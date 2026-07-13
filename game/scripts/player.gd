extends CharacterBody3D
class_name PlayerCharacter

enum MovementState {
	STATIONARY,
	WALK,
	JOG,
	SPRINT,
	STOPPING,
}

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var acceleration: float = 12.0
@export var rotation_speed: float = 10.0
@export var gravity: float = 9.8

@onready var mesh: MeshInstance3D = $MeshInstance3D

var _camera: Camera3D
var _last_move_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
var _requested_move_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
var _possessed_ball: Node3D = null
var _dribble_speed_multiplier: float = 1.0
var _dribble_rotation_speed: float = -1.0


func _ready() -> void:
	_camera = get_tree().get_first_node_in_group("broadcast_camera") as Camera3D
	_last_move_direction = get_facing_direction()
	_requested_move_direction = _last_move_direction


func _physics_process(delta: float) -> void:
	_update_requested_move_direction()

	var input_dir: Vector2 = Input.get_vector(
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

	var sprint_strength: float = Input.get_action_strength(InputActions.SPRINT)
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


func has_possession() -> bool:
	return _possessed_ball != null


func get_possessed_ball() -> Node3D:
	return _possessed_ball


func notify_possession_gained(ball: Node3D) -> void:
	_possessed_ball = ball


func notify_possession_lost() -> void:
	_possessed_ball = null
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


func has_movement_input() -> bool:
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
