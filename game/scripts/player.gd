extends CharacterBody3D

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var acceleration: float = 12.0
@export var rotation_speed: float = 10.0
@export var gravity: float = 9.8

@onready var mesh: MeshInstance3D = $MeshInstance3D

var _camera: Camera3D


func _ready() -> void:
	_camera = get_tree().get_first_node_in_group("broadcast_camera") as Camera3D


func _physics_process(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = Vector3.ZERO

	if input_dir.length_squared() > 0.0 and _camera != null:
		var cam_basis: Basis = _camera.global_transform.basis
		direction = cam_basis * Vector3(input_dir.x, 0.0, input_dir.y)
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			direction = direction.normalized()

	var target_speed: float = sprint_speed if Input.is_action_pressed("sprint") else walk_speed

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


func _rotate_toward_direction(direction: Vector3, delta: float) -> void:
	var target_rotation: float = atan2(direction.x, direction.z)
	var current_rotation: float = mesh.rotation.y
	mesh.rotation.y = lerp_angle(current_rotation, target_rotation, rotation_speed * delta)
