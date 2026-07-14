extends CharacterBody3D
class_name GoalkeeperCharacter

const PLAYER_LAYER: int = 2
const PLAYER_MASK: int = 5

@export var team_id: int = TeamId.HOME
@export var goal_center: Vector3 = Vector3(0.0, 0.1, -6.8)
@export var goal_forward: Vector3 = Vector3(0.0, 0.0, -1.0)
@export var zone_min: Vector3 = Vector3(-2.2, 0.1, -7.25)
@export var zone_max: Vector3 = Vector3(2.2, 0.1, -5.8)
@export var lateral_speed: float = 4.5
@export var return_speed: float = 3.5
@export var forward_move_distance: float = 1.2
@export var save_reaction_distance: float = 6.0
@export var save_reach: float = 1.75
@export var save_impulse_strength: float = 10.0
@export var gravity: float = 9.8

var _home_position: Vector3 = Vector3.ZERO
var _match_enabled: bool = true
var _save_cooldown: float = 0.0
var _last_save_attempted: bool = false
var _ball: RigidBody3D


func _ready() -> void:
	add_to_group("goalkeeper")
	collision_layer = PLAYER_LAYER
	collision_mask = PLAYER_MASK
	_home_position = goal_center
	global_position = _home_position
	goal_forward = goal_forward.normalized()
	_ball = get_tree().get_first_node_in_group("soccer_ball") as RigidBody3D


func _physics_process(delta: float) -> void:
	_save_cooldown = maxf(_save_cooldown - delta, 0.0)
	_last_save_attempted = false

	if _ball == null or not is_instance_valid(_ball):
		_ball = get_tree().get_first_node_in_group("soccer_ball") as RigidBody3D

	if not _match_enabled or not _is_play_active():
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var target: Vector3 = _compute_target_position()
	target = _clamp_to_zone(target)
	_move_toward_target(target, delta)
	_try_save(delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	move_and_slide()


func get_team_id() -> int:
	return team_id


func set_match_enabled(enabled: bool) -> void:
	_match_enabled = enabled
	if not enabled:
		velocity = Vector3.ZERO


func reset_to_kickoff(position: Vector3 = Vector3.ZERO) -> void:
	_home_position = goal_center if position == Vector3.ZERO else position
	global_position = _home_position
	velocity = Vector3.ZERO
	_save_cooldown = 0.0


func did_attempt_save_recently() -> bool:
	return _last_save_attempted


func _compute_target_position() -> Vector3:
	if _ball == null:
		return _home_position

	var ball_flat: Vector3 = _flat(_ball.global_position)
	var home_flat: Vector3 = _flat(_home_position)
	if not _ball_threatens_goal(ball_flat):
		return _home_position

	var lateral_x: float = clampf(ball_flat.x, zone_min.x, zone_max.x)
	var distance_to_ball: float = home_flat.distance_to(ball_flat)
	var ball_velocity: Vector3 = Vector3(
		_ball.linear_velocity.x,
		0.0,
		_ball.linear_velocity.z
	)
	var toward_goal_speed: float = ball_velocity.dot(goal_forward)
	var threat: float = clampf(
		(1.0 - distance_to_ball / maxf(forward_move_distance * 3.0, 0.001))
		+ maxf(toward_goal_speed / 12.0, 0.0),
		0.0,
		1.0
	)

	var depth_z: float = home_flat.z
	if threat > 0.15:
		var forward_limit: float = _goal_line_z()
		depth_z = lerpf(home_flat.z, forward_limit, threat)
	else:
		lateral_x = lerpf(lateral_x, home_flat.x, clampf(distance_to_ball / 18.0, 0.0, 0.65))

	return Vector3(lateral_x, _home_position.y, depth_z)


func _goal_line_z() -> float:
	if goal_forward.z < 0.0:
		return zone_min.z
	return zone_max.z


func _move_toward_target(target: Vector3, delta: float) -> void:
	var current_flat: Vector3 = _flat(global_position)
	var target_flat: Vector3 = _flat(target)
	var offset: Vector3 = target_flat - current_flat
	var distance: float = offset.length()
	if distance <= 0.001:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var speed: float = lateral_speed
	if distance < 0.35:
		speed = return_speed
	var move_step: float = minf(speed * delta, distance)
	var move_dir: Vector3 = offset / distance
	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed
	global_position = Vector3(
		global_position.x + move_dir.x * move_step,
		_home_position.y,
		global_position.z + move_dir.z * move_step
	)


func _try_save(_delta: float) -> void:
	if _ball == null or _save_cooldown > 0.0:
		return
	if not _ball.has_method("is_loose") or not _ball.is_loose():
		return
	if not _ball.has_method("apply_goalkeeper_deflection"):
		return

	var ball_flat: Vector3 = _flat(_ball.global_position)
	if not _ball_threatens_goal(ball_flat):
		return
	var keeper_flat: Vector3 = _flat(global_position)
	var to_ball: Vector3 = ball_flat - keeper_flat
	var distance: float = to_ball.length()
	if distance > save_reaction_distance:
		return

	var ball_velocity: Vector3 = Vector3(
		_ball.linear_velocity.x,
		0.0,
		_ball.linear_velocity.z
	)
	var approaching: bool = ball_velocity.dot(goal_forward) > 0.5
	if distance > save_reach and not approaching:
		return

	if distance > save_reach:
		var predicted: Vector3 = ball_flat + ball_velocity * 0.12
		var lateral_miss: float = absf(predicted.x - keeper_flat.x)
		if lateral_miss > save_reach:
			return

	var deflect_dir: Vector3 = -goal_forward
	if absf(to_ball.x) > 0.05:
		deflect_dir.x = signf(to_ball.x) * 0.45
	deflect_dir = deflect_dir.normalized()

	if _ball.apply_goalkeeper_deflection(deflect_dir, save_impulse_strength):
		_last_save_attempted = true
		_save_cooldown = 0.35


func _clamp_to_zone(point: Vector3) -> Vector3:
	return Vector3(
		clampf(point.x, zone_min.x, zone_max.x),
		_home_position.y,
		clampf(point.z, minf(zone_min.z, zone_max.z), maxf(zone_min.z, zone_max.z))
	)


func _flat(point: Vector3) -> Vector3:
	return Vector3(point.x, 0.0, point.z)


func _is_play_active() -> bool:
	var match_ctrl: Node = get_tree().get_first_node_in_group("match")
	if match_ctrl != null and match_ctrl.has_method("is_play_active"):
		return match_ctrl.is_play_active()
	return true


func _ball_threatens_goal(ball_flat: Vector3) -> bool:
	var zone_near: float = minf(zone_min.z, zone_max.z)
	var zone_far: float = maxf(zone_min.z, zone_max.z)
	if ball_flat.z < zone_near or ball_flat.z > zone_far:
		var home_flat: Vector3 = _flat(_home_position)
		if home_flat.distance_to(ball_flat) > save_reaction_distance:
			return false

	var ball_velocity: Vector3 = Vector3(
		_ball.linear_velocity.x,
		0.0,
		_ball.linear_velocity.z
	)
	return ball_velocity.dot(goal_forward) > 0.5
