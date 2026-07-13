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
	await physics_frame
	await physics_frame

	var match: Node = main
	var player: PlayerCharacter = main.get_node("Player") as PlayerCharacter
	var teammate: PlayerCharacter = main.get_node("Teammate") as PlayerCharacter
	var ball: RigidBody3D = main.get_node("Ball") as RigidBody3D

	_check(match.has_method("get_home_score"), "Match controller missing on Main")
	_check(player.get_team_id() == 0, "Player team_id regressed")
	_check(teammate.get_team_id() == 0, "Teammate team_id regressed")
	if not _errors.is_empty():
		_finish()
		return

	await _test_regression(player, teammate, ball)
	await _test_home_goal_scoring(match, ball)
	await _test_away_goal_scoring(match, ball)

	_finish()


func _test_regression(
	player: PlayerCharacter,
	teammate: PlayerCharacter,
	ball: RigidBody3D
) -> void:
	_check(player.collision_layer == 2 and player.collision_mask == 5, "Player collision regressed")
	_check(ball.collision_layer == 4 and ball.collision_mask == 3, "Ball collision regressed")
	_check(ball.is_match_play_enabled(), "Ball should start with match play enabled")

	ball.global_position = player.global_position + Vector3(0.0, 0.11, -0.4)
	ball.linear_velocity = Vector3.ZERO
	ball.sleeping = false
	for i: int in range(30):
		await physics_frame
		if player.has_possession():
			break
	_check(player.has_possession(), "Possession acquisition regressed")

	player.perform_charged_shot(0.0)
	_check(not player.has_possession(), "Charged shot regressed")
	await physics_frame
	var shot_speed: float = Vector3(ball.linear_velocity.x, 0.0, ball.linear_velocity.z).length()
	_check(shot_speed > 5.0, "Shot velocity regressed (%.2f)" % shot_speed)

	for i: int in range(40):
		await physics_frame

	ball.global_position = player.global_position + Vector3(0.0, 0.11, -0.4)
	ball.linear_velocity = Vector3.ZERO
	ball.sleeping = false
	if not ball.try_acquire_possession(player):
		for i: int in range(30):
			await physics_frame
			if player.has_possession():
				break
	_check(player.has_possession(), "Reacquire after shot regressed")

	player.perform_short_pass()
	var frames: int = 0
	while frames < 600 and not teammate.has_possession():
		await physics_frame
		frames += 1
	_check(teammate.has_possession(), "Short pass receiving regressed")

	if teammate.has_possession() and ball.has_method("force_match_reset"):
		ball.force_match_reset(Vector3(0.0, 0.21, -2.0))
		await physics_frame


func _test_home_goal_scoring(match: Node, ball: RigidBody3D) -> void:
	var home_before: int = match.get_home_score()
	var away_before: int = match.get_away_score()

	ball.global_position = Vector3(0.0, 0.21, 7.4)
	ball.linear_velocity = Vector3(0.0, 0.0, 2.0)
	ball.sleeping = false
	if ball.has_method("set_match_play_enabled"):
		ball.set_match_play_enabled(true)

	for i: int in range(120):
		await physics_frame
		if match.get_home_score() > home_before:
			break

	_check(match.get_home_score() == home_before + 1, "HOME score should increment once")
	_check(match.get_away_score() == away_before, "AWAY score should not change for south goal")

	var score_after_first: int = match.get_home_score()
	for i: int in range(90):
		await physics_frame
	_check(
		match.get_home_score() == score_after_first,
		"Duplicate HOME goal counted while ball remained in trigger"
	)

	for i: int in range(30):
		if not match.is_play_active():
			await physics_frame
		else:
			break
	_check(
		ball.global_position.distance_to(Vector3(0.0, 0.21, -2.0)) < 0.5,
		"Ball not reset to kickoff position during delay (at %s)" % str(ball.global_position)
	)
	_check(ball.is_loose(), "Ball should be LOOSE after reset")
	_check(ball.get_collision_exceptions().is_empty(), "Ball collision exceptions should be cleared")

	await _wait_for_playing(match)
	_check(match.is_play_active(), "Match should return to PLAYING after kickoff delay")
	_check(ball.is_match_play_enabled(), "Ball match play should re-enable after kickoff")


func _test_away_goal_scoring(match: Node, ball: RigidBody3D) -> void:
	var home_before: int = match.get_home_score()
	var away_before: int = match.get_away_score()

	ball.global_position = Vector3(0.0, 0.21, -7.4)
	ball.linear_velocity = Vector3(0.0, 0.0, -2.0)
	ball.sleeping = false
	if ball.has_method("set_match_play_enabled"):
		ball.set_match_play_enabled(true)

	for i: int in range(120):
		await physics_frame
		if match.get_away_score() > away_before:
			break

	_check(match.get_away_score() == away_before + 1, "AWAY score should increment for north goal")
	_check(match.get_home_score() == home_before, "HOME score should not change for north goal")

	await _wait_for_playing(match)
	print(
		"[Validation] final score HOME %d - %d AWAY"
		% [match.get_home_score(), match.get_away_score()]
	)


func _wait_for_playing(match: Node) -> void:
	for i: int in range(300):
		if match.is_play_active():
			return
		await physics_frame
	_check(false, "Match did not return to PLAYING within timeout")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)


func _fail(message: String) -> void:
	_errors.append(message)
	_finish()


func _finish() -> void:
	if _errors.is_empty():
		print("[Validation] Milestone 3 checks passed")
		quit(0)
	else:
		for error: String in _errors:
			push_error("[Validation] " + error)
		quit(1)
