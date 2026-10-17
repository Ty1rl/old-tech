extends SceneTree

const Tuning = preload("res://scenes/prototype/tuning.gd")

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func run() -> void:
	var packed := load("res://scenes/prototype/arena.tscn") as PackedScene
	var arena = packed.instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame

	# Disable arena's automatic physics tick so we can drive director.step deterministically
	arena.set_physics_process(false)
	var director = arena.director
	var player = arena.player
	arena.reset_arena()

	# 1. Baseline reset_state starts with stationary target
	expect(director.enemies.size() == 1 and director.enemies[0].kind == &"target", "reset_state spawns initial target")
	var target = director.enemies[0]
	expect(is_equal_approx(target.position.y, 0.0) and is_equal_approx(target.health, Tuning.ENEMIES.target.health), "Target root sits at floor y=0 with tuned health")

	# 2. Stationary target does not move or deal contact damage even when overlapping player
	director.clear()
	expect(director.enemies.is_empty(), "clear() removes all active enemies")
	var overlap_target = director.spawn(&"target", Vector3.ZERO)
	for i in range(10):
		director.step(0.2, player)
	expect(is_equal_approx(player.health, 100.0) and overlap_target.position.length() < 0.001, "Stationary test target never moves or damages player")

	# 3. Brute directional armor: front vs side vs rear using contact_world (not player position)
	director.clear()
	player.reset_state()
	player.position = Vector3(0.0, 0.55, 0.0) # Player stands in front (+Z) of the brute
	var brute = director.spawn(&"brute", Vector3(0.0, 0.0, -6.0))
	brute.facing = Vector3(0.0, 0.0, 1.0) # Facing +Z toward player

	var front_hit: Dictionary = brute.hit(40.0, Vector3(0.0, 0.0, -5.0))
	expect(front_hit.get("armored", false) == true and is_equal_approx(front_hit.get("dealt", 0.0), 10.0), "Brute front contact reduces damage by front_multiplier (0.25x)")
	expect(is_equal_approx(brute.health, 170.0) and front_hit.get("killed", true) == false, "Brute health reflects reduced front damage")

	var side_hit: Dictionary = brute.hit(40.0, Vector3(1.0, 0.0, -6.0))
	expect(side_hit.get("armored", true) == false and is_equal_approx(side_hit.get("dealt", 0.0), 40.0), "Brute 90-degree side contact deals full unarmored damage")

	# Rear contact while player is still in front at (0, 0, 0): proves contact_world is used, not player position
	var rear_hit: Dictionary = brute.hit(40.0, Vector3(0.0, 0.0, -7.0))
	expect(rear_hit.get("armored", true) == false and is_equal_approx(rear_hit.get("dealt", 0.0), 40.0), "Brute rear contact deals full damage even when player stands in front")
	expect(is_equal_approx(brute.health, 90.0), "Brute health after front + side + rear hits is 90")

	# 4. Kill, actual HP lost clamping, immediate dead rejection, and next-step pruning
	director.clear()
	var swarmer = director.spawn(&"swarmer", Vector3(0.0, 0.0, -5.0))
	var first_swarmer_hit: Dictionary = swarmer.hit(20.0, Vector3(0.0, 0.0, -4.6))
	expect(is_equal_approx(first_swarmer_hit.get("dealt", 0.0), 20.0) and not first_swarmer_hit.get("killed", true), "Swarmer first hit deals 20 and leaves 12 HP")
	var lethal_hit: Dictionary = swarmer.hit(50.0, Vector3(0.0, 0.0, -4.6))
	expect(is_equal_approx(lethal_hit.get("dealt", 0.0), 12.0) and lethal_hit.get("killed", false) == true, "Lethal hit reports actual remaining HP lost (12.0) and killed=true")
	var post_death_hit: Dictionary = swarmer.hit(25.0, Vector3(0.0, 0.0, -4.6))
	expect(is_equal_approx(post_death_hit.get("dealt", -1.0), 0.0) and post_death_hit.get("killed", true) == false, "Dead enemy immediately rejects further damage before next step")
	director.step(0.05, player)
	expect(director.enemies.is_empty(), "Dead enemy leaves director.enemies on next step()")

	# 5. Swarmer approach, XZ-only contact judgment, world-delta contact cooldown, and time-slow scaling
	director.clear()
	player.reset_state()
	player.position = Vector3(0.0, 4.0, 0.0) # Elevated Y to verify XZ-only contact check
	var runner = director.spawn(&"swarmer", Vector3(0.0, 0.0, -2.0))
	for i in range(10):
		director.step(0.05, player)
	expect(is_equal_approx(player.health, 95.0), "Swarmer closes in XZ and deals 5 contact damage ignoring player Y height")

	# Step 0.4 world seconds (< 1.0s CONTACT_COOLDOWN): no second hit yet
	director.step(0.4, player)
	expect(is_equal_approx(player.health, 95.0), "Contact cooldown prevents immediate repeat damage within 1.0 world second")

	# Under time slow (world_scale = 0.18), 2.0 real seconds = 0.36 world seconds (total 0.76s < 1.0s): still on cooldown
	for i in range(20):
		director.step(0.1 * Tuning.SLOW.scale, player)
	expect(is_equal_approx(player.health, 95.0), "Time-slowed world_delta scales enemy contact cooldown")

	# Advance remaining 0.3 world seconds (total 1.06s >= 1.0s): second contact hit triggers
	director.step(0.3, player)
	expect(is_equal_approx(player.health, 90.0), "Swarmer deals second contact hit once world-time cooldown expires")

	# 6. Dead-player policy: stop dealing damage at zero HP
	player.health = 3.0
	director.step(1.05, player)
	expect(is_equal_approx(player.health, 0.0), "Contact damage clamps player health at 0.0")
	director.step(2.0, player)
	expect(is_equal_approx(player.health, 0.0), "Enemies stop dealing contact damage once player health is 0.0")

	# 7. Skirmisher finite sidestep/orbit within cone range -> commit and contact hit
	director.clear()
	player.reset_state()
	var skirm = director.spawn(&"skirmisher", Vector3(0.0, 0.0, -5.5))
	for i in range(12):
		director.step(0.1, player)
	var orbit_dist := Vector2(skirm.position.x, skirm.position.z).length()
	expect(absf(skirm.position.x) > 0.25 and orbit_dist <= Tuning.CONE.range, "Skirmisher sidesteps laterally while staying within cone range (<= 5.0)")

	var committed_and_hit := false
	for i in range(30):
		director.step(0.1, player)
		if player.health < 100.0:
			committed_and_hit = true
			break
	expect(committed_and_hit and is_equal_approx(player.health, 100.0 - Tuning.ENEMIES.skirmisher.damage), "Skirmisher commits after finite orbit and lands contact damage")

	# 8. spawn_group() and reset_state() restore clean state
	director.clear()
	director.spawn_group()
	expect(director.enemies.size() == 4, "spawn_group() creates modest 4-enemy mixed encounter")
	director.reset_state()
	expect(director.enemies.size() == 1 and director.enemies[0].kind == &"target", "reset_state() clears mixed group and restores single target")

	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
