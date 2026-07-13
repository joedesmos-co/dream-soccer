extends Node3D

enum MatchState {
	PLAYING,
	GOAL_SCORED,
	RESETTING,
	KICKOFF_DELAY,
}

const KICKOFF_PLAYER_POSITION: Vector3 = Vector3(0.0, 0.1, 0.0)
const KICKOFF_TEAMMATE_POSITION: Vector3 = Vector3(3.0, 0.1, -6.0)
const KICKOFF_BALL_POSITION: Vector3 = Vector3(0.0, 0.21, -2.0)

@export var kickoff_delay: float = 2.0
@export var player_path: NodePath = ^"Player"
@export var teammate_path: NodePath = ^"Teammate"
@export var ball_path: NodePath = ^"Ball"
@export var north_goal_path: NodePath = ^"Goals/NorthGoal/GoalTrigger"
@export var south_goal_path: NodePath = ^"Goals/SouthGoal/GoalTrigger"

var _home_score: int = 0
var _away_score: int = 0
var _match_state: MatchState = MatchState.PLAYING
var _kickoff_timer: float = 0.0

@onready var _player: PlayerCharacter = get_node(player_path) as PlayerCharacter
@onready var _teammate: PlayerCharacter = get_node(teammate_path) as PlayerCharacter
@onready var _ball: RigidBody3D = get_node(ball_path) as RigidBody3D
@onready var _north_goal: GoalTrigger = get_node(north_goal_path) as GoalTrigger
@onready var _south_goal: GoalTrigger = get_node(south_goal_path) as GoalTrigger
@onready var _score_label: Label = $MatchUI/ScoreLabel


func _ready() -> void:
	_north_goal.goal_scored.connect(_on_goal_scored)
	_south_goal.goal_scored.connect(_on_goal_scored)
	_update_score_label()


func _physics_process(delta: float) -> void:
	if _match_state != MatchState.KICKOFF_DELAY:
		return
	_kickoff_timer -= delta
	if _kickoff_timer <= 0.0:
		_resume_play()


func get_match_state() -> MatchState:
	return _match_state


func get_home_score() -> int:
	return _home_score


func get_away_score() -> int:
	return _away_score


func is_play_active() -> bool:
	return _match_state == MatchState.PLAYING


func _on_goal_scored(scoring_team_id: int) -> void:
	if _match_state != MatchState.PLAYING:
		return

	_match_state = MatchState.GOAL_SCORED
	if scoring_team_id == TeamId.HOME:
		_home_score += 1
	else:
		_away_score += 1
	_update_score_label()
	print("[GOAL] Team %d scored. HOME %d - %d AWAY" % [scoring_team_id, _home_score, _away_score])
	_begin_goal_reset()


func _begin_goal_reset() -> void:
	_match_state = MatchState.RESETTING
	_set_play_enabled(false)

	if _ball.has_method("force_match_reset"):
		_ball.force_match_reset(KICKOFF_BALL_POSITION)
	else:
		_ball.global_position = KICKOFF_BALL_POSITION
		_ball.linear_velocity = Vector3.ZERO
		_ball.angular_velocity = Vector3.ZERO

	_player.reset_to_kickoff(KICKOFF_PLAYER_POSITION)
	_teammate.reset_to_kickoff(KICKOFF_TEAMMATE_POSITION)

	_north_goal.reset_trigger()
	_south_goal.reset_trigger()

	_match_state = MatchState.KICKOFF_DELAY
	_kickoff_timer = kickoff_delay


func _resume_play() -> void:
	_set_play_enabled(true)
	_match_state = MatchState.PLAYING


func _set_play_enabled(enabled: bool) -> void:
	_player.set_match_controls_enabled(enabled)
	_player.set_possession_acquisition_enabled(enabled)
	_teammate.set_match_controls_enabled(enabled)
	_teammate.set_possession_acquisition_enabled(enabled)
	if _ball.has_method("set_match_play_enabled"):
		_ball.set_match_play_enabled(enabled)


func _update_score_label() -> void:
	_score_label.text = "HOME %d  -  %d AWAY" % [_home_score, _away_score]
