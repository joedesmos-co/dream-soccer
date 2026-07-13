extends Area3D
class_name GoalTrigger

signal goal_scored(scoring_team_id: int)

@export var scoring_team_id: int = 0

var _counted_for_current_entry: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 4
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func reset_trigger() -> void:
	_counted_for_current_entry = false


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("soccer_ball"):
		return
	if _counted_for_current_entry:
		return
	_counted_for_current_entry = true
	goal_scored.emit(scoring_team_id)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("soccer_ball"):
		_counted_for_current_entry = false
