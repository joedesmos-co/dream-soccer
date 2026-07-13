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

	_check(player.is_user_controlled, "Player should be user controlled")
	_check(not teammate.is_user_controlled, "Teammate should not be user controlled")
	_check(teammate.is_in_group("player"), "Teammate missing 'player' group")

	# Regression audit: collision configuration unchanged.
	_check(player.collision_layer == 2, "Player layer regressed: %d" % player.collision_layer)
	_check(player.collision_mask == 5, "Player mask regressed: %d" % player.collision_mask)
	_check(teammate.collision_layer == 2, "Teammate layer wrong: %d" % teammate.collision_layer)
	_check(ball.collision_layer == 4, "Ball layer regressed: %d" % ball.collision_layer)
	_check(ball.collision_mask == 3, "Ball mask regressed: %d" % ball.collision_mask)
	var player_area: Area3D = player.get_node("PossessionArea") as Area3D
	var teammate_area: Area3D = teammate.get_node("PossessionArea") as Area3D
	_check(player_area.monitoring, "Player PossessionArea monitoring off")
	_check(teammate_area.monitoring, "Teammate PossessionArea monitoring off")

	# Acquisition: bring ball to the player and wait for overlap acquisition.
	ball.global_position = player.global_position + Vector3(0.0, 0.11, -0.4)
	ball.linear_velocity = Vector3.ZERO
	for i: int in range(30):
		await physics_frame
		if player.has_possession():
			break
	_check(player.has_possession(), "Player failed to acquire loose ball")
	if not player.has_possession():
		_finish()
		return

	# Regression audit: possessed ball follows the player (simple controller).
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

	# Milestone 1: short pass, fallback direction toward the teammate.
	player.perform_short_pass()
	_check(not player.has_possession(), "Passer still has possession after pass")
	_check(ball.is_loose(), "Ball not LOOSE immediately after pass")

	var frames_waited: int = 0
	while frames_waited < 600 and not teammate.has_possession():
		await physics_frame
		frames_waited += 1

	_check(
		teammate.has_possession(),
		"Teammate failed to receive pass within %d frames (ball at %s, vel %s)"
		% [frames_waited, str(ball.global_position), str(ball.linear_velocity)]
	)
	_check(not player.has_possession(), "Passer reacquired the ball instead of teammate")
	if teammate.has_possession():
		_check(ball.get_possessor() == teammate, "Ball possessor is not the teammate")
		var exceptions: Array = ball.get_collision_exceptions()
		_check(exceptions.has(teammate), "Missing ball-teammate collision exception")
		_check(not exceptions.has(player), "Stale ball-player collision exception remains")

	print(
		"[Validation] pass received after %d frames, follow separation %.2f"
		% [frames_waited, follow_separation]
	)
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)


func _fail(message: String) -> void:
	_errors.append(message)
	_finish()


func _finish() -> void:
	if _errors.is_empty():
		print("[Validation] Milestone 1 checks passed")
		quit(0)
	else:
		for error: String in _errors:
			push_error("[Validation] " + error)
		quit(1)
