extends RigidBody3D

enum PossessionState {
	LOOSE,
	POSSESSED,
}

enum TurnState {
	NORMAL_DRIBBLE,
	PREPARE_TURN,
	CONTROL_TOUCH,
	EXIT_TURN,
}

enum FootSide {
	LEFT = -1,
	RIGHT = 1,
}

const PLAYER_COLLISION_LAYER: int = 2
const BALL_COLLISION_LAYER: int = 3

@export_group("Physics")
@export var ball_mass: float = 0.43
@export var linear_damping: float = 0.5
@export var angular_damping: float = 0.8
@export var friction: float = 0.8
@export var bounce: float = 0.6
@export var max_speed: float = 15.0

@export_group("Possession")
@export var possession_acquisition_radius: float = 1.1
@export var normal_control_radius: float = 2.0
@export var emergency_recovery_radius: float = 3.6
@export var loose_ball_max_controllable_speed: float = 4.0
@export var loose_ball_max_ground_height: float = 0.6
@export var reacquisition_cooldown: float = 0.25

@export_group("Touch Dribbling")
@export var walk_touch_distance: float = 0.45
@export var jog_touch_distance: float = 0.75
@export var sprint_touch_distance: float = 1.4
@export var walk_touch_interval: float = 0.18
@export var jog_touch_interval: float = 0.24
@export var sprint_touch_interval: float = 0.34

@export_group("Turn Control")
@export var mild_turn_speed_multiplier: float = 0.82
@export var sharp_turn_speed_multiplier: float = 0.55
@export var turn_entry_duration: float = 0.12
@export var control_touch_duration: float = 0.18
@export var turn_exit_duration: float = 0.14
@export var preferred_foot_side: FootSide = FootSide.RIGHT
@export var possession_ball_side_offset: float = 0.42
@export var sharp_turn_angle_threshold: float = 90.0
@export var full_turn_angle_threshold: float = 135.0
@export var turn_ball_distance: float = 0.32
@export var turn_rotation_speed: float = 14.0

@export_group("Control Forces")
@export var turn_control_strength: float = 1.35
@export var forward_control_strength: float = 5.5
@export var lateral_control_strength: float = 4.5
@export var stop_control_strength: float = 7.0
@export var maximum_recovery_force: float = 22.0
@export var external_impulse_release_threshold: float = 9.0
@export var stationary_ball_offset: float = 0.38

@export_group("Debug")
@export var debug_enabled: bool = false

var _physics_material: PhysicsMaterial
var _player: PlayerCharacter = null
var _possession_state: PossessionState = PossessionState.LOOSE
var _possessor: PlayerCharacter = null
var _touch_cooldown: float = 0.0
var _expected_flat_velocity: Vector3 = Vector3.ZERO
var _reacquire_cooldown: float = 0.0
var _possession_grace_timer: float = 0.0
var _emergency_recovery_active: bool = false
var _possession_collision_exempt: bool = false
var _default_ball_collision_mask: int = 0
var _default_player_collision_mask: int = 0
var _turn_state: TurnState = TurnState.NORMAL_DRIBBLE
var _turn_state_timer: float = 0.0
var _stable_dribble_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
var _target_turn_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
var _current_turn_angle: float = 0.0
var _debug_target: Vector3 = Vector3.ZERO
var _debug_target_marker: MeshInstance3D
var _debug_label: Label3D

@onready var _acquisition_area: Area3D = $AcquisitionArea
@onready var _acquisition_shape: CollisionShape3D = $AcquisitionArea/CollisionShape3D


func _ready() -> void:
	mass = ball_mass
	linear_damp = linear_damping
	angular_damp = angular_damping
	continuous_cd = true

	_physics_material = PhysicsMaterial.new()
	_physics_material.friction = friction
	_physics_material.bounce = bounce
	physics_material_override = _physics_material

	_default_ball_collision_mask = collision_mask
	_update_acquisition_area_radius()

	call_deferred("_resolve_player")
	call_deferred("_setup_debug_visuals")


func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return

	var candidate: Node = get_tree().get_first_node_in_group("player")
	if candidate is PlayerCharacter:
		_player = candidate
		_default_player_collision_mask = _player.collision_mask
		_debug_acquisition("Resolved PlayerCharacter: %s" % _player.name)
	elif candidate != null:
		_debug_acquisition("Player group node is not PlayerCharacter: %s" % candidate.get_class())
	else:
		_debug_acquisition("No node found in group 'player'")


func _update_acquisition_area_radius() -> void:
	if _acquisition_shape == null or _acquisition_shape.shape is not SphereShape3D:
		return
	var sphere: SphereShape3D = _acquisition_shape.shape as SphereShape3D
	sphere.radius = possession_acquisition_radius


func _setup_debug_visuals() -> void:
	if not debug_enabled:
		return

	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.09
	sphere_mesh.height = 0.18

	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = Color(1.0, 0.85, 0.1, 0.9)
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_debug_target_marker = MeshInstance3D.new()
	_debug_target_marker.mesh = sphere_mesh
	_debug_target_marker.material_override = marker_material
	_debug_target_marker.visible = false
	get_parent().call_deferred("add_child", _debug_target_marker)

	_debug_label = Label3D.new()
	_debug_label.font_size = 16
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_label.visible = false
	add_child.call_deferred(_debug_label)


func _physics_process(delta: float) -> void:
	_touch_cooldown = maxf(_touch_cooldown - delta, 0.0)
	_reacquire_cooldown = maxf(_reacquire_cooldown - delta, 0.0)
	_possession_grace_timer = maxf(_possession_grace_timer - delta, 0.0)

	if _player == null:
		_resolve_player()

	if _possession_state == PossessionState.LOOSE:
		_restore_loose_ball_collision()

	_update_possession_state()
	if _possession_state == PossessionState.POSSESSED and _possessor != null:
		_update_turn_state(delta)
	_update_debug_visuals()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if state.sleeping and _possession_state == PossessionState.POSSESSED:
		state.sleeping = false

	if _possession_state == PossessionState.POSSESSED and _possessor != null:
		_apply_possession_dribble(state)

	var linear_velocity: Vector3 = state.linear_velocity
	if linear_velocity.length() > max_speed:
		state.linear_velocity = linear_velocity.normalized() * max_speed


func has_possession() -> bool:
	return _possession_state == PossessionState.POSSESSED


func get_possessor() -> PlayerCharacter:
	return _possessor


func get_possession_state() -> PossessionState:
	return _possession_state


func get_turn_state() -> TurnState:
	return _turn_state


func release_for_pass() -> void:
	_release_possession(true)


func release_for_shot() -> void:
	_release_possession(true)


func release_for_tackle() -> void:
	_release_possession(true)


func release_for_deflection() -> void:
	_release_possession(true)


func release_as_loose_ball() -> void:
	_release_possession(true)


func _release_possession(apply_reacquire_cooldown: bool = true) -> void:
	var releasing_possessor: PlayerCharacter = _possessor
	_restore_loose_ball_collision(releasing_possessor)
	if releasing_possessor != null and releasing_possessor.has_method("notify_possession_lost"):
		releasing_possessor.notify_possession_lost()
	_possession_state = PossessionState.LOOSE
	_possessor = null
	_emergency_recovery_active = false
	if apply_reacquire_cooldown:
		_reacquire_cooldown = reacquisition_cooldown
	_expected_flat_velocity = Vector3.ZERO
	_turn_state = TurnState.NORMAL_DRIBBLE
	_turn_state_timer = 0.0
	_debug_acquisition("Possession released")


func _acquire_possession(player: PlayerCharacter) -> void:
	_possession_state = PossessionState.POSSESSED
	_possessor = player
	_touch_cooldown = 0.0
	_turn_state = TurnState.NORMAL_DRIBBLE
	_turn_state_timer = 0.0
	_stable_dribble_direction = _get_primary_control_direction()
	if player.has_method("notify_possession_gained"):
		player.notify_possession_gained(self)
	_apply_possession_collision_exempt()
	_possession_grace_timer = 0.35
	_debug_acquisition("Possession acquired by %s" % player.name)


func _restore_loose_ball_collision(player: PlayerCharacter = null) -> void:
	var target_player: PlayerCharacter = player if player != null else _player
	collision_mask = _default_ball_collision_mask
	set_collision_mask_value(PLAYER_COLLISION_LAYER, true)
	if target_player != null and is_instance_valid(target_player):
		target_player.collision_mask = _default_player_collision_mask
		target_player.set_collision_mask_value(BALL_COLLISION_LAYER, true)
	_possession_collision_exempt = false


func _apply_possession_collision_exempt() -> void:
	if _possessor == null:
		return
	_possessor.set_collision_mask_value(BALL_COLLISION_LAYER, false)
	set_collision_mask_value(PLAYER_COLLISION_LAYER, false)
	_possession_collision_exempt = true


func _update_possession_state() -> void:
	if _possession_state == PossessionState.LOOSE:
		if _reacquire_cooldown > 0.0:
			_debug_acquisition("Acquisition blocked by cooldown: %.2fs" % _reacquire_cooldown)
			return
		_try_acquire_from_candidates()
		return

	if _possessor == null:
		_release_possession(false)
		return

	var distance_to_possessor: float = _flat_distance_to(_possessor.global_position)
	_emergency_recovery_active = distance_to_possessor > normal_control_radius

	if distance_to_possessor > emergency_recovery_radius:
		_debug_acquisition("Emergency release: distance %.2f" % distance_to_possessor)
		release_as_loose_ball()
		return

	if _detect_external_impulse():
		_debug_acquisition("External impulse release")
		release_as_loose_ball()


func _try_acquire_from_candidates() -> void:
	var candidates: Array[PlayerCharacter] = _get_acquisition_candidates()
	if candidates.is_empty():
		return

	for candidate: PlayerCharacter in candidates:
		var distance: float = _flat_distance_to(candidate.global_position)
		_debug_acquisition("Candidate detected: %s distance %.2f" % [candidate.name, distance])
		if not _passes_acquisition_conditions(candidate, distance):
			continue
		_acquire_possession(candidate)
		return


func _get_acquisition_candidates() -> Array[PlayerCharacter]:
	var candidates: Array[PlayerCharacter] = []

	if _acquisition_area != null:
		for body: Node3D in _acquisition_area.get_overlapping_bodies():
			if body is PlayerCharacter and body not in candidates:
				candidates.append(body)

	if _player != null and _player not in candidates:
		var distance: float = _flat_distance_to(_player.global_position)
		if distance <= possession_acquisition_radius:
			candidates.append(_player)

	return candidates


func _passes_acquisition_conditions(candidate: PlayerCharacter, distance: float) -> bool:
	if distance > possession_acquisition_radius:
		_debug_acquisition("Failed: outside radius (%.2f > %.2f)" % [distance, possession_acquisition_radius])
		return false
	if global_position.y > loose_ball_max_ground_height:
		_debug_acquisition("Failed: ball too high (y=%.2f)" % global_position.y)
		return false
	if _get_flat_speed() > loose_ball_max_controllable_speed:
		_debug_acquisition("Failed: ball too fast (%.2f)" % _get_flat_speed())
		return false
	if candidate == null or not is_instance_valid(candidate):
		_debug_acquisition("Failed: invalid candidate")
		return false

	_debug_acquisition("Acquisition conditions passed for %s" % candidate.name)
	return true


func _debug_acquisition(message: String) -> void:
	if debug_enabled:
		print("[Ball Acquisition] ", message)


func _update_turn_state(delta: float) -> void:
	_current_turn_angle = _get_requested_turn_angle()
	var turn_degrees: float = rad_to_deg(_current_turn_angle)

	match _turn_state:
		TurnState.NORMAL_DRIBBLE:
			_apply_normal_turn_modifiers(turn_degrees)
			if turn_degrees < 30.0 and _possessor.has_movement_input():
				_stable_dribble_direction = _possessor.get_requested_move_direction()
			if _should_begin_turn_sequence(turn_degrees):
				_begin_turn_sequence()
		TurnState.PREPARE_TURN:
			_apply_turn_phase_modifiers(true)
			_turn_state_timer -= delta
			if _turn_state_timer <= 0.0:
				_turn_state = TurnState.CONTROL_TOUCH
				_turn_state_timer = control_touch_duration
		TurnState.CONTROL_TOUCH:
			_apply_turn_phase_modifiers(true)
			_turn_state_timer -= delta
			if _turn_state_timer <= 0.0:
				_turn_state = TurnState.EXIT_TURN
				_turn_state_timer = turn_exit_duration
		TurnState.EXIT_TURN:
			_apply_turn_phase_modifiers(false)
			_turn_state_timer -= delta
			if _turn_state_timer <= 0.0:
				_finish_turn_sequence()


func _apply_normal_turn_modifiers(turn_degrees: float) -> void:
	if not _possessor.has_movement_input():
		_possessor.set_dribble_speed_multiplier(1.0)
		return

	if turn_degrees < 30.0:
		_possessor.set_dribble_speed_multiplier(1.0)
	elif turn_degrees < sharp_turn_angle_threshold:
		_possessor.set_dribble_speed_multiplier(mild_turn_speed_multiplier)
	else:
		_possessor.set_dribble_speed_multiplier(mild_turn_speed_multiplier)


func _should_begin_turn_sequence(turn_degrees: float) -> bool:
	if turn_degrees < sharp_turn_angle_threshold:
		return false
	if not _possessor.has_movement_input():
		return false
	if _possessor.get_movement_state() == PlayerCharacter.MovementState.STATIONARY:
		return false
	return true


func _begin_turn_sequence() -> void:
	_target_turn_direction = _possessor.get_requested_move_direction()
	_turn_state = TurnState.PREPARE_TURN
	_turn_state_timer = turn_entry_duration
	var turn_degrees: float = rad_to_deg(_current_turn_angle)
	var speed_multiplier: float = sharp_turn_speed_multiplier
	if turn_degrees < full_turn_angle_threshold:
		speed_multiplier = lerpf(mild_turn_speed_multiplier, sharp_turn_speed_multiplier, 0.65)
	_possessor.set_dribble_speed_multiplier(speed_multiplier)
	_possessor.set_dribble_rotation_speed(turn_rotation_speed)


func _apply_turn_phase_modifiers(full_control: bool) -> void:
	var turn_degrees: float = rad_to_deg(_current_turn_angle)
	var speed_multiplier: float = sharp_turn_speed_multiplier
	if turn_degrees < full_turn_angle_threshold:
		speed_multiplier = lerpf(mild_turn_speed_multiplier, sharp_turn_speed_multiplier, 0.75)
	_possessor.set_dribble_speed_multiplier(speed_multiplier if full_control else lerpf(speed_multiplier, 1.0, 0.35))
	_possessor.set_dribble_rotation_speed(turn_rotation_speed)


func _finish_turn_sequence() -> void:
	_turn_state = TurnState.NORMAL_DRIBBLE
	_turn_state_timer = 0.0
	_stable_dribble_direction = _target_turn_direction
	_possessor.set_dribble_speed_multiplier(1.0)
	_possessor.set_dribble_rotation_speed(-1.0)


func _get_requested_turn_angle() -> float:
	if _possessor == null or not _possessor.has_movement_input():
		return 0.0
	return _stable_dribble_direction.angle_to(_possessor.get_requested_move_direction())


func _get_primary_control_direction() -> Vector3:
	if _possessor == null:
		return Vector3(0.0, 0.0, -1.0)
	if _possessor.has_movement_input():
		return _possessor.get_requested_move_direction()
	return _possessor.get_facing_direction()


func _detect_external_impulse() -> bool:
	if _possession_grace_timer > 0.0:
		return false
	if _turn_state != TurnState.NORMAL_DRIBBLE:
		return false
	var actual: Vector3 = _get_flat_velocity()
	var delta_velocity: float = (actual - _expected_flat_velocity).length()
	return delta_velocity > external_impulse_release_threshold


func _apply_possession_dribble(state: PhysicsDirectBodyState3D) -> void:
	var movement_state: PlayerCharacter.MovementState = _possessor.get_movement_state()
	var dribble_target: Vector3 = _compute_dribble_target(movement_state)
	_debug_target = dribble_target

	var ball_flat: Vector3 = _flat_position(state.transform.origin)
	var target_flat: Vector3 = Vector3(dribble_target.x, 0.0, dribble_target.z)
	var to_target: Vector3 = target_flat - ball_flat
	var distance_to_possessor: float = _flat_distance_to(_possessor.global_position)

	var guidance_strength: float = _get_guidance_strength(movement_state)
	var control_dir: Vector3 = _get_active_control_direction()
	var forward_axis: Vector3 = control_dir
	var forward_error: float = forward_axis.dot(to_target)
	var lateral_error: Vector3 = to_target - forward_axis * forward_error
	var current_flat_velocity: Vector3 = Vector3(state.linear_velocity.x, 0.0, state.linear_velocity.z)
	var desired_velocity: Vector3 = forward_axis * _possessor.get_flat_velocity().length() * _possessor.get_dribble_speed_multiplier()

	if movement_state == PlayerCharacter.MovementState.STATIONARY:
		desired_velocity = Vector3.ZERO
		guidance_strength = stop_control_strength
	elif movement_state == PlayerCharacter.MovementState.STOPPING:
		desired_velocity *= 0.35
		guidance_strength = stop_control_strength

	var velocity_error: Vector3 = desired_velocity - current_flat_velocity
	var forward_force: Vector3 = forward_axis * forward_error * forward_control_strength
	var lateral_force: Vector3 = lateral_error * lateral_control_strength
	var velocity_force: Vector3 = velocity_error * guidance_strength
	var total_force: Vector3 = forward_force + lateral_force + velocity_force

	if _emergency_recovery_active and _turn_state == TurnState.NORMAL_DRIBBLE:
		var recovery_scale: float = clampf(
			(distance_to_possessor - normal_control_radius)
			/ maxf(emergency_recovery_radius - normal_control_radius, 0.001),
			0.0,
			0.45
		)
		total_force += to_target.normalized() * maximum_recovery_force * recovery_scale * 0.35

	total_force = total_force.limit_length(maximum_recovery_force)
	total_force *= mass
	state.apply_central_force(total_force)
	_expected_flat_velocity = desired_velocity

	if _touch_cooldown <= 0.0:
		_apply_touch(state, to_target, movement_state)
		_touch_cooldown = _get_touch_interval(movement_state)


func _apply_touch(state: PhysicsDirectBodyState3D, to_target: Vector3, movement_state: PlayerCharacter.MovementState) -> void:
	if to_target.length_squared() < 0.0004:
		return

	var touch_direction: Vector3 = to_target.normalized()
	var touch_strength: float = 0.22
	match movement_state:
		PlayerCharacter.MovementState.WALK:
			touch_strength = 0.18
		PlayerCharacter.MovementState.JOG:
			touch_strength = 0.24
		PlayerCharacter.MovementState.SPRINT:
			touch_strength = 0.34
		PlayerCharacter.MovementState.STATIONARY, PlayerCharacter.MovementState.STOPPING:
			touch_strength = 0.1

	if _turn_state == TurnState.CONTROL_TOUCH:
		touch_strength = 0.28
	elif _turn_state == TurnState.PREPARE_TURN:
		touch_strength = 0.16

	state.apply_central_impulse(touch_direction * touch_strength * mass)


func _get_active_control_direction() -> Vector3:
	if _turn_state == TurnState.NORMAL_DRIBBLE:
		if _possessor.has_movement_input():
			return _possessor.get_requested_move_direction()
		return _possessor.get_facing_direction()

	var blend: float = 0.0
	match _turn_state:
		TurnState.PREPARE_TURN:
			blend = 0.25
		TurnState.CONTROL_TOUCH:
			blend = 0.72
		TurnState.EXIT_TURN:
			blend = 0.9

	return _stable_dribble_direction.lerp(_target_turn_direction, blend).normalized()


func _compute_dribble_target(movement_state: PlayerCharacter.MovementState) -> Vector3:
	var player_pos: Vector3 = _possessor.global_position
	var player_flat: Vector3 = Vector3(player_pos.x, 0.0, player_pos.z)
	var control_dir: Vector3 = _get_active_control_direction()
	var turn_sign: float = _possessor.get_turn_sign()
	var turn_degrees: float = rad_to_deg(_current_turn_angle)

	var touch_distance: float = _get_touch_distance(movement_state)
	if turn_degrees >= 30.0 and turn_degrees < sharp_turn_angle_threshold:
		touch_distance = lerpf(touch_distance, turn_ball_distance + 0.08, 0.45)
	if _turn_state != TurnState.NORMAL_DRIBBLE:
		touch_distance = turn_ball_distance

	var right_dir: Vector3 = Vector3.UP.cross(control_dir).normalized()
	var foot_side: float = float(preferred_foot_side)
	var foot_offset: Vector3 = right_dir * possession_ball_side_offset * foot_side

	if _turn_state == TurnState.CONTROL_TOUCH:
		var across_body: float = clampf(turn_degrees / 180.0, 0.35, 1.0)
		foot_offset = foot_offset.lerp(right_dir * turn_sign * possession_ball_side_offset * 1.15, across_body)
	elif _turn_state == TurnState.PREPARE_TURN:
		foot_offset *= 0.65

	if movement_state == PlayerCharacter.MovementState.STATIONARY:
		touch_distance = stationary_ball_offset
		control_dir = _possessor.get_facing_direction()
		foot_offset = right_dir * possession_ball_side_offset * foot_side * 0.85
	elif movement_state == PlayerCharacter.MovementState.STOPPING:
		touch_distance = lerpf(stationary_ball_offset, touch_distance, 0.35)
		control_dir = control_dir.lerp(_possessor.get_facing_direction(), 0.45).normalized()

	var target_flat: Vector3 = player_flat + control_dir * touch_distance + foot_offset
	target_flat.y = player_pos.y + 0.11
	return target_flat


func _get_touch_distance(movement_state: PlayerCharacter.MovementState) -> float:
	match movement_state:
		PlayerCharacter.MovementState.SPRINT:
			return sprint_touch_distance
		PlayerCharacter.MovementState.JOG:
			return jog_touch_distance
		PlayerCharacter.MovementState.STATIONARY, PlayerCharacter.MovementState.STOPPING:
			return stationary_ball_offset
		_:
			return walk_touch_distance


func _get_touch_interval(movement_state: PlayerCharacter.MovementState) -> float:
	match movement_state:
		PlayerCharacter.MovementState.SPRINT:
			return sprint_touch_interval
		PlayerCharacter.MovementState.JOG:
			return jog_touch_interval
		PlayerCharacter.MovementState.STATIONARY, PlayerCharacter.MovementState.STOPPING:
			return walk_touch_interval * 1.4
		_:
			return walk_touch_interval


func _get_guidance_strength(movement_state: PlayerCharacter.MovementState) -> float:
	match movement_state:
		PlayerCharacter.MovementState.STATIONARY, PlayerCharacter.MovementState.STOPPING:
			return stop_control_strength
		PlayerCharacter.MovementState.SPRINT:
			return forward_control_strength * 0.85
		_:
			return forward_control_strength


func _flat_position(world_position: Vector3) -> Vector3:
	return Vector3(world_position.x, 0.0, world_position.z)


func _flat_distance_to(world_position: Vector3) -> float:
	return _flat_position(global_position).distance_to(_flat_position(world_position))


func _get_flat_velocity() -> Vector3:
	return Vector3(linear_velocity.x, 0.0, linear_velocity.z)


func _get_flat_speed() -> float:
	return _get_flat_velocity().length()


func _turn_state_name() -> String:
	match _turn_state:
		TurnState.NORMAL_DRIBBLE:
			return "NORMAL_DRIBBLE"
		TurnState.PREPARE_TURN:
			return "PREPARE_TURN"
		TurnState.CONTROL_TOUCH:
			return "CONTROL_TOUCH"
		TurnState.EXIT_TURN:
			return "EXIT_TURN"
		_:
			return "UNKNOWN"


func _update_debug_visuals() -> void:
	if not debug_enabled:
		if _debug_target_marker != null:
			_debug_target_marker.visible = false
		if _debug_label != null:
			_debug_label.visible = false
		return

	if _debug_target_marker != null:
		_debug_target_marker.visible = true
		_debug_target_marker.global_position = _debug_target

	if _debug_label != null:
		_debug_label.visible = true
		_debug_label.global_position = global_position + Vector3(0.0, 1.8, 0.0)
		var requested: String = "n/a"
		var facing: String = "n/a"
		if _possessor != null:
			requested = str(_possessor.get_requested_move_direction().round())
			facing = str(_possessor.get_facing_direction().round())
		_debug_label.text = (
			"Possession: %s\nTurn: %s\nAngle: %.1f\nRequested: %s\nFacing: %s\nTarget: %s\nCollision assist: %s"
			% [
				"POSSESSED" if _possession_state == PossessionState.POSSESSED else "LOOSE",
				_turn_state_name(),
				rad_to_deg(_current_turn_angle),
				requested,
				facing,
				str(_debug_target.round()),
				str(_possession_collision_exempt),
			]
		)
