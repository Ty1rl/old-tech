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
	var mixed_kinds: Array = director.enemies.map(func(e): return e.kind)
	expect(mixed_kinds.count(&"swarmer") == 2 and mixed_kinds.count(&"skirmisher") == 1 and mixed_kinds.count(&"warden") == 1,
		"Mixed group pairs two swarmers with a skirmisher and a mechanized guard")
	director.reset_state()
	expect(director.enemies.size() == 1 and director.enemies[0].kind == &"target", "reset_state() clears mixed group and restores single target")

	# 9. Round C: Crowd control (shove knockback + stagger suppression + recovery) on swarmer
	director.clear()
	player.reset_state()
	player.position = Vector3.ZERO
	var shoved_swarmer = director.spawn(&"swarmer", Vector3(0.0, 0.0, -1.0))
	shoved_swarmer.apply_control(Vector3(0.0, 0.0, -1.0), float(Tuning.CONTROL.pulse_impulse), float(Tuning.CONTROL.stagger))
	expect(shoved_swarmer.is_staggered() and is_equal_approx(shoved_swarmer.stagger_timer, float(Tuning.CONTROL.stagger)), "apply_control sets stagger_timer on swarmer")
	director.step(0.2, player)
	expect(shoved_swarmer.position.z < -2.2, "Strong shove visibly displaces swarmer away from player")
	expect(is_equal_approx(player.health, 100.0), "Staggered enemy suppresses contact attack even when starting in contact range")

	# Place staggered swarmer right on top of player while still staggered: still no contact damage
	shoved_swarmer.position = Vector3(0.0, 0.0, -0.5)
	shoved_swarmer.knockback_vel = Vector3.ZERO
	director.step(0.2, player)
	expect(shoved_swarmer.is_staggered() and is_equal_approx(player.health, 100.0), "Staggered swarmer does not deal contact damage while stagger_timer > 0")

	# Advance past remaining stagger so swarmer recovers and resumes AI + contact attack
	director.step(0.5, player)
	expect(not shoved_swarmer.is_staggered() and is_equal_approx(player.health, 95.0), "Recovered swarmer resumes normal AI and contact attack after stagger expires")

	# 10. Round D: Distinct Brute displacement vs stun resistance + Stationary Target push/stun
	director.clear()
	player.reset_state()
	player.position = Vector3.ZERO
	var ctrl_swarmer = director.spawn(&"swarmer", Vector3(-3.0, 0.0, -4.0))
	var ctrl_brute = director.spawn(&"brute", Vector3(0.0, 0.0, -4.0))
	var ctrl_target = director.spawn(&"target", Vector3(3.0, 0.0, -4.0))
	var shove_dir := Vector3(0.0, 0.0, -1.0)
	var test_impulse := 22.0
	var test_stagger := 0.85
	ctrl_swarmer.apply_control(shove_dir, test_impulse, test_stagger)
	ctrl_brute.apply_control(shove_dir, test_impulse, test_stagger)
	ctrl_target.apply_control(shove_dir, test_impulse, test_stagger)

	var impulse_resist := float(Tuning.CONTROL.get("brute_resistance", 0.4))
	var stagger_resist := float(Tuning.CONTROL.get("brute_stagger_resistance", 0.8))
	expect(is_equal_approx(ctrl_brute.stagger_timer, test_stagger * stagger_resist) and ctrl_brute.stagger_timer > test_stagger * impulse_resist,
		"Brute retains meaningful stun (0.8x stagger) distinct from displacement resistance")
	expect(is_equal_approx(ctrl_brute.knockback_vel.length(), ctrl_swarmer.knockback_vel.length() * impulse_resist),
		"Brute knockback velocity scales by brute_resistance")
	expect(ctrl_target.is_staggered() and is_equal_approx(ctrl_target.stagger_timer, test_stagger) and is_equal_approx(ctrl_target.knockback_vel.length(), test_impulse),
		"Stationary target has no anchored immunity: it can be shoved and stunned")

	director.step(0.15, player)
	var swarmer_disp := absf(ctrl_swarmer.position.z - (-4.0))
	var brute_disp := absf(ctrl_brute.position.z - (-4.0))
	var target_disp := absf(ctrl_target.position.z - (-4.0))
	expect(is_equal_approx(brute_disp, swarmer_disp * impulse_resist) and brute_disp < swarmer_disp,
		"Brute travels less than swarmer over world_delta")
	expect(is_equal_approx(target_disp, swarmer_disp) and target_disp > 1.0,
		"Shoved stationary target displaces over world_delta just like unarmored enemies")

	# After knockback and stagger settle, target stays at its new shoved position (no approach AI)
	for i in range(25):
		director.step(0.1, player)
	var settled_target_z: float = ctrl_target.position.z
	director.step(0.5, player)
	expect(not ctrl_target.is_staggered() and is_equal_approx(ctrl_target.position.z, settled_target_z) and settled_target_z < -5.5,
		"Stationary target stays at its shoved position after recovery with no approach AI")

	# 11. Round C/D: Frame-delta and time-slow consistency for knockback + stagger recovery
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

	# Slow-time scaling on control integration (5 steps of 0.1 * SLOW.scale == 1 step of 0.5 * SLOW.scale)
	director.clear()
	var slow_a = director.spawn(&"brute", Vector3(2.0, 0.0, -3.0))
	slow_a.apply_control(Vector3(0.0, 0.0, -1.0), 22.0, 0.85)
	for i in range(5):
		director.step(0.1 * float(Tuning.SLOW.scale), player)
	var slow_a_pos: Vector3 = slow_a.position
	var slow_a_stagger: float = slow_a.stagger_timer

	director.clear()
	var slow_b = director.spawn(&"brute", Vector3(2.0, 0.0, -3.0))
	slow_b.apply_control(Vector3(0.0, 0.0, -1.0), 22.0, 0.85)
	director.step(0.5 * float(Tuning.SLOW.scale), player)
	expect(slow_a_pos.distance_to(slow_b.position) < 0.001 and is_equal_approx(slow_a_stagger, slow_b.stagger_timer),
		"World-time control integration scales consistently under time slow")

	# 12. Round C: Cover-safe knockback (no tunneling or overlapping Cover.RECTANGLES)
	director.clear()
	# Left cover rectangle is Rect2(-6, -6, 2, 3) -> x in [-6, -4], z in [-6, -3]
	var kb_cover_enemy = director.spawn(&"swarmer", Vector3(-5.0, 0.0, -2.2))
	kb_cover_enemy.apply_control(Vector3(0.0, 0.0, -1.0), float(Tuning.CONTROL.pulse_impulse), float(Tuning.CONTROL.stagger))
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

	var first_wave: Array = director.enemies.map(func(e): return e.kind)
	expect(first_wave == [&"swarmer", &"swarmer"], "Encounter opens with two swarmers instead of every archetype at once")
	var opening: Dictionary = director.capture_state()
	director.step(12.0, player)
	var second_wave: Array = director.enemies.map(func(e): return e.kind)
	expect(second_wave.count(&"skirmisher") == 1 and not second_wave.has(&"warden"), "Skirmisher arrives before the first guard")
	director.step(12.0, player)
	var third_wave: Array = director.enemies.map(func(e): return e.kind)
	expect(third_wave.count(&"warden") == 1 and third_wave.size() <= 6, "First guard joins after two tool introductions, within live cap")
	director.restore_state(opening)
	player.reset_state()

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

	# 15. Round D: Stable rewind_id / combat_id(), snapshot kill/revive, remove later spawns, and deterministic next ID
	director.reset_state()
	expect(director.enemies.size() == 1 and director.enemies[0].combat_id() == 1,
		"reset_state() resets _spawn_counter and assigns rewind_id=1 to initial target")
	director.clear()
	player.reset_state()
	player.position = Vector3.ZERO
	var e1 = director.spawn(&"swarmer", Vector3(-3.0, 0.0, -3.5))
	var e2 = director.spawn(&"brute", Vector3(0.0, 0.0, -6.0))
	var e3 = director.spawn(&"skirmisher", Vector3(3.5, 0.0, -5.0))
	expect(e1.combat_id() == 2 and e2.combat_id() == 3 and e3.combat_id() == 4 and e1.rewind_id == 2,
		"director.spawn assigns sequential positive rewind_id returned by combat_id() without reusing cleared IDs")

	# Put e1, e2, e3 into rich mid-combat states (contact timer, knockback/stagger, damaged HP, skirmisher phase/timer/sign)
	e1.contact_cooldown = 0.65
	e1.apply_control(Vector3(-1.0, 0.0, -1.0), 14.0, 0.45)
	e2.facing = Vector3(1.0, 0.0, 0.0)
	e2.hit(50.0, Vector3(-1.0, 0.0, -6.0)) # Rear hit -> 130 HP
	e3.skirmish_phase = &"commit"
	e3.skirmish_timer = 1.75
	e3.skirmish_strafe_sign = -1.0
	director.step(0.1, player)

	var e1_snap_pos: Vector3 = e1.position
	var e1_snap_cd: float = e1.contact_cooldown
	var e1_snap_kb: Vector3 = e1.knockback_vel
	var e1_snap_stagger: float = e1.stagger_timer
	var e2_snap_hp: float = e2.health
	var e2_snap_facing: Vector3 = e2.facing
	var e3_snap_phase: StringName = e3.skirmish_phase
	var e3_snap_timer: float = e3.skirmish_timer
	var e3_snap_sign: float = e3.skirmish_strafe_sign

	var snap_mid: Dictionary = director.capture_state()

	# Advance timeline: kill e1 (pruned), damage e2 further, and spawn later enemies e4 and e5
	e1.hit(999.0, e1.position - e1.facing)
	e2.hit(40.0, e2.position - e2.facing)
	director.step(0.2, player)
	var e4 = director.spawn(&"swarmer", Vector3(-6.0, 0.0, -8.0))
	var e5 = director.spawn(&"target", Vector3(6.0, 0.0, -8.0))
	expect(director.enemies.size() == 4 and e4.combat_id() == 5 and e5.combat_id() == 6,
		"Timeline advanced: e1 dead/pruned and e4 (ID 5), e5 (ID 6) spawned")

	# Restore snapshot: e1 must revive with ID 2, e2/e3 reconcile in place, e4/e5 removed, next spawn gets ID 5
	var e2_node_before_restore: Node3D = e2
	director.restore_state(snap_mid)
	expect(director.enemies.size() == 3, "restore_state restores exact 3-enemy roster")
	expect(director.enemies[0].combat_id() == 2 and director.enemies[1].combat_id() == 3 and director.enemies[2].combat_id() == 4,
		"Restored roster preserves stable combat_id() order [2, 3, 4]")
	var rev_e1 = director.enemies[0]
	var rev_e2 = director.enemies[1]
	var rev_e3 = director.enemies[2]
	expect(rev_e2 == e2_node_before_restore, "Still-live enemy (ID 3) reconciles in place without node recreation")
	expect(rev_e1.position.distance_to(e1_snap_pos) < 0.001 and is_equal_approx(rev_e1.contact_cooldown, e1_snap_cd) and rev_e1.knockback_vel.distance_to(e1_snap_kb) < 0.001 and is_equal_approx(rev_e1.stagger_timer, e1_snap_stagger),
		"Revived enemy (ID 2) restores position, contact_cooldown, knockback_vel, and stagger_timer")
	expect(is_equal_approx(rev_e2.health, e2_snap_hp) and rev_e2.facing.distance_to(e2_snap_facing) < 0.001,
		"Reconciled brute (ID 3) restores health and facing")
	expect(rev_e3.skirmish_phase == e3_snap_phase and is_equal_approx(rev_e3.skirmish_timer, e3_snap_timer) and is_equal_approx(rev_e3.skirmish_strafe_sign, e3_snap_sign),
		"Reconciled skirmisher (ID 4) restores skirmish_phase, skirmish_timer, and skirmish_strafe_sign")

	var next_after_restore = director.spawn(&"swarmer", Vector3(0.0, 0.0, -9.0))
	expect(next_after_restore != null and next_after_restore.combat_id() == 5,
		"Restoring spawn_counter makes the next spawned enemy deterministically receive ID 5")

	# 16. Round D: Encounter state / elapsed / wave index round-trip without replaying waves
	director.clear()
	player.reset_state()
	director.start_encounter()
	director.step(15.0, player) # Crosses wave 1 at 12.0s; wave_index is now 2, elapsed is 15.0s
	expect(director.encounter_wave_index == 2 and is_equal_approx(director.encounter_elapsed, 15.0),
		"Encounter at 15.0s has spawned waves 0 and 1 (wave_index == 2)")
	# Kill one enemy at 15.0s so live count is 5, then capture snapshot
	director.enemies[0].hit(999.0, director.enemies[0].position - director.enemies[0].facing)
	director.step(0.05, player)
	var count_at_15s: int = director.enemies.size()
	var snap_enc: Dictionary = director.capture_state()

	# Advance to 26.0s (crosses wave 2 at 24.0s) and kill everything
	director.step(11.0, player)
	expect(director.encounter_wave_index == 3, "Stepping to 26.05s triggers wave 2 (wave_index == 3)")
	for e in director.enemies:
		e.hit(999.0, e.position - e.facing)
	director.step(0.05, player)
	expect(director.enemies.is_empty(), "All enemies cleared at 26.1s before restoring 15.05s snapshot")

	# Restore 15.05s encounter snapshot
	director.restore_state(snap_enc)
	expect(director.encounter_active and director.encounter_state == &"running" and director.encounter_wave_index == 2 and is_equal_approx(director.encounter_elapsed, 15.05),
		"restore_state restores encounter_active, encounter_state, encounter_wave_index, and encounter_elapsed")
	expect(director.enemies.size() == count_at_15s,
		"restore_state revives the exact 15.05s live roster without replaying wave 0 or wave 1")

	# Step 8.0s (to 23.05s < 24.0s): no new wave yet
	director.step(8.0, player)
	expect(director.encounter_wave_index == 2, "Stepping to 23.05s does not prematurely trigger wave 2")
	# Step 1.5s (to 24.55s >= 24.0s): wave 2 triggers on schedule
	director.step(1.5, player)
	expect(director.encounter_wave_index == 3, "Wave 2 triggers on schedule at 24.0s after restore")

	# 17. Round D: 32-enemy live cap on director.spawn and compact value-only snapshot serialization
	director.clear()
	var counter_before_cap: int = director._spawn_counter
	var all_spawned_ok := true
	for i in range(32):
		var col := float(i % 8) * 2.2 - 7.7
		var row := float(i / 8) * 2.2 - 12.0
		var spawned = director.spawn(&"swarmer", Vector3(col, 0.0, row))
		if spawned == null or spawned.combat_id() != counter_before_cap + i + 1:
			all_spawned_ok = false
	expect(all_spawned_ok and director.enemies.size() == 32,
		"director.spawn allows up to 32 live enemies with sequential IDs")

	var overflow_spawn = director.spawn(&"swarmer", Vector3(0.0, 0.0, -10.0))
	expect(overflow_spawn == null and director.enemies.size() == 32 and director._spawn_counter == counter_before_cap + 32,
		"33rd live spawn returns null, caps live enemies at 32, and does not advance _spawn_counter")

	var full_snap: Dictionary = director.capture_state()
	var encoded: PackedByteArray = var_to_bytes(full_snap)
	expect(encoded.size() > 0 and encoded.size() < 16384,
		"32-enemy snapshot serializes cleanly via var_to_bytes in under 16 KiB (no object references)")
	var decoded: Dictionary = bytes_to_var(encoded)
	director.clear()
	director.restore_state(decoded)
	expect(director.enemies.size() == 32 and director.enemies[31].combat_id() == counter_before_cap + 32,
		"32-enemy snapshot round-trips through var_to_bytes / bytes_to_var")

	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
