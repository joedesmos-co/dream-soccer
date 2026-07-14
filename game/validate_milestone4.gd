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

	var player: PlayerCharacter = main.get_node("Player") as PlayerCharacter
	var teammate: PlayerCharacter = main.get_node("Teammate") as PlayerCharacter
	var ball: RigidBody3D = main.get_node("Ball") as RigidBody3D
	var north_gk: GoalkeeperCharacter = main.get_node("Goalkeepers/NorthGoalkeeper") as GoalkeeperCharacter
	var south_gk: GoalkeeperCharacter = main.get_node("Goalkeepers/SouthGoalkeeper") as GoalkeeperCharacter

	_check(north_gk != null and south_gk != null, "Goalkeepers missing from main scene")
	_check(north_gk.get_team_id() == TeamId.HOME, "North GK should be HOME team")
	_check(south_gk.get_team_id() == TeamId.AWAY, "South GK should be AWAY team")
	_check(north_gk.is_in_group("goalkeeper"), "North GK missing goalkeeper group")
	_check(not north_gk.is_in_group("player"), "North GK must not be in player group")
	if not _errors.is_empty():
		_finish()
		return

	await _test_regression(player, teammate, ball)
	await _test_south_goalkeeper_save_attempt(main, south_gk, ball)
	north_gk.reset_to_kickoff()
	south_gk.reset_to_kickoff()
	await physics_frame
	await _test_north_goalkeeper_save_and_goal(main, north_gk, ball)

	_finish()


func _test_regression(
	player: PlayerCharacter,
	teammate: PlayerCharacter,
	ball: RigidBody3D
) -> void:
	ball.global_position = player.global_position + Vector3(0.0, 0.11, -0.4)
	ball.linear_velocity = Vector3.ZERO
	ball.sleeping = false
	if ball.has_method("set_match_play_enabled"):
		ball.set_match_play_enabled(true)

	for i: int in range(30):
		await physics_frame
		if player.has_possession():
			break
	_check(player.has_possession(), "Possession acquisition regressed")

	player.perform_charged_shot(0.0)
	_check(not player.has_possession(), "Shooting regressed")

	for i: int in range(40):
		await physics_frame

	ball.global_position = player.global_position + Vector3(0.0, 0.11, -0.4)
	ball.linear_velocity = Vector3.ZERO
	ball.sleeping = false
	if ball.has_method("set_match_play_enabled"):
		ball.set_match_play_enabled(true)
	for i: int in range(60):
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

	if ball.has_method("force_match_reset"):
		ball.force_match_reset(Vector3(0.0, 0.21, -2.0))
		await physics_frame


func _test_south_goalkeeper_save_attempt(
	match: Node,
	south_gk: GoalkeeperCharacter,
	ball: RigidBody3D
) -> void:
	var home_before: int = match.get_home_score()
	var gk_start: Vector3 = south_gk.global_position
	var ball_start_velocity: Vector3 = Vector3(0.0, 0.0, 14.0)

	ball.global_position = Vector3(0.0, 0.21, 4.8)
	ball.linear_velocity = Vector3(0.0, 0.0, 7.0)
	ball.angular_velocity = Vector3.ZERO
	ball.sleeping = false
	ball.freeze = false
	if ball.has_method("set_match_play_enabled"):
		ball.set_match_play_enabled(true)

	var save_attempted: bool = false
	var velocity_changed: bool = false
	var gk_moved: bool = false

	for i: int in range(120):
		await physics_frame
		if south_gk.did_attempt_save_recently():
			save_attempted = true
		if ball.linear_velocity.distance_to(ball_start_velocity) > 1.0:
			velocity_changed = true
		if south_gk.global_position.distance_to(gk_start) > 0.15:
			gk_moved = true

	_check(save_attempted or velocity_changed or gk_moved, "South GK did not attempt save or react to shot")
	_check(match.get_home_score() == home_before, "Unexpected HOME goal during save test")

	for i: int in range(120):
		if match.is_play_active():
			break
		await physics_frame

	print(
		"[Validation] south GK save_attempt=%s velocity_changed=%s gk_moved=%s"
		% [save_attempted, velocity_changed, gk_moved]
	)


func _test_north_goalkeeper_save_and_goal(
	match: Node,
	north_gk: GoalkeeperCharacter,
	ball: RigidBody3D
) -> void:
	var away_before: int = match.get_away_score()
	var gk_home: Vector3 = Vector3(0.0, 0.1, -6.8)

	ball.global_position = Vector3(0.0, 0.21, -6.4)
	ball.linear_velocity = Vector3(0.0, 0.0, -9.0)
	ball.angular_velocity = Vector3.ZERO
	ball.sleeping = false
	ball.freeze = false
	if ball.has_method("set_match_play_enabled"):
		ball.set_match_play_enabled(true)

	var save_attempted: bool = false
	var gk_moved: bool = false
	var gk_start: Vector3 = north_gk.global_position
	for i: int in range(90):
		await physics_frame
		if north_gk.did_attempt_save_recently():
			save_attempted = true
		if north_gk.global_position.distance_to(gk_start) > 0.1:
			gk_moved = true

	_check(
		save_attempted or gk_moved or _ball_velocity_changed(ball, Vector3(0.0, 0.0, -9.0)),
		"North GK did not attempt save on approaching shot"
	)

	var scored: bool = false
	var score_after_goal: int = away_before
	ball.global_position = Vector3(2.05, 0.21, -7.1)
	ball.linear_velocity = Vector3(0.0, 0.0, -2.0)
	ball.angular_velocity = Vector3.ZERO
	ball.sleeping = false
	ball.freeze = false
	if ball.has_method("set_match_play_enabled"):
		ball.set_match_play_enabled(true)

	for i: int in range(120):
		await physics_frame
		if match.get_away_score() > away_before:
			scored = true
			score_after_goal = match.get_away_score()
			break

	var duplicate_count: int = 0
	for i: int in range(60):
		await physics_frame
		if match.get_away_score() > score_after_goal:
			duplicate_count += 1

	_check(scored, "Some shots should still score against goalkeeper")
	if scored:
		_check(score_after_goal - away_before == 1, "Goal should increment exactly once")
		_check(duplicate_count == 0, "Duplicate goal counted while ball remained in trigger")

		for i: int in range(120):
			if match.is_play_active():
				break
			await physics_frame

		_check(match.is_play_active(), "Match should resume after goal")
		_check(
			Vector2(north_gk.global_position.x, north_gk.global_position.z).distance_to(
				Vector2(gk_home.x, gk_home.z)
			) < 0.35,
			"North GK not reset after goal (at %s)" % str(north_gk.global_position)
		)
		_check(ball.is_loose(), "Ball should be loose after goal reset")

	print(
		"[Validation] north GK save=%s scored=%s final AWAY=%d"
		% [save_attempted, scored, match.get_away_score()]
	)


func _ball_velocity_changed(ball: RigidBody3D, original: Vector3) -> bool:
	return ball.linear_velocity.distance_to(original) > 1.0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)


func _fail(message: String) -> void:
	_errors.append(message)
	_finish()


func _finish() -> void:
	if _errors.is_empty():
		print("[Validation] Milestone 4 checks passed")
		quit(0)
	else:
		for error: String in _errors:
			push_error("[Validation] " + error)
		quit(1)
