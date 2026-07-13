extends CharacterBody3D
class_name PlayerCharacter

enum MovementState {
	STATIONARY,
	WALK,
	JOG,
	SPRINT,
	STOPPING,
}

const LOOSE_PLAYER_LAYER: int = 2
const LOOSE_PLAYER_MASK: int = 5
const POSSESSION_AREA_MASK: int = 4

@export var is_user_controlled: bool = true
@export var team_id: int = 0
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var acceleration: float = 12.0
@export var rotation_speed: float = 10.0
@export var gravity: float = 9.8
@export var short_pass_speed: float = 9.0
@export var min_shot_speed: float = 8.0
@export var max_shot_speed: float = 18.0
@export var max_shot_charge_time: float = 1.0
@export var possession_debug_enabled: bool = true

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var _possession_area: Area3D = $PossessionArea
@onready var _possession_debug_label: Label3D = $DebugLabel

var _camera: Camera3D
var _last_move_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
var _requested_move_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
var _possessed_ball: Node3D = null
var _dribble_speed_multiplier: float = 1.0
var _dribble_rotation_speed: float = -1.0
var _tracked_ball: Node3D = null
var _is_charging_shot: bool = false
var _shot_charge_time: float = 0.0
var _match_controls_enabled: bool = true
var _possession_acquisition_enabled: bool = true


func _ready() -> void:
	collision_layer = LOOSE_PLAYER_LAYER
	collision_mask = LOOSE_PLAYER_MASK

	_camera = get_tree().get_first_node_in_group("broadcast_camera") as Camera3D
	_last_move_direction = get_facing_direction()
	_requested_move_direction = _last_move_direction

	_possession_area.body_entered.connect(_on_possession_area_body_entered)
	_possession_debug_label.visible = possession_debug_enabled
	$PossessionArea/DebugMesh.visible = possession_debug_enabled

	call_deferred("_run_startup_self_check")


func _physics_process(delta: float) -> void:
	if is_user_controlled and _match_controls_enabled:
		_update_requested_move_direction()

	var input_dir: Vector2 = Vector2.ZERO
	if is_user_controlled and _match_controls_enabled:
		input_dir = Input.get_vector(
			InputActions.MOVE_LEFT,
			InputActions.MOVE_RIGHT,
			InputActions.MOVE_FORWARD,
			InputActions.MOVE_BACK
		)
	var direction: Vector3 = Vector3.ZERO

	if input_dir.length_squared() > 0.0 and _camera != null:
		var cam_basis: Basis = _camera.global_transform.basis
		direction = cam_basis * Vector3(input_dir.x, 0.0, input_dir.y)
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			direction = direction.normalized()

	var sprint_strength: float = get_sprint_strength()
	var target_speed: float = lerpf(walk_speed, sprint_speed, sprint_strength) * _dribble_speed_multiplier

	if direction.length_squared() > 0.0:
		velocity.x = move_toward(velocity.x, direction.x * target_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * target_speed, acceleration * delta)
		_rotate_toward_direction(direction, delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	move_and_slide()
	_update_last_move_direction()

	if not has_possession() and _possession_acquisition_enabled:
		for body: Node3D in _possession_area.get_overlapping_bodies():
			_try_acquire_from_body(body)

	if is_user_controlled and _match_controls_enabled and has_possession():
		_update_shot_input(delta)
		if Input.is_action_just_pressed(InputActions.SHORT_PASS):
			_cancel_shot_charge()
			perform_short_pass()
	elif is_user_controlled:
		_cancel_shot_charge()

	_update_possession_debug()


func _on_possession_area_body_entered(body: Node3D) -> void:
	_try_acquire_from_body(body)


func _try_acquire_from_body(body: Node3D) -> void:
	if has_possession():
		return
	if not body.is_in_group("soccer_ball"):
		return
	if body.has_method("is_loose") and not body.is_loose():
		return
	if not body.has_method("try_acquire_possession"):
		return
	body.try_acquire_possession(self)


func _run_startup_self_check() -> void:
	var ball: Node = get_tree().get_first_node_in_group("soccer_ball")
	var checks_ok: bool = true

	print("[Startup Check] Player layer=%d mask=%d" % [collision_layer, collision_mask])
	if ball != null:
		print(
			"[Startup Check] Ball layer=%d mask=%d in_group=%s"
			% [ball.collision_layer, ball.collision_mask, ball.is_in_group("soccer_ball")]
		)
	else:
		push_error("[Startup Check] ERROR: No node in group 'soccer_ball'")
		checks_ok = false

	print(
		"[Startup Check] PossessionArea layer=%d mask=%d monitoring=%s"
		% [_possession_area.collision_layer, _possession_area.collision_mask, str(_possession_area.monitoring)]
	)

	if collision_layer != LOOSE_PLAYER_LAYER:
		push_error("[Startup Check] ERROR: Player layer should be %d" % LOOSE_PLAYER_LAYER)
		checks_ok = false
	if collision_mask != LOOSE_PLAYER_MASK:
		push_error("[Startup Check] ERROR: Player mask should be %d" % LOOSE_PLAYER_MASK)
		checks_ok = false
	if ball != null and ball.collision_layer != 4:
		push_error("[Startup Check] ERROR: Ball layer should be 4 (layer 3)")
		checks_ok = false
	if ball != null and ball.collision_mask != 3:
		push_error("[Startup Check] ERROR: Ball mask should be 3")
		checks_ok = false
	if _possession_area.collision_mask != POSSESSION_AREA_MASK:
		push_error("[Startup Check] ERROR: PossessionArea mask should be %d" % POSSESSION_AREA_MASK)
		checks_ok = false
	if not _possession_area.monitoring:
		push_error("[Startup Check] ERROR: PossessionArea monitoring is disabled")
		checks_ok = false
	if ball != null and not ball.is_in_group("soccer_ball"):
		push_error("[Startup Check] ERROR: Ball is not in group 'soccer_ball'")
		checks_ok = false

	if checks_ok:
		print("[Startup Check] All possession collision checks passed")


func _update_possession_debug() -> void:
	if not possession_debug_enabled:
		return

	_tracked_ball = _find_nearest_soccer_ball()
	var ball_detected: bool = _tracked_ball != null
	var ball_state: String = "n/a"
	var distance: float = -1.0

	if _tracked_ball != null:
		distance = global_position.distance_to(_tracked_ball.global_position)
		if _tracked_ball.has_method("get_possession_state_name"):
			ball_state = _tracked_ball.get_possession_state_name()

	_possession_debug_label.text = (
		"ball detected: %s\nball state: %s\npossession acquired: %s\ndistance: %.2f"
		% [
			"yes" if ball_detected else "no",
			ball_state,
			"yes" if has_possession() else "no",
			distance,
		]
	)


func _find_nearest_soccer_ball() -> Node3D:
	var nearest: Node3D = null
	var nearest_distance: float = INF
	for body: Node3D in _possession_area.get_overlapping_bodies():
		if not body.is_in_group("soccer_ball"):
			continue
		var distance: float = global_position.distance_to(body.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = body
	return nearest


func has_possession() -> bool:
	return _possessed_ball != null


func get_possessed_ball() -> Node3D:
	return _possessed_ball


func notify_possession_gained(ball: Node3D) -> void:
	_possessed_ball = ball


func notify_possession_lost() -> void:
	_possessed_ball = null
	_cancel_shot_charge()
	reset_dribble_modifiers()


func reset_dribble_modifiers() -> void:
	_dribble_speed_multiplier = 1.0
	_dribble_rotation_speed = -1.0


func set_dribble_speed_multiplier(multiplier: float) -> void:
	_dribble_speed_multiplier = clampf(multiplier, 0.15, 1.0)


func set_dribble_rotation_speed(speed: float) -> void:
	_dribble_rotation_speed = maxf(speed, 0.0)


func get_dribble_speed_multiplier() -> float:
	return _dribble_speed_multiplier


func get_team_id() -> int:
	return team_id


func is_same_team(other: PlayerCharacter) -> bool:
	return other != null and other.team_id == team_id


func set_match_controls_enabled(enabled: bool) -> void:
	_match_controls_enabled = enabled
	if not enabled:
		_cancel_shot_charge()
		velocity = Vector3.ZERO


func set_possession_acquisition_enabled(enabled: bool) -> void:
	_possession_acquisition_enabled = enabled


func reset_to_kickoff(position: Vector3) -> void:
	global_position = position
	velocity = Vector3.ZERO


func perform_short_pass() -> void:
	var ball: Node3D = _possessed_ball
	if ball == null or not ball.has_method("perform_pass"):
		return
	ball.perform_pass(_get_pass_direction(), short_pass_speed)


func perform_charged_shot(charge_time: float) -> void:
	var ball: Node3D = _possessed_ball
	if ball == null or not ball.has_method("perform_shot"):
		return
	ball.perform_shot(_get_shot_direction(), get_charged_shot_speed(charge_time))


func get_charged_shot_speed(charge_time: float) -> float:
	var charge_ratio: float = clampf(charge_time / maxf(max_shot_charge_time, 0.001), 0.0, 1.0)
	return lerpf(min_shot_speed, max_shot_speed, charge_ratio)


func _update_shot_input(delta: float) -> void:
	if Input.is_action_just_pressed(InputActions.SHOOT):
		_is_charging_shot = true
		_shot_charge_time = 0.0

	if not _is_charging_shot:
		return

	if Input.is_action_pressed(InputActions.SHOOT):
		_shot_charge_time = minf(_shot_charge_time + delta, max_shot_charge_time)

	if Input.is_action_just_released(InputActions.SHOOT):
		perform_charged_shot(_shot_charge_time)
		_cancel_shot_charge()


func _cancel_shot_charge() -> void:
	_is_charging_shot = false
	_shot_charge_time = 0.0


func _get_pass_direction() -> Vector3:
	if has_movement_input():
		return get_requested_move_direction()

	var teammate: PlayerCharacter = _find_nearest_teammate()
	if teammate != null:
		var to_teammate: Vector3 = teammate.global_position - global_position
		to_teammate.y = 0.0
		if to_teammate.length_squared() > 0.0001:
			return to_teammate.normalized()

	return get_facing_direction()


func _get_shot_direction() -> Vector3:
	if has_movement_input():
		return get_requested_move_direction()
	return get_facing_direction()


func _find_nearest_teammate() -> PlayerCharacter:
	var nearest: PlayerCharacter = null
	var nearest_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group("player"):
		if node == self or node is not PlayerCharacter:
			continue
		var other: PlayerCharacter = node
		if not is_same_team(other):
			continue
		var distance: float = global_position.distance_to(other.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = other
	return nearest


func has_movement_input() -> bool:
	if not is_user_controlled:
		return false
	return Input.get_vector(
		InputActions.MOVE_LEFT,
		InputActions.MOVE_RIGHT,
		InputActions.MOVE_FORWARD,
		InputActions.MOVE_BACK
	).length_squared() > 0.01


func is_moving(threshold: float = 0.5) -> bool:
	return get_flat_velocity().length() >= threshold


func get_flat_velocity() -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)


func get_facing_direction() -> Vector3:
	var facing: Vector3 = -global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() > 0.0001:
		return facing.normalized()
	return Vector3(0.0, 0.0, -1.0)


func get_requested_move_direction() -> Vector3:
	return _requested_move_direction


func get_move_direction() -> Vector3:
	var flat_velocity: Vector3 = get_flat_velocity()
	if flat_velocity.length_squared() > 0.0001:
		return flat_velocity.normalized()
	if has_movement_input():
		return _requested_move_direction
	return get_facing_direction()


func get_sprint_strength() -> float:
	if not is_user_controlled:
		return 0.0
	return Input.get_action_strength(InputActions.SPRINT)


func get_movement_state() -> MovementState:
	var speed: float = get_flat_velocity().length()
	if speed < 0.25:
		return MovementState.STATIONARY
	if not has_movement_input() and speed > 0.35:
		return MovementState.STOPPING
	if get_sprint_strength() > 0.5 and speed > walk_speed * 0.6:
		return MovementState.SPRINT
	if speed >= walk_speed * 0.75:
		return MovementState.JOG
	return MovementState.WALK


func get_turn_angle() -> float:
	return _last_move_direction.angle_to(get_requested_move_direction())


func get_turn_sign() -> float:
	var requested: Vector3 = get_requested_move_direction()
	var cross_y: float = _last_move_direction.cross(requested).y
	if absf(cross_y) < 0.0001:
		return 0.0
	return signf(cross_y)


func is_stopping() -> bool:
	return get_movement_state() == MovementState.STOPPING


func _update_requested_move_direction() -> void:
	var input_dir: Vector2 = Input.get_vector(
		InputActions.MOVE_LEFT,
		InputActions.MOVE_RIGHT,
		InputActions.MOVE_FORWARD,
		InputActions.MOVE_BACK
	)
	if input_dir.length_squared() <= 0.01 or _camera == null:
		return

	var cam_basis: Basis = _camera.global_transform.basis
	var direction: Vector3 = cam_basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		_requested_move_direction = direction.normalized()


func _update_last_move_direction() -> void:
	var speed: float = get_flat_velocity().length()
	if speed > 0.35:
		_last_move_direction = get_move_direction()


func _rotate_toward_direction(direction: Vector3, delta: float) -> void:
	var target_rotation: float = atan2(direction.x, direction.z)
	var current_rotation: float = mesh.rotation.y
	var active_rotation_speed: float = rotation_speed if _dribble_rotation_speed < 0.0 else _dribble_rotation_speed
	mesh.rotation.y = lerp_angle(current_rotation, target_rotation, active_rotation_speed * delta)
