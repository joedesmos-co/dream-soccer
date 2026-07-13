extends Node3D

const FIELD_HALF_X: float = 12.0
const FIELD_HALF_Z: float = 8.0
const MAX_SEPARATION_FOR_ZOOM: float = 12.0
const FRAMING_CENTER: Vector2 = Vector2(0.5, 0.58)

@export var player_path: NodePath
@export var ball_path: NodePath
@export var camera_height: float = 12.0
@export var camera_angle: float = 10.0
@export var horizontal_dead_zone: float = 0.28
@export var vertical_dead_zone: float = 0.22
@export var ball_focus_weight: float = 0.55
@export var pan_smoothing: float = 3.0
@export var minimum_zoom_distance: float = 11.0
@export var maximum_zoom_distance: float = 18.0
@export var zoom_smoothing: float = 4.0
@export var field_bounds_margin: float = 3.0

@onready var _camera: Camera3D = $Camera3D
@onready var _player: CharacterBody3D = get_node(player_path)
@onready var _ball: RigidBody3D = get_node(ball_path)

var _anchor: Vector3 = Vector3.ZERO
var _zoom_distance: float = 14.0


func _ready() -> void:
	_anchor = _get_play_focus()
	_zoom_distance = minimum_zoom_distance
	global_position = _compute_camera_world_pos(_anchor)
	_update_camera_rotation()


func _physics_process(delta: float) -> void:
	var focus: Vector3 = _get_play_focus()
	_update_zoom(delta)
	_update_anchor(focus, delta)

	var clamped_anchor: Vector3 = _clamp_to_field(_anchor)
	global_position = _compute_camera_world_pos(clamped_anchor)
	_update_camera_rotation()


func get_field_forward() -> Vector3:
	var forward: Vector3 = -_camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return Vector3(0.0, 0.0, -1.0)
	return forward.normalized()


func _get_play_focus() -> Vector3:
	var player_pos: Vector3 = _player.global_position
	var ball_pos: Vector3 = _ball.global_position
	var player_flat: Vector3 = Vector3(player_pos.x, 0.0, player_pos.z)
	var ball_flat: Vector3 = Vector3(ball_pos.x, 0.0, ball_pos.z)
	return player_flat.lerp(ball_flat, ball_focus_weight)


func _update_zoom(delta: float) -> void:
	var player_flat: Vector3 = Vector3(_player.global_position.x, 0.0, _player.global_position.z)
	var ball_flat: Vector3 = Vector3(_ball.global_position.x, 0.0, _ball.global_position.z)
	var separation: float = player_flat.distance_to(ball_flat)
	var zoom_blend: float = clampf(separation / MAX_SEPARATION_FOR_ZOOM, 0.0, 1.0)
	var minimum_distance: float = minf(minimum_zoom_distance, maximum_zoom_distance)
	var maximum_distance: float = maxf(minimum_zoom_distance, maximum_zoom_distance)
	var target_distance: float = clampf(
		lerpf(minimum_zoom_distance, maximum_zoom_distance, zoom_blend),
		minimum_distance,
		maximum_distance
	)
	var blend: float = clampf(zoom_smoothing * delta, 0.0, 1.0)
	_zoom_distance = clampf(
		lerpf(_zoom_distance, target_distance, blend),
		minimum_distance,
		maximum_distance
	)


func _update_anchor(focus: Vector3, delta: float) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var screen_pos: Vector2 = _camera.unproject_position(focus + Vector3(0.0, 0.5, 0.0))
	var normalized: Vector2 = Vector2(screen_pos.x / viewport_size.x, screen_pos.y / viewport_size.y)
	var half_h: float = horizontal_dead_zone * 0.5
	var half_v: float = vertical_dead_zone * 0.5

	var error: Vector2 = Vector2(
		_compute_axis_error(normalized.x, FRAMING_CENTER.x, half_h),
		_compute_axis_error(normalized.y, FRAMING_CENTER.y, half_v)
	)
	if error.length_squared() <= 0.000001:
		return

	var world_pan: Vector3 = _error_to_world_pan(error, focus, viewport_size)
	var target_anchor: Vector3 = _clamp_to_field(_anchor + world_pan)
	var blend: float = clampf(pan_smoothing * delta, 0.0, 1.0)
	_anchor = _anchor.lerp(target_anchor, blend)


func _compute_axis_error(value: float, center: float, half_extent: float) -> float:
	var min_bound: float = center - half_extent
	var max_bound: float = center + half_extent
	if value < min_bound:
		return value - min_bound
	if value > max_bound:
		return value - max_bound
	return 0.0


func _error_to_world_pan(error_norm: Vector2, focus: Vector3, viewport_size: Vector2) -> Vector3:
	var cam_right: Vector3 = global_transform.basis.x
	cam_right.y = 0.0
	if cam_right.length_squared() > 0.0001:
		cam_right = cam_right.normalized()

	var cam_forward: Vector3 = -global_transform.basis.z
	cam_forward.y = 0.0
	if cam_forward.length_squared() > 0.0001:
		cam_forward = cam_forward.normalized()

	var focus_dist: float = maxf(global_position.distance_to(focus), 1.0)
	var world_span_y: float = 2.0 * focus_dist * tan(deg_to_rad(_camera.fov * 0.5))
	var aspect: float = viewport_size.x / viewport_size.y
	var world_span_x: float = world_span_y * aspect

	return cam_right * error_norm.x * world_span_x + cam_forward * error_norm.y * world_span_y


func _clamp_to_field(point: Vector3) -> Vector3:
	var margin: float = field_bounds_margin + _zoom_distance * 0.2
	var clamped: Vector3 = point
	clamped.x = clampf(clamped.x, -FIELD_HALF_X + margin, FIELD_HALF_X - margin)
	clamped.z = clampf(clamped.z, -FIELD_HALF_Z + margin, FIELD_HALF_Z - margin)
	clamped.y = 0.0
	return clamped


func _compute_camera_world_pos(anchor: Vector3) -> Vector3:
	return Vector3(anchor.x, camera_height, anchor.z + _zoom_distance)


func _update_camera_rotation() -> void:
	var look_target: Vector3 = _anchor + Vector3(0.0, 1.0, 0.0)
	look_at(look_target, Vector3.UP)
	rotate_object_local(Vector3.RIGHT, deg_to_rad(-camera_angle))
