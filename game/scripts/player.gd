extends CharacterBody3D
class_name PlayerCharacter

enum MovementState {
	STATIONARY,
	WALK,
	JOG,
	SPRINT,
	STOPPING,
}

enum AIState {
	IDLE,
	SUPPORT,
	DEFEND,
	PURSUE_LOOSE,
	PRESSURE,
	DRIBBLE_ATTACK,
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

@export_group("Pass Targeting")
@export var pass_target_max_angle: float = 65.0
@export var pass_target_distance_weight: float = 0.08
@export var pass_target_angle_weight: float = 1.0
@export var behind_target_penalty: float = 8.0
@export var manual_pass_assist_strength: float = 1.0
@export var pass_target_max_distance: float = 18.0

@export_group("Field AI")
@export var ai_enabled: bool = true
@export var ai_debug_enabled: bool = false
@export var ai_decision_interval: float = 0.2
@export var ai_move_speed: float = 4.2
@export var ai_acceleration: float = 10.0
@export var ai_support_distance: float = 4.0
@export var ai_pressure_distance: float = 2.2
@export var ai_loose_ball_pursuit_radius: float = 14.0
@export var ai_min_teammate_spacing: float = 2.2
@export var ai_field_half_x: float = 10.0
@export var ai_field_half_z: float = 6.2

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var _possession_area: Area3D = $PossessionArea
@onready var _possession_debug_label: Label3D = $DebugLabel

var _camera: Camera3D
var _last_move_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
var _requested_move_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
var _facing_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
var _possessed_ball: Node3D = null
var _dribble_speed_multiplier: float = 1.0
var _dribble_rotation_speed: float = -1.0
var _tracked_ball: Node3D = null
var _is_charging_shot: bool = false
var _shot_charge_time: float = 0.0
var _match_controls_enabled: bool = true
var _possession_acquisition_enabled: bool = true
var _last_pass_target: PlayerCharacter = null
var _ai_state: AIState = AIState.IDLE
var _ai_target: Vector3 = Vector3.ZERO
var _ai_decision_timer: float = 0.0
var _ai_move_direction: Vector3 = Vector3.ZERO
var _ai_debug_label: Label3D = null
var _ai_enabled_runtime: bool = true


func _ready() -> void:
	collision_layer = LOOSE_PLAYER_LAYER
	collision_mask = LOOSE_PLAYER_MASK

	_camera = get_tree().get_first_node_in_group("broadcast_camera") as Camera3D
	_facing_direction = _read_mesh_facing()
	_last_move_direction = _facing_direction
	_requested_move_direction = _facing_direction

	_possession_area.body_entered.connect(_on_possession_area_body_entered)
	_possession_debug_label.visible = possession_debug_enabled
	$PossessionArea/DebugMesh.visible = possession_debug_enabled
	_ai_enabled_runtime = ai_enabled
	_ai_target = global_position
	if ai_debug_enabled:
		_setup_ai_debug_label()

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

	if is_user_controlled and input_dir.length_squared() > 0.0 and _camera != null:
		var cam_basis: Basis = _camera.global_transform.basis
		direction = cam_basis * Vector3(input_dir.x, 0.0, input_dir.y)
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			direction = direction.normalized()
	elif (not is_user_controlled) and _match_controls_enabled and _ai_enabled_runtime:
		_update_field_ai(delta)
		direction = _ai_move_direction

	var sprint_strength: float = get_sprint_strength()
	var target_speed: float = lerpf(walk_speed, sprint_speed, sprint_strength) * _dribble_speed_multiplier
	if not is_user_controlled:
		target_speed = ai_move_speed * _dribble_speed_multiplier
	var move_accel: float = acceleration if is_user_controlled else ai_acceleration

	if direction.length_squared() > 0.0:
		velocity.x = move_toward(velocity.x, direction.x * target_speed, move_accel * delta)
		velocity.z = move_toward(velocity.z, direction.z * target_speed, move_accel * delta)
		_rotate_toward_direction(direction, delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_accel * delta)
		velocity.z = move_toward(velocity.z, 0.0, move_accel * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	move_and_slide()
	_update_last_move_direction()
	_facing_direction = _read_mesh_facing()

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
	_update_ai_debug()


func _on_possession_area_body_entered(body: Node3D) -> void:
	if not _possession_acquisition_enabled:
		return
	_try_acquire_from_body(body)


func _try_acquire_from_body(body: Node3D) -> void:
	if has_possession():
		return
	if not _possession_acquisition_enabled:
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
		"ball detected: %s\nball state: %s\npossession acquired: %s\ndistance: %.2f\ncontrolled: %s"
		% [
			"yes" if ball_detected else "no",
			ball_state,
			"yes" if has_possession() else "no",
			distance,
			"yes" if is_user_controlled else "no",
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
	var match_ctrl: Node = get_tree().get_first_node_in_group("match")
	if match_ctrl != null and match_ctrl.has_method("notify_possession_gained"):
		match_ctrl.notify_possession_gained(self)


func notify_possession_lost() -> void:
	_possessed_ball = null
	_cancel_shot_charge()
	reset_dribble_modifiers()
	var match_ctrl: Node = get_tree().get_first_node_in_group("match")
	if match_ctrl != null and match_ctrl.has_method("notify_possession_lost"):
		match_ctrl.notify_possession_lost(self)


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


func set_user_controlled(enabled: bool) -> void:
	is_user_controlled = enabled
	if not enabled:
		_cancel_shot_charge()
		velocity = Vector3.ZERO
	else:
		_ai_state = AIState.IDLE
		_ai_move_direction = Vector3.ZERO


func set_ai_enabled(enabled: bool) -> void:
	_ai_enabled_runtime = enabled
	if not enabled:
		_ai_move_direction = Vector3.ZERO
		_ai_state = AIState.IDLE


func get_ai_state() -> AIState:
	return _ai_state


func get_ai_state_name() -> String:
	match _ai_state:
		AIState.SUPPORT:
			return "SUPPORT"
		AIState.DEFEND:
			return "DEFEND"
		AIState.PURSUE_LOOSE:
			return "PURSUE_LOOSE"
		AIState.PRESSURE:
			return "PRESSURE"
		AIState.DRIBBLE_ATTACK:
			return "DRIBBLE_ATTACK"
		_:
			return "IDLE"


func get_ai_target() -> Vector3:
	return _ai_target


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
	_last_pass_target = null


func perform_short_pass() -> void:
	var ball: Node3D = _possessed_ball
	if ball == null or not ball.has_method("perform_pass"):
		return

	var aim: Vector3 = get_aim_direction()
	var target: PlayerCharacter = find_pass_target(aim)
	_last_pass_target = target

	var pass_direction: Vector3 = aim
	if target != null:
		var to_target: Vector3 = target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001:
			# Blend aim toward the selected teammate so the pass is directional but accurate.
			var assisted: Vector3 = aim.lerp(to_target.normalized(), clampf(manual_pass_assist_strength, 0.0, 1.0))
			if assisted.length_squared() > 0.0001:
				pass_direction = assisted.normalized()

	var match_ctrl: Node = get_tree().get_first_node_in_group("match")
	if match_ctrl != null and match_ctrl.has_method("notify_pass_intent"):
		match_ctrl.notify_pass_intent(self, target)

	ball.perform_pass(pass_direction, short_pass_speed)


func perform_charged_shot(charge_time: float) -> void:
	var ball: Node3D = _possessed_ball
	if ball == null or not ball.has_method("perform_shot"):
		return
	var shot_direction: Vector3 = get_aim_direction()
	print(
		"[SHOT DEBUG] facing=%s requested=%s final=%s"
		% [str(get_facing_direction()), str(_requested_move_direction), str(shot_direction)]
	)
	ball.perform_shot(shot_direction, get_charged_shot_speed(charge_time))


func get_charged_shot_speed(charge_time: float) -> float:
	var charge_ratio: float = clampf(charge_time / maxf(max_shot_charge_time, 0.001), 0.0, 1.0)
	return lerpf(min_shot_speed, max_shot_speed, charge_ratio)


func get_aim_direction() -> Vector3:
	if has_movement_input():
		var requested: Vector3 = Vector3(_requested_move_direction.x, 0.0, _requested_move_direction.z)
		if requested.length_squared() > 0.0001:
			return requested.normalized()
	return get_facing_direction()


func get_last_pass_target() -> PlayerCharacter:
	return _last_pass_target


func find_pass_target(aim_direction: Vector3 = Vector3.ZERO) -> PlayerCharacter:
	var aim: Vector3 = aim_direction
	if aim.length_squared() <= 0.0001:
		aim = get_aim_direction()
	aim.y = 0.0
	if aim.length_squared() <= 0.0001:
		aim = Vector3(0.0, 0.0, -1.0)
	else:
		aim = aim.normalized()

	var best: PlayerCharacter = null
	var best_score: float = INF

	for node: Node in get_tree().get_nodes_in_group("player"):
		if node == self or node is not PlayerCharacter:
			continue
		var other: PlayerCharacter = node
		if not is_same_team(other):
			continue

		var to_teammate: Vector3 = other.global_position - global_position
		to_teammate.y = 0.0
		var distance: float = to_teammate.length()
		if distance < 0.35 or distance > pass_target_max_distance:
			continue

		var to_dir: Vector3 = to_teammate / distance
		var angle_deg: float = rad_to_deg(aim.angle_to(to_dir))
		var ahead: bool = aim.dot(to_dir) > 0.0
		if not ahead or angle_deg > pass_target_max_angle:
			continue

		var lane_penalty: float = _estimate_lane_penalty(to_dir, distance)
		var score: float = (
			angle_deg * pass_target_angle_weight
			+ distance * pass_target_distance_weight
			+ lane_penalty
		)
		if score < best_score:
			best_score = score
			best = other

	return best


func score_pass_candidate(candidate: PlayerCharacter, aim_direction: Vector3) -> float:
	var aim: Vector3 = Vector3(aim_direction.x, 0.0, aim_direction.z)
	if aim.length_squared() <= 0.0001:
		aim = get_aim_direction()
	else:
		aim = aim.normalized()

	var to_teammate: Vector3 = candidate.global_position - global_position
	to_teammate.y = 0.0
	var distance: float = to_teammate.length()
	if distance < 0.001:
		return INF
	var to_dir: Vector3 = to_teammate / distance
	var angle_deg: float = rad_to_deg(aim.angle_to(to_dir))
	var score: float = (
		angle_deg * pass_target_angle_weight
		+ distance * pass_target_distance_weight
		+ _estimate_lane_penalty(to_dir, distance)
	)
	if aim.dot(to_dir) <= 0.0:
		score += behind_target_penalty
	return score


func _estimate_lane_penalty(to_dir: Vector3, distance: float) -> float:
	# Simple deterministic openness proxy: prefer shorter, more centered passes.
	# Avoids RayCast dependency and remains stable for the current prototype.
	return absf(to_dir.x) * 0.35 + maxf(distance - 8.0, 0.0) * 0.04


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


func has_movement_input() -> bool:
	if not is_user_controlled:
		return _ai_move_direction.length_squared() > 0.01
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
	var facing: Vector3 = Vector3(_facing_direction.x, 0.0, _facing_direction.z)
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
	_facing_direction = _read_mesh_facing()


func _read_mesh_facing() -> Vector3:
	var yaw: float = mesh.rotation.y
	var facing: Vector3 = Vector3(sin(yaw), 0.0, cos(yaw))
	if facing.length_squared() <= 0.0001:
		return Vector3(0.0, 0.0, -1.0)
	return facing.normalized()


func set_facing_direction(direction: Vector3) -> void:
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() <= 0.0001:
		return
	flat = flat.normalized()
	_facing_direction = flat
	_requested_move_direction = flat
	_last_move_direction = flat
	mesh.rotation.y = atan2(flat.x, flat.z)


func _update_field_ai(delta: float) -> void:
	_ai_decision_timer -= delta
	if _ai_decision_timer <= 0.0:
		_ai_decision_timer = ai_decision_interval
		_recompute_ai_target()

	var to_target: Vector3 = _flat(_ai_target) - _flat(global_position)
	if to_target.length() < 0.35:
		_ai_move_direction = Vector3.ZERO
	else:
		_ai_move_direction = to_target.normalized()
		_requested_move_direction = _ai_move_direction


func _recompute_ai_target() -> void:
	var match_ctrl: Node = get_tree().get_first_node_in_group("match")
	var ball: Node3D = get_tree().get_first_node_in_group("soccer_ball") as Node3D
	if ball == null:
		_ai_state = AIState.IDLE
		_ai_target = global_position
		return

	var team_in_possession: int = -1
	var possessor: PlayerCharacter = null
	if match_ctrl != null and match_ctrl.has_method("get_team_in_possession"):
		team_in_possession = match_ctrl.get_team_in_possession()
	if ball.has_method("get_possessor"):
		possessor = ball.get_possessor()

	var ball_loose: bool = ball.has_method("is_loose") and ball.is_loose()
	if has_possession():
		if team_id == TeamId.AWAY:
			_ai_state = AIState.DRIBBLE_ATTACK
			_ai_target = _clamp_to_field(
				global_position + TeamId.attack_direction(team_id) * 3.5
			)
		else:
			_ai_state = AIState.SUPPORT
			_ai_target = global_position
		return

	if ball_loose:
		if _is_best_loose_ball_chaser(ball, match_ctrl):
			_ai_state = AIState.PURSUE_LOOSE
			_ai_target = _clamp_to_field(_flat(ball.global_position))
		else:
			_ai_state = AIState.IDLE
			_ai_target = _clamp_to_field(_default_waiting_position())
		return

	if team_in_possession == team_id:
		_ai_state = AIState.SUPPORT
		_ai_target = _compute_support_target(possessor, match_ctrl)
	elif team_in_possession >= 0:
		if team_id == TeamId.AWAY:
			_ai_state = AIState.PRESSURE
			_ai_target = _compute_pressure_target(possessor, ball)
		else:
			_ai_state = AIState.DEFEND
			_ai_target = _compute_defensive_support_target(possessor, ball)
	else:
		_ai_state = AIState.IDLE
		_ai_target = _clamp_to_field(_default_waiting_position())

	_ai_target = _apply_spacing(_ai_target)
	_ai_target = _clamp_to_field(_ai_target)


func _is_best_loose_ball_chaser(ball: Node3D, match_ctrl: Node) -> bool:
	var my_distance: float = global_position.distance_to(ball.global_position)
	if my_distance > ai_loose_ball_pursuit_radius:
		return false

	for node: Node in get_tree().get_nodes_in_group("player"):
		if node == self or node is not PlayerCharacter:
			continue
		var other: PlayerCharacter = node
		if other.team_id != team_id:
			continue
		if other.is_user_controlled and match_ctrl != null and match_ctrl.has_method("get_active_player"):
			var user_distance: float = other.global_position.distance_to(ball.global_position)
			if user_distance <= my_distance + 0.75:
				return false
		elif other.global_position.distance_to(ball.global_position) + 0.35 < my_distance:
			return false
	return true


func _compute_support_target(possessor: PlayerCharacter, _match_ctrl: Node) -> Vector3:
	var carrier: PlayerCharacter = possessor
	if carrier == null:
		carrier = _find_team_ball_carrier()
	if carrier == null:
		return _default_waiting_position()

	var attack: Vector3 = TeamId.attack_direction(team_id)
	var side: float = 1.0 if global_position.x >= carrier.global_position.x else -1.0
	var lane: Vector3 = (
		carrier.global_position
		+ attack * ai_support_distance
		+ Vector3(side * 2.4, 0.0, 0.0)
	)

	var nearest_opponent: PlayerCharacter = _find_nearest_opponent()
	if nearest_opponent != null:
		var to_opp: Vector3 = nearest_opponent.global_position - carrier.global_position
		to_opp.y = 0.0
		if to_opp.length_squared() > 0.01:
			var opp_dir: Vector3 = to_opp.normalized()
			var desired_dir: Vector3 = lane - carrier.global_position
			desired_dir.y = 0.0
			if desired_dir.length_squared() > 0.01 and desired_dir.normalized().dot(opp_dir) > 0.85:
				lane = (
					carrier.global_position
					+ attack * ai_support_distance
					+ Vector3(-side * 2.8, 0.0, 0.0)
				)
	return lane


func _compute_defensive_support_target(possessor: PlayerCharacter, ball: Node3D) -> Vector3:
	var threat: Vector3 = ball.global_position
	if possessor != null:
		threat = possessor.global_position
	var defend_z: float = TeamId.defend_goal_z(team_id)
	var mid: Vector3 = threat.lerp(Vector3(0.0, 0.1, defend_z), 0.45)
	mid.x = clampf(threat.x * 0.55, -ai_field_half_x, ai_field_half_x)
	return mid


func _compute_pressure_target(possessor: PlayerCharacter, ball: Node3D) -> Vector3:
	var carrier_pos: Vector3 = ball.global_position
	if possessor != null:
		carrier_pos = possessor.global_position
	var to_carrier: Vector3 = carrier_pos - global_position
	to_carrier.y = 0.0
	var distance: float = to_carrier.length()
	if distance <= ai_pressure_distance:
		return global_position
	return carrier_pos - to_carrier.normalized() * ai_pressure_distance


func _default_waiting_position() -> Vector3:
	if team_id == TeamId.AWAY:
		return Vector3(signf(global_position.x) * 2.0, 0.1, -2.5)
	return Vector3(signf(global_position.x) * 2.5, 0.1, -1.5)


func _apply_spacing(target: Vector3) -> Vector3:
	var adjusted: Vector3 = target
	for node: Node in get_tree().get_nodes_in_group("player"):
		if node == self or node is not PlayerCharacter:
			continue
		var other: PlayerCharacter = node
		var to_other: Vector3 = other.global_position - adjusted
		to_other.y = 0.0
		var distance: float = to_other.length()
		if distance < ai_min_teammate_spacing and distance > 0.001:
			adjusted -= to_other.normalized() * (ai_min_teammate_spacing - distance)
	return adjusted


func _clamp_to_field(point: Vector3) -> Vector3:
	return Vector3(
		clampf(point.x, -ai_field_half_x, ai_field_half_x),
		0.1,
		clampf(point.z, -ai_field_half_z, ai_field_half_z)
	)


func _flat(point: Vector3) -> Vector3:
	return Vector3(point.x, 0.0, point.z)


func _find_team_ball_carrier() -> PlayerCharacter:
	for node: Node in get_tree().get_nodes_in_group("player"):
		if node is not PlayerCharacter:
			continue
		var other: PlayerCharacter = node
		if other.team_id == team_id and other.has_possession():
			return other
	return null


func _find_nearest_opponent() -> PlayerCharacter:
	var nearest: PlayerCharacter = null
	var nearest_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group("player"):
		if node == self or node is not PlayerCharacter:
			continue
		var other: PlayerCharacter = node
		if other.team_id == team_id:
			continue
		var distance: float = global_position.distance_to(other.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = other
	return nearest


func _setup_ai_debug_label() -> void:
	_ai_debug_label = Label3D.new()
	_ai_debug_label.font_size = 16
	_ai_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_ai_debug_label.position = Vector3(0.0, 2.4, 0.0)
	add_child(_ai_debug_label)


func _update_ai_debug() -> void:
	if not ai_debug_enabled:
		if _ai_debug_label != null:
			_ai_debug_label.visible = false
		return
	if _ai_debug_label == null:
		_setup_ai_debug_label()
	_ai_debug_label.visible = true

	var possessor_name: String = "none"
	var team_poss: String = "loose"
	var match_ctrl: Node = get_tree().get_first_node_in_group("match")
	var ball: Node = get_tree().get_first_node_in_group("soccer_ball")
	if ball != null and ball.has_method("get_possessor") and ball.get_possessor() != null:
		possessor_name = ball.get_possessor().name
	if match_ctrl != null and match_ctrl.has_method("get_team_in_possession"):
		var possession_team: int = match_ctrl.get_team_in_possession()
		if possession_team == TeamId.HOME:
			team_poss = "HOME"
		elif possession_team == TeamId.AWAY:
			team_poss = "AWAY"

	_ai_debug_label.text = (
		"team=%s\nstate=%s\ntarget=%s\npossessor=%s\nteam_poss=%s"
		% [
			"HOME" if team_id == TeamId.HOME else "AWAY",
			get_ai_state_name(),
			str(_ai_target.round()),
			possessor_name,
			team_poss,
		]
	)
