extends Node3D

enum MatchState {
	PLAYING,
	GOAL_SCORED,
	RESETTING,
	KICKOFF_DELAY,
}

## HOME attacks south (+Z). South goal credits HOME.
## AWAY attacks north (-Z). North goal credits AWAY.
## Scoring is based on the goal entered, not the last toucher.

const KICKOFF_PLAYER_POSITION: Vector3 = Vector3(0.0, 0.1, 0.0)
const KICKOFF_TEAMMATE_POSITION: Vector3 = Vector3(3.0, 0.1, -3.0)
const KICKOFF_OPPONENT_POSITION: Vector3 = Vector3(-2.5, 0.1, 3.0)
const KICKOFF_BALL_POSITION: Vector3 = Vector3(0.0, 0.21, -2.0)

const KICKOFF_NORTH_GK_POSITION: Vector3 = Vector3(0.0, 0.1, -6.8)
const KICKOFF_SOUTH_GK_POSITION: Vector3 = Vector3(0.0, 0.1, 6.8)

@export var kickoff_delay: float = 2.0
@export var pass_control_timeout: float = 2.5
@export var player_path: NodePath = ^"Player"
@export var teammate_path: NodePath = ^"Teammate"
@export var opponent_path: NodePath = ^"Opponent"
@export var ball_path: NodePath = ^"Ball"
@export var north_goalkeeper_path: NodePath = ^"Goalkeepers/NorthGoalkeeper"
@export var south_goalkeeper_path: NodePath = ^"Goalkeepers/SouthGoalkeeper"
@export var north_goal_path: NodePath = ^"Goals/NorthGoal/GoalTrigger"
@export var south_goal_path: NodePath = ^"Goals/SouthGoal/GoalTrigger"
@export var camera_path: NodePath = ^"BroadcastCamera"

var _home_score: int = 0
var _away_score: int = 0
var _match_state: MatchState = MatchState.PLAYING
var _kickoff_timer: float = 0.0
var _active_player: PlayerCharacter = null
var _intended_receiver: PlayerCharacter = null
var _pass_timeout_timer: float = 0.0
var _team_in_possession: int = -1
var _current_possessor: PlayerCharacter = null

@onready var _player: PlayerCharacter = get_node(player_path) as PlayerCharacter
@onready var _teammate: PlayerCharacter = get_node(teammate_path) as PlayerCharacter
@onready var _opponent: PlayerCharacter = get_node(opponent_path) as PlayerCharacter
@onready var _ball: RigidBody3D = get_node(ball_path) as RigidBody3D
@onready var _north_goal: GoalTrigger = get_node(north_goal_path) as GoalTrigger
@onready var _south_goal: GoalTrigger = get_node(south_goal_path) as GoalTrigger
@onready var _north_goalkeeper: GoalkeeperCharacter = get_node(north_goalkeeper_path) as GoalkeeperCharacter
@onready var _south_goalkeeper: GoalkeeperCharacter = get_node(south_goalkeeper_path) as GoalkeeperCharacter
@onready var _score_label: Label = $MatchUI/ScoreLabel
@onready var _camera: Node3D = get_node(camera_path)


func _ready() -> void:
	add_to_group("match")
	_north_goal.goal_scored.connect(_on_goal_scored)
	_south_goal.goal_scored.connect(_on_goal_scored)
	_update_score_label()
	call_deferred("_initialize_active_player")


func _physics_process(delta: float) -> void:
	if _pass_timeout_timer > 0.0:
		_pass_timeout_timer = maxf(_pass_timeout_timer - delta, 0.0)
		if _pass_timeout_timer <= 0.0 and _intended_receiver != null:
			clear_intended_receiver()
		elif _intended_receiver != null and _ball != null and _ball.has_method("is_loose"):
			if not _ball.is_loose() and _ball.get_possessor() != _intended_receiver:
				if _ball.get_possessor() != _active_player:
					clear_intended_receiver()

	if _match_state != MatchState.KICKOFF_DELAY:
		return
	_kickoff_timer -= delta
	if _kickoff_timer <= 0.0:
		_resume_play()


func _initialize_active_player() -> void:
	_teammate.set_user_controlled(false)
	_teammate.set_ai_enabled(true)
	_opponent.set_user_controlled(false)
	_opponent.set_ai_enabled(true)
	set_active_player(_player)


func get_match_state() -> MatchState:
	return _match_state


func get_home_score() -> int:
	return _home_score


func get_away_score() -> int:
	return _away_score


func is_play_active() -> bool:
	return _match_state == MatchState.PLAYING


func get_active_player() -> PlayerCharacter:
	return _active_player


func get_intended_receiver() -> PlayerCharacter:
	return _intended_receiver


func get_team_in_possession() -> int:
	return _team_in_possession


func get_current_possessor() -> PlayerCharacter:
	return _current_possessor


func get_opponent() -> PlayerCharacter:
	return _opponent


func get_teammate() -> PlayerCharacter:
	return _teammate


func set_active_player(player: PlayerCharacter) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.get_team_id() != TeamId.HOME:
		return

	if _active_player != null and _active_player != player:
		_active_player.set_user_controlled(false)
		_active_player.set_ai_enabled(true)

	_active_player = player
	_active_player.set_user_controlled(true)
	_active_player.set_ai_enabled(false)
	_active_player.possession_debug_enabled = true

	if _camera != null and _camera.has_method("set_follow_player"):
		_camera.set_follow_player(_active_player)


func notify_pass_intent(passer: PlayerCharacter, receiver: PlayerCharacter) -> void:
	if passer == null or passer != _active_player:
		return
	_intended_receiver = receiver
	_pass_timeout_timer = pass_control_timeout if receiver != null else 0.0


func notify_possession_gained(player: PlayerCharacter) -> void:
	if player == null:
		return

	_current_possessor = player
	_team_in_possession = player.get_team_id()

	if _intended_receiver != null:
		if player == _intended_receiver:
			set_active_player(player)
			clear_intended_receiver()
			print("[CONTROL] Transferred to %s after completed pass" % player.name)
		elif player.get_team_id() != TeamId.HOME or player != _active_player:
			clear_intended_receiver()


func notify_possession_lost(_player: PlayerCharacter) -> void:
	# Ball becomes loose until someone else acquires it.
	_current_possessor = null
	_team_in_possession = -1


func clear_intended_receiver() -> void:
	_intended_receiver = null
	_pass_timeout_timer = 0.0


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
	clear_intended_receiver()
	_current_possessor = null
	_team_in_possession = -1
	_set_play_enabled(false)

	if _ball.has_method("force_match_reset"):
		_ball.force_match_reset(KICKOFF_BALL_POSITION)
	else:
		_ball.global_position = KICKOFF_BALL_POSITION
		_ball.linear_velocity = Vector3.ZERO
		_ball.angular_velocity = Vector3.ZERO

	_player.reset_to_kickoff(KICKOFF_PLAYER_POSITION)
	_teammate.reset_to_kickoff(KICKOFF_TEAMMATE_POSITION)
	_opponent.reset_to_kickoff(KICKOFF_OPPONENT_POSITION)
	_north_goalkeeper.reset_to_kickoff(KICKOFF_NORTH_GK_POSITION)
	_south_goalkeeper.reset_to_kickoff(KICKOFF_SOUTH_GK_POSITION)
	set_active_player(_player)

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
	_opponent.set_match_controls_enabled(enabled)
	_opponent.set_possession_acquisition_enabled(enabled)
	_teammate.set_ai_enabled(enabled and not _teammate.is_user_controlled)
	_opponent.set_ai_enabled(enabled)
	_north_goalkeeper.set_match_enabled(enabled)
	_south_goalkeeper.set_match_enabled(enabled)
	if _ball.has_method("set_match_play_enabled"):
		_ball.set_match_play_enabled(enabled)


func _update_score_label() -> void:
	_score_label.text = "HOME %d  -  %d AWAY" % [_home_score, _away_score]
