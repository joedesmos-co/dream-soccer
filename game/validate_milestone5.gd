extends SceneTree

var _errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_main: PackedScene = load("res://main.tscn")
	if packed_main == null:
		_fail("main.tscn failed to load")
		return

	var main: Node3D = packed_main.instantiate()
	root.add_child(main)
	for i: int in range(5):
		await physics_frame

	var match_ctrl: Node = main
	var player: PlayerCharacter = main.get_node("Player") as PlayerCharacter
	var teammate: PlayerCharacter = main.get_node("Teammate") as PlayerCharacter
	var opponent: PlayerCharacter = main.get_node("Opponent") as PlayerCharacter
	var ball: RigidBody3D = main.get_node("Ball") as RigidBody3D

	_check(opponent != null, "Opponent missing")
	_check(opponent.get_team_id() == TeamId.AWAY, "Opponent should be AWAY team")
	_check(teammate.get_team_id() == TeamId.HOME, "Teammate should be HOME team")
	_check(TeamId.HOME_ATTACK_DIRECTION.z > 0.0, "HOME should attack south (+Z)")
	_check(TeamId.AWAY_ATTACK_DIRECTION.z < 0.0, "AWAY should attack north (-Z)")

	await _reset_play(match_ctrl, player, teammate, opponent, ball)
	await _test_home_support(match_ctrl, player, teammate, opponent, ball)
	await _reset_play(match_ctrl, player, teammate, opponent, ball)
	await _test_opponent_pressure(match_ctrl, player, opponent, ball)
	await _reset_play(match_ctrl, player, teammate, opponent, ball)
	await _test_opponent_loose_acquire(match_ctrl, player, teammate, opponent, ball)
	await _reset_play(match_ctrl, player, teammate, opponent, ball)
	await _test_regression_pass_shot_goal(match_ctrl, player, teammate, ball)

	_finish()


func _reset_play(
	match_ctrl: Node,
	player: PlayerCharacter,
	teammate: PlayerCharacter,
	opponent: PlayerCharacter,
	ball: RigidBody3D
) -> void:
	player.set_possession_acquisition_enabled(false)
	teammate.set_possession_acquisition_enabled(false)
	opponent.set_possession_acquisition_enabled(false)
	if ball.has_method("release_as_loose_ball") and ball.has_possession():
		ball.release_as_loose_ball()
	if ball.has_method("force_match_reset"):
		ball.force_match_reset(Vector3(0.0, 0.21, -2.0))
	if player.has_possession():
		player.notify_possession_lost()
	if teammate.has_possession():
		teammate.notify_possession_lost()
	if opponent.has_possession():
		opponent.notify_possession_lost()
	player.reset_to_kickoff(Vector3(0.0, 0.1, 0.0))
	teammate.reset_to_kickoff(Vector3(3.0, 0.1, -3.0))
	opponent.reset_to_kickoff(Vector3(-2.5, 0.1, 3.0))
	match_ctrl.set_active_player(player)
	player.set_match_controls_enabled(true)
	teammate.set_match_controls_enabled(true)
	opponent.set_match_controls_enabled(true)
	teammate.set_ai_enabled(true)
	opponent.set_ai_enabled(true)
	if ball.has_method("set_match_play_enabled"):
		ball.set_match_play_enabled(true)
	match_ctrl.notify_possession_lost(player)
	await physics_frame
	await physics_frame
	player.set_possession_acquisition_enabled(true)
	teammate.set_possession_acquisition_enabled(true)
	opponent.set_possession_acquisition_enabled(true)


func _test_home_support(
	match_ctrl: Node,
	player: PlayerCharacter,
	teammate: PlayerCharacter,
	opponent: PlayerCharacter,
	ball: RigidBody3D
) -> void:
	opponent.global_position = Vector3(-5.0, 0.1, 4.0)
	teammate.global_position = Vector3(4.0, 0.1, -1.5)
	ball.global_position = player.global_position + Vector3(0.0, 0.11, -0.35)
	ball.linear_velocity = Vector3.ZERO
	ball.sleeping = false
	ball.freeze = false

	for i: int in range(45):
		await physics_frame
		if player.has_possession():
			break
	_check(player.has_possession(), "Player failed to acquire for support test")
	_check(match_ctrl.get_team_in_possession() == TeamId.HOME, "HOME should be team in possession")

	var start: Vector3 = teammate.global_position
	for i: int in range(100):
		await physics_frame

	_check(
		teammate.get_ai_state() == PlayerCharacter.AIState.SUPPORT
		or teammate.global_position.distance_to(start) > 0.35,
		"HOME teammate should move into support"
	)


func _test_opponent_pressure(
	match_ctrl: Node,
	player: PlayerCharacter,
	opponent: PlayerCharacter,
	ball: RigidBody3D
) -> void:
	ball.global_position = player.global_position + Vector3(0.0, 0.11, -0.35)
	ball.linear_velocity = Vector3.ZERO
	ball.sleeping = false
	ball.freeze = false
	for i: int in range(45):
		await physics_frame
		if player.has_possession():
			break
	_check(player.has_possession(), "Need HOME possession for pressure test")

	opponent.global_position = Vector3(-3.0, 0.1, 2.0)
	var start: Vector3 = opponent.global_position
	var start_distance: float = start.distance_to(player.global_position)
	for i: int in range(120):
		await physics_frame

	_check(
		opponent.get_ai_state() == PlayerCharacter.AIState.PRESSURE
		or opponent.global_position.distance_to(player.global_position) < start_distance,
		"AWAY opponent should pressure HOME possession"
	)
	_check(player.has_possession(), "Opponent should not auto-steal merely by approaching")


func _test_opponent_loose_acquire(
	match_ctrl: Node,
	player: PlayerCharacter,
	teammate: PlayerCharacter,
	opponent: PlayerCharacter,
	ball: RigidBody3D
) -> void:
	if ball.has_possession():
		ball.release_as_loose_ball()
	if player.has_possession():
		player.notify_possession_lost()
	if teammate.has_possession():
		teammate.notify_possession_lost()

	player.set_possession_acquisition_enabled(false)
	teammate.set_possession_acquisition_enabled(false)
	opponent.set_possession_acquisition_enabled(true)
	opponent.set_ai_enabled(true)
	opponent.set_match_controls_enabled(true)

	player.global_position = Vector3(7.0, 0.1, -5.0)
	teammate.global_position = Vector3(8.0, 0.1, -5.0)
	opponent.global_position = Vector3(0.0, 0.1, 1.0)
	ball.global_position = opponent.global_position + Vector3(0.0, 0.11, 0.25)
	ball.linear_velocity = Vector3.ZERO
	ball.sleeping = false
	ball.freeze = false
	if ball.has_method("set_match_play_enabled"):
		ball.set_match_play_enabled(true)
	match_ctrl.notify_possession_lost(player)
	_check(ball.is_loose(), "Ball should be loose before opponent acquisition test")

	opponent._ai_decision_timer = 0.0
	for i: int in range(40):
		await physics_frame
	_check(
		opponent.get_ai_state() == PlayerCharacter.AIState.PURSUE_LOOSE
		or opponent.global_position.distance_to(ball.global_position) < 1.75,
		"Opponent AI should pursue nearby loose ball (state=%s)" % opponent.get_ai_state_name()
	)

	var acquired: bool = opponent.has_possession()
	if not acquired:
		acquired = ball.try_acquire_possession(opponent)
	for i: int in range(20):
		if opponent.has_possession():
			acquired = true
			break
		await physics_frame

	_check(acquired and opponent.has_possession(), "Opponent should acquire a nearby loose ball")
	_check(match_ctrl.get_team_in_possession() == TeamId.AWAY, "Team possession should be AWAY")
	_check(match_ctrl.get_current_possessor() == opponent, "Current possessor should be opponent")
	_check(not player.has_possession(), "Only one possessor at a time (player)")
	_check(not teammate.has_possession(), "Only one possessor at a time (teammate)")
	_check(ball.get_collision_exceptions().has(opponent), "Possession collision exception should exist")
	_check(not ball.get_collision_exceptions().has(player), "Stale player exception should be cleared")

	player.set_possession_acquisition_enabled(true)
	teammate.set_possession_acquisition_enabled(true)


func _test_regression_pass_shot_goal(
	match_ctrl: Node,
	player: PlayerCharacter,
	teammate: PlayerCharacter,
	ball: RigidBody3D
) -> void:
	match_ctrl.set_active_player(player)
	player.global_position = Vector3(0.0, 0.1, 0.0)
	teammate.global_position = Vector3(0.0, 0.1, -3.5)
	player.set_facing_direction(Vector3(0.0, 0.0, -1.0))
	ball.global_position = player.global_position + Vector3(0.0, 0.11, -0.35)
	ball.linear_velocity = Vector3.ZERO
	ball.sleeping = false
	ball.freeze = false

	for i: int in range(45):
		await physics_frame
		if player.has_possession():
			break
	_check(player.has_possession(), "Regression acquisition failed")

	player.perform_charged_shot(0.0)
	await physics_frame
	_check(not player.has_possession(), "Charged shot regression failed")

	for i: int in range(45):
		await physics_frame

	ball.global_position = player.global_position + Vector3(0.0, 0.11, -0.35)
	ball.linear_velocity = Vector3.ZERO
	ball.sleeping = false
	for i: int in range(45):
		await physics_frame
		if player.has_possession():
			break
	_check(player.has_possession(), "Reacquire after shot regression failed")

	player.perform_short_pass()
	ball.global_position = teammate.global_position + Vector3(0.0, 0.11, 0.2)
	ball.linear_velocity = Vector3.ZERO
	for i: int in range(60):
		await physics_frame
		if teammate.has_possession():
			break
	_check(teammate.has_possession(), "Pass receive regression failed")

	var away_before: int = match_ctrl.get_away_score()
	if ball.has_method("force_match_reset"):
		ball.force_match_reset(Vector3(2.05, 0.21, -7.1))
	ball.global_position = Vector3(2.05, 0.21, -7.1)
	ball.linear_velocity = Vector3(0.0, 0.0, -2.0)
	ball.sleeping = false
	ball.freeze = false
	if ball.has_method("set_match_play_enabled"):
		ball.set_match_play_enabled(true)
	for i: int in range(120):
		await physics_frame
		if match_ctrl.get_away_score() > away_before:
			break
	_check(match_ctrl.get_away_score() == away_before + 1, "Goal scoring regression failed")

	for i: int in range(180):
		if match_ctrl.is_play_active():
			break
		await physics_frame
	_check(match_ctrl.is_play_active(), "Kickoff resume regression failed")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)


func _fail(message: String) -> void:
	_errors.append(message)
	_finish()


func _finish() -> void:
	if _errors.is_empty():
		print("[Validation] Milestone 5 checks passed")
		quit(0)
	else:
		for error: String in _errors:
			push_error("[Validation] " + error)
		quit(1)
