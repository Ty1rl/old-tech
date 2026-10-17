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

	# 9. Round C: Crowd control (shove knockback + stagger suppression + recovery) on swarmer
	director.clear()
	player.reset_state()
	player.position = Vector3.ZERO
	var shoved_swarmer = director.spawn(&"swarmer", Vector3(0.0, 0.0, -1.0))
	shoved_swarmer.apply_control(Vector3(0.0, 0.0, -1.0), float(Tuning.CONTROL.impulse), float(Tuning.CONTROL.stagger))
	expect(shoved_swarmer.is_staggered() and is_equal_approx(shoved_swarmer.stagger_timer, float(Tuning.CONTROL.stagger)), "apply_control sets stagger_timer on swarmer")
	director.step(0.2, player)
	expect(shoved_swarmer.position.z < -2.2, "Strong shove visibly displaces swarmer away from player")
	expect(is_equal_approx(player.health, 100.0), "Staggered enemy suppresses contact attack even when starting in contact range")

	# Place staggered swarmer right on top of player while still staggered: still no contact damage
	shoved_swarmer.position = Vector3(0.0, 0.0, -0.5)
	shoved_swarmer.knockback_vel = Vector3.ZERO
	director.step(0.2, player)
	expect(shoved_swarmer.is_staggered() and is_equal_approx(player.health, 100.0), "Staggered swarmer does not deal contact damage while stagger_timer > 0")

	# Advance past remaining stagger (0.25s left) so swarmer recovers and resumes AI + contact attack
	director.step(0.4, player)
	expect(not shoved_swarmer.is_staggered() and is_equal_approx(player.health, 95.0), "Recovered swarmer resumes normal AI and contact attack after stagger expires")

	# 10. Round C: Brute knockback & stagger resistance + Target anchored feedback
	director.clear()
	var ctrl_swarmer = director.spawn(&"swarmer", Vector3(-3.0, 0.0, -4.0))
	var ctrl_brute = director.spawn(&"brute", Vector3(0.0, 0.0, -4.0))
	var ctrl_target = director.spawn(&"target", Vector3(3.0, 0.0, -4.0))
	var shove_dir := Vector3(0.0, 0.0, -1.0)
	ctrl_swarmer.apply_control(shove_dir, float(Tuning.CONTROL.impulse), float(Tuning.CONTROL.stagger))
	ctrl_brute.apply_control(shove_dir, float(Tuning.CONTROL.impulse), float(Tuning.CONTROL.stagger))
	ctrl_target.apply_control(shove_dir, float(Tuning.CONTROL.impulse), float(Tuning.CONTROL.stagger))

	var resist := float(Tuning.CONTROL.brute_resistance)
	expect(is_equal_approx(ctrl_brute.stagger_timer, float(Tuning.CONTROL.stagger) * resist), "Brute stagger duration scales by Tuning.CONTROL.brute_resistance (0.25)")
	expect(is_equal_approx(ctrl_brute.knockback_vel.length(), ctrl_swarmer.knockback_vel.length() * resist), "Brute knockback impulse scales by Tuning.CONTROL.brute_resistance (0.25)")
	expect(not ctrl_target.is_staggered() and is_equal_approx(ctrl_target.knockback_vel.length(), 0.0) and ctrl_target.feedback_label.text == "ANCHORED", "Target remains unstaggered with zero knockback velocity and shows ANCHORED feedback")

	director.step(0.15, player)
	var swarmer_disp := absf(ctrl_swarmer.position.z - (-4.0))
	var brute_disp := absf(ctrl_brute.position.z - (-4.0))
	var target_disp: float = ctrl_target.position.distance_to(Vector3(3.0, 0.0, -4.0))
	expect(is_equal_approx(brute_disp, swarmer_disp * resist), "Brute displacement over world_delta scales by brute_resistance")
	expect(target_disp < 0.0001, "Stationary target stays anchored in place after step()")

	# 11. Round C: Frame-delta and time-slow consistency for knockback + stagger recovery
	director.clear()
	player.reset_state()
	player.position = Vector3(0.0, 0.0, 10.0)
	var enemy_coarse = director.spawn(&"swarmer", Vector3(-2.0, 0.0, 2.0))
	enemy_coarse.apply_control(Vector3(0.0, 0.0, -1.0), 10.0, 0.3)
	for i in range(5):
		enemy_coarse.step_enemy(0.1, player, [])
	var coarse_pos: Vector3 = enemy_coarse.position
	var coarse_vel: Vector3 = enemy_coarse.knockback_vel

	director.clear()
	var enemy_fine = director.spawn(&"swarmer", Vector3(-2.0, 0.0, 2.0))
	enemy_fine.apply_control(Vector3(0.0, 0.0, -1.0), 10.0, 0.3)
	for i in range(50):
		enemy_fine.step_enemy(0.01, player, [])
	expect(coarse_pos.distance_to(enemy_fine.position) < 0.001 and coarse_vel.distance_to(enemy_fine.knockback_vel) < 0.001, "Knockback drag and mid-tick stagger recovery are frame-delta invariant")

	# 12. Round C: Cover-safe knockback (no tunneling or overlapping Cover.RECTANGLES)
	director.clear()
	# Left cover rectangle is Rect2(-6, -6, 2, 3) -> x in [-6, -4], z in [-6, -3]
	var kb_cover_enemy = director.spawn(&"swarmer", Vector3(-5.0, 0.0, -2.2))
	kb_cover_enemy.apply_control(Vector3(0.0, 0.0, -1.0), float(Tuning.CONTROL.impulse), float(Tuning.CONTROL.stagger))
	var crossed_or_overlapped := false
	for i in range(15):
		kb_cover_enemy.step_enemy(0.04, player, [])
		if kb_cover_enemy.overlaps_cover(-0.005) or kb_cover_enemy.position.z < -3.0:
			crossed_or_overlapped = true
	expect(not crossed_or_overlapped, "Shoved enemy stops/slides against cover boundary without crossing or overlapping cover")

	# 13. Round C: Cover-safe AI navigation around cover box without getting stuck
	director.clear()
	player.reset_state()
	player.position = Vector3(-5.0, 0.0, 0.0) # Directly Across Rect2(-6, -6, 2, 3) from (-5, 0, -7.2)
	var nav_swarmer = director.spawn(&"swarmer", Vector3(-5.0, 0.0, -7.2))
	var nav_overlapped := false
	var reached_player := false
	for i in range(90):
		director.step(0.05, player)
		if nav_swarmer.overlaps_cover(-0.005):
			nav_overlapped = true
		if player.health < 100.0:
			reached_player = true
			break
	expect(not nav_overlapped and reached_player, "Enemy spawned behind cover steers around the cover box and reaches player without overlapping cover")

	# 14. Round C: Bounded encounter schedule, live cap (<= 6), victory, defeat stop-spawning, and sandbox reset
	director.clear()
	player.reset_state()
	expect(director.status_text() == "Sandbox", "Default director status_text() is Sandbox")
	director.start_encounter()
	expect(director.encounter_active and director.status_text().begins_with("Encounter Wave 1/"), "start_encounter() enters running state and updates status_text()")
	expect(director.enemies.size() > 0 and director.enemies.size() <= int(Tuning.ENCOUNTER.max_enemies), "Wave 0 spawns initial enemies within max_enemies cap")

	# Step across multiple 12s wave intervals without killing enemies to verify live cap <= 6
	var cap_exceeded := false
	for i in range(6):
		director.step(12.0, player)
		if director.enemies.size() > int(Tuning.ENCOUNTER.max_enemies):
			cap_exceeded = true
	expect(not cap_exceeded and director.enemies.size() == int(Tuning.ENCOUNTER.max_enemies), "Encounter wave spawns never exceed Tuning.ENCOUNTER.max_enemies (6)")

	# Advance past full 75s duration, then kill all live enemies -> Victory
	director.step(10.0, player)
	expect(director.encounter_elapsed >= float(Tuning.ENCOUNTER.duration) and director.encounter_state == &"running", "Encounter remains running at 75s while live enemies remain")
	for e in director.enemies:
		e.hit(999.0, e.position - e.facing)
	director.step(0.05, player)
	expect(director.encounter_state == &"victory" and director.status_text().contains("Victory"), "Encounter transitions to Victory when 75s schedule finishes and all live enemies are gone")

	# Defeat condition: at 0 player HP, stop spawning and report reset hint
	player.reset_state()
	director.start_encounter()
	for e in director.enemies:
		e.hit(999.0, e.position - e.facing)
	director.step(0.05, player)
	expect(director.enemies.is_empty(), "Cleared wave 0 enemies before testing defeat")
	player.health = 0.0
	director.step(15.0, player) # Crosses 12s wave boundary while player is at 0 HP
	expect(director.encounter_state == &"defeat" and director.enemies.is_empty() and director.status_text().contains("R"), "At 0 player HP, encounter stops spawning new waves and reports reset hint")

	# Reset returns to Sandbox
	director.reset_state()
	expect(director.status_text() == "Sandbox" and director.enemies.size() == 1 and director.enemies[0].kind == &"target", "reset_state() cancels encounter and returns status_text() to Sandbox")

	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
