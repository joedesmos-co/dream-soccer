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

	_check(player != null, "Player node missing")
	_check(teammate != null, "Teammate node missing")
	_check(ball != null, "Ball node missing")
	if not _errors.is_empty():
		_finish()
		return

	# Team identifier checks.
	_check(player.get_team_id() == 0, "Player team_id should be HOME (0)")
	_check(teammate.get_team_id() == 0, "Teammate team_id should be HOME (0)")
	_check(player.is_same_team(teammate), "Player and teammate should share a team")

	await _test_acquisition_and_dribble(player, ball)
	await _test_shot_power(player, ball)
	await _test_short_pass(player, teammate, ball)

	_finish()


func _test_acquisition_and_dribble(player: PlayerCharacter, ball: RigidBody3D) -> void:
	_check(player.collision_layer == 2, "Player layer regressed")
	_check(player.collision_mask == 5, "Player mask regressed")
	_check(ball.collision_layer == 4, "Ball layer regressed")
	_check(ball.collision_mask == 3, "Ball mask regressed")

	ball.global_position = player.global_position + Vector3(0.0, 0.11, -0.4)
	ball.linear_velocity = Vector3.ZERO
	for i: int in range(30):
		await physics_frame
		if player.has_possession():
			break
	_check(player.has_possession(), "Player failed to acquire loose ball")
	if not player.has_possession():
		return

	for i: int in range(60):
		player.global_position.x += 0.04
		await physics_frame

	var follow_separation: float = Vector2(
		player.global_position.x - ball.global_position.x,
		player.global_position.z - ball.global_position.z
	).length()
	_check(
		follow_separation < 1.5,
		"Possessed ball no longer follows player (separation %.2f)" % follow_separation
	)


func _test_short_pass(
	player: PlayerCharacter,
	teammate: PlayerCharacter,
	ball: RigidBody3D
) -> void:
	player.perform_short_pass()
	_check(not player.has_possession(), "Passer still has possession after pass")
	_check(ball.is_loose(), "Ball not LOOSE immediately after pass")

	var frames_waited: int = 0
	while frames_waited < 600 and not teammate.has_possession():
		await physics_frame
		frames_waited += 1

	_check(teammate.has_possession(), "Teammate failed to receive pass within %d frames" % frames_waited)
	_check(not player.has_possession(), "Passer reacquired the ball instead of teammate")
	if teammate.has_possession():
		_check(ball.get_possessor() == teammate, "Ball possessor is not the teammate")


func _test_shot_power(player: PlayerCharacter, ball: RigidBody3D) -> void:
	var min_speed: float = player.get_charged_shot_speed(0.0)
	var max_speed: float = player.get_charged_shot_speed(player.max_shot_charge_time)
	_check(is_equal_approx(min_speed, player.min_shot_speed), "Min shot speed mismatch")
	_check(is_equal_approx(max_speed, player.max_shot_speed), "Max shot speed mismatch")

	var shot_direction: Vector3 = player.get_facing_direction()
	player.perform_charged_shot(0.0)
	_check(not player.has_possession(), "Player still has possession after min shot")
	_check(ball.is_loose(), "Ball not LOOSE after min shot")

	await physics_frame
	var min_velocity: float = Vector3(ball.linear_velocity.x, 0.0, ball.linear_velocity.z).length()
	_check(
		absf(min_velocity - player.min_shot_speed) <= 0.5,
		"Min shot velocity expected %.2f got %.2f" % [player.min_shot_speed, min_velocity]
	)

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
	_check(player.has_possession(), "Player failed to reacquire ball for max shot test")
	if not player.has_possession():
		return

	player.perform_charged_shot(player.max_shot_charge_time)
	_check(not player.has_possession(), "Player still has possession after max shot")

	await physics_frame
	var max_velocity: float = Vector3(ball.linear_velocity.x, 0.0, ball.linear_velocity.z).length()
	_check(
		absf(max_velocity - player.max_shot_speed) <= 0.5,
		"Max shot velocity expected %.2f got %.2f" % [player.max_shot_speed, max_velocity]
	)
	_check(max_velocity > min_velocity, "Max shot should be faster than min shot")

	print(
		"[Validation] shot speeds min=%.2f max=%.2f direction=%s"
		% [min_velocity, max_velocity, str(shot_direction)]
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)


func _fail(message: String) -> void:
	_errors.append(message)
	_finish()


func _finish() -> void:
	if _errors.is_empty():
		print("[Validation] Milestone 2 checks passed")
		quit(0)
	else:
		for error: String in _errors:
			push_error("[Validation] " + error)
		quit(1)
