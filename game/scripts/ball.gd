extends RigidBody3D

@export var ball_mass: float = 0.43
@export var linear_damping: float = 0.5
@export var angular_damping: float = 0.8
@export var friction: float = 0.8
@export var bounce: float = 0.6
@export var max_speed: float = 15.0

var _physics_material: PhysicsMaterial


func _ready() -> void:
	mass = ball_mass
	linear_damp = linear_damping
	angular_damp = angular_damping
	continuous_cd = true

	_physics_material = PhysicsMaterial.new()
	_physics_material.friction = friction
	_physics_material.bounce = bounce
	physics_material_override = _physics_material


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var linear_velocity: Vector3 = state.linear_velocity
	if linear_velocity.length() > max_speed:
		state.linear_velocity = linear_velocity.normalized() * max_speed
