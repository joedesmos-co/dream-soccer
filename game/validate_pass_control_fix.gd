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
	await physics_frame

	var match_ctrl: Node = main
	var player: PlayerCharacter = main.get_node("Player") as PlayerCharacter
	var teammate: PlayerCharacter = main.get_node("Teammate") as PlayerCharacter
	var ball: RigidBody3D = main.get_node("Ball") as RigidBody3D

	_check(match_ctrl.get_active_player() == player, "Active player should start as blue Player")

	await _test_pass_targeting(player, teammate)
	await _test_aim_and_shot(player, ball)
	await _test_pass_and_control_transfer(match_ctrl, player, teammate, ball)
	await _test_regression_goal(match_ctrl, ball)

	_finish()


func _test_pass_targeting(player: PlayerCharacter, teammate: PlayerCharacter) -> void:
	# Fake a nearer teammate-like option outside the aim cone by scoring only.
	player.set_facing_direction(Vector3(0.0, 0.0, -1.0))
	player.global_position = Vector3(0.0, 0.1, 0.0)
	teammate.global_position = Vector3(2.0, 0.1, -3.0)

	var aim_toward_teammate: Vector3 = (teammate.global_position - player.global_position).normalized()
	aim_toward_teammate.y = 0.0
	var selected: PlayerCharacter = player.find_pass_target(aim_toward_teammate)
	_check(selected == teammate, "Teammate inside aim cone should be selected")

	var selected_away: PlayerCharacter = player.find_pass_target(Vector3(0.0, 0.0, 1.0))
	_check(selected_away == null, "Pass into empty opposite direction should have no teammate target")

	var score_on: float = player.score_pass_candidate(teammate, aim_toward_teammate)
	var score_off: float = player.score_pass_candidate(teammate, Vector3(0.0, 0.0, 1.0))
	_check(score_on < score_off, "Aim cone candidate should score better than opposite-direction aim")


func _test_aim_and_shot(player: PlayerCharacter, ball: RigidBody3D) -> void:
	player.set_user_controlled(true)
	player.set_facing_direction(Vector3(0.0, 0.0, -1.0))
	ball.global_position = player.global_position + Vector3(0.0, 0.11, -0.4)
	ball.linear_velocity = Vector3.ZERO
	ball.sleeping = false
	if ball.has_method("set_match_play_enabled"):
		ball.set_match_play_enabled(true)

	for i: int in range(40):
		await physics_frame
		if player.has_possession():
			break
	_check(player.has_possession(), "Player failed to acquire for shot aim test")
	if not player.has_possession():
		return

	_check(
		player.get_aim_direction().dot(Vector3(0.0, 0.0, -1.0)) > 0.95,
		"Standing aim should use north facing"
	)
	player.perform_charged_shot(0.0)
	await physics_frame
	var shot_dir: Vector3 = Vector3(ball.linear_velocity.x, 0.0, ball.linear_velocity.z).normalized()
	_check(shot_dir.dot(Vector3(0.0, 0.0, -1.0)) > 0.9, "Standing north shot should travel north (got %s)" % str(shot_dir))

	for i: int in range(40):
		await physics_frame

	ball.global_position = player.global_position + Vector3(0.0, 0.11, -0.4)
	ball.linear_velocity = Vector3.ZERO
	ball.sleeping = false
	for i: int in range(40):
		await physics_frame
		if player.has_possession():
			break
	_check(player.has_possession(), "Reacquire for movement-aim shot failed")
	if not player.has_possession():
		return

	player.set_facing_direction(Vector3(0.0, 0.0, -1.0))
	Input.action_press("move_right")
	await physics_frame
	await physics_frame
	var aim: Vector3 = player.get_aim_direction()
	_check(aim.dot(Vector3(1.0, 0.0, 0.0)) > 0.5, "Held movement input should override facing for aim (got %s)" % str(aim))
	player.perform_charged_shot(0.0)
	Input.action_release("move_right")
	await physics_frame
	var move_shot_dir: Vector3 = Vector3(ball.linear_velocity.x, 0.0, ball.linear_velocity.z).normalized()
	_check(move_shot_dir.dot(Vector3(0.0, 0.0, -1.0)) < 0.5, "Movement-aimed shot should not travel purely north")
	_check(move_shot_dir.x > 0.3, "Movement-aimed shot should include eastward component (got %s)" % str(move_shot_dir))


func _test_pass_and_control_transfer(
	match_ctrl: Node,
	player: PlayerCharacter,
	teammate: PlayerCharacter,
	ball: RigidBody3D
) -> void:
	Input.action_release("move_right")
	Input.action_release("move_left")
	Input.action_release("move_forward")
	Input.action_release("move_back")
	await physics_frame

	match_ctrl.set_active_player(player)
	player.global_position = Vector3(0.0, 0.1, 0.0)
	teammate.global_position = Vector3(0.0, 0.1, -4.0)
	player.set_facing_direction(Vector3(0.0, 0.0, -1.0))

	ball.global_position = player.global_position + Vector3(0.0, 0.11, -0.4)
	ball.linear_velocity = Vector3.ZERO
	ball.sleeping = false
	if ball.has_method("set_match_play_enabled"):
		ball.set_match_play_enabled(true)
	for i: int in range(40):
		await physics_frame
		if player.has_possession():
			break
	_check(player.has_possession(), "Pass transfer setup acquisition failed")
	if not player.has_possession():
		return

	var target: PlayerCharacter = player.find_pass_target(Vector3(0.0, 0.0, -1.0))
	_check(target == teammate, "Directional pass should target teammate ahead")

	# Explicit north aim for the pass action so leftover input cannot pollute the test.
	player.set_facing_direction(Vector3(0.0, 0.0, -1.0))
	player.perform_short_pass()
	_check(match_ctrl.get_intended_receiver() == teammate, "Intended receiver should be teammate after pass")
	_check(not player.has_possession(), "Passer should lose possession after pass")

	# Deliver the pass immediately to the intended receiver without letting a long miss enter a goal.
	ball.global_position = teammate.global_position + Vector3(0.0, 0.11, 0.2)
	ball.linear_velocity = Vector3(0.0, 0.0, -1.0)
	ball.sleeping = false
	ball.freeze = false
	if ball.has_method("set_match_play_enabled"):
		ball.set_match_play_enabled(true)
	teammate.set_possession_acquisition_enabled(true)
	player.set_possession_acquisition_enabled(true)

	var frames: int = 0
	while frames < 90 and not teammate.has_possession():
		await physics_frame
		frames += 1

	_check(teammate.has_possession(), "Teammate failed to receive pass")
	_check(match_ctrl.get_active_player() == teammate, "Control should transfer to receiver")
	_check(teammate.is_user_controlled, "Receiver should be user controlled")
	_check(not player.is_user_controlled, "Former player should stop reading user input")
	_check(match_ctrl.get_intended_receiver() == null, "Intended receiver should clear after transfer")

	# Restore starter control for later regression tests.
	match_ctrl.set_active_player(player)
	if ball.has_method("force_match_reset"):
		ball.force_match_reset(Vector3(0.0, 0.21, -2.0))
	await physics_frame


func _test_regression_goal(match_ctrl: Node, ball: RigidBody3D) -> void:
	var away_before: int = match_ctrl.get_away_score()
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
	_check(match_ctrl.get_away_score() == away_before + 1, "Goal scoring regressed")

	for i: int in range(180):
		if match_ctrl.is_play_active():
			break
		await physics_frame
	_check(match_ctrl.is_play_active(), "Kickoff resume regressed")
	_check(match_ctrl.get_active_player().name == "Player", "Kickoff should restore blue as active player")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)


func _fail(message: String) -> void:
	_errors.append(message)
	_finish()


func _finish() -> void:
	if _errors.is_empty():
		print("[Validation] Pass/control/shot correction checks passed")
		quit(0)
	else:
		for error: String in _errors:
			push_error("[Validation] " + error)
		quit(1)
