extends SceneTree

const EnemyScript := preload("res://scenes/prototype/enemy.gd")
const EnemiesScript := preload("res://scenes/prototype/enemies.gd")
const PatternEnemyScript := preload("res://scenes/prototype/pattern_enemy.gd")
const PatternVisualScript := preload("res://scenes/prototype/pattern_visual.gd")
const FlowScript := preload("res://scenes/prototype/flow.gd")
const HeatBellowsScript := preload("res://scenes/weapons/heat_bellows.gd")
const NavFixture := preload("res://scenes/navigation/checks/fixture.gd")
const Tuning := preload("res://scenes/prototype/tuning.gd")

var checks := 0
var failures: Array[String] = []
var metrics := {}


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)


func run() -> void:
	# 1. Boss visual distinction, larger chassis/silhouette, weakpoint readability, collision & camera fit.
	var director := EnemiesScript.new()
	root.add_child(director)
	director.cover = preload("res://scenes/prototype/cover.gd").new()
	director.cover.set_rectangles([])

	var regular_loop: CombatPatternEnemy = director.spawn(&"loop", Vector3(-6, 0, -6))
	var regular_pair: CombatPatternEnemy = director.spawn(&"pair", Vector3(0, 0, -6))
	var regular_zigzag: CombatPatternEnemy = director.spawn(&"zigzag", Vector3(6, 0, -6))

	var boss_kinds: Array[StringName] = [&"loop_boss", &"sequence_boss", &"final_boss"]
	var bosses: Array[CombatPatternEnemy] = []
	var seen_body_colors: Array[String] = []
	var seen_accent_colors: Array[String] = []

	for i in range(boss_kinds.size()):
		var b_kind := boss_kinds[i]
		var boss: CombatPatternEnemy = director.spawn(b_kind, Vector3(-6 + i * 6, 0, -8))
		boss.facing = Vector3.BACK
		bosses.append(boss)

		var pv: CombatPatternVisual = boss.pattern_visual
		var reg_pv: CombatPatternVisual = regular_loop.pattern_visual
		expect(pv.boss and not reg_pv.boss, "%s is flagged as boss visual" % String(b_kind))
		expect(pv.chassis_extents.x > reg_pv.chassis_extents.x * 1.5 and pv.chassis_extents.y > reg_pv.chassis_extents.y * 1.5,
			"%s chassis extents (%s) are clearly larger than regular pattern enemy (%s)" % [String(b_kind), str(pv.chassis_extents), str(reg_pv.chassis_extents)])
		expect(absf(pv.feet[1].position.x) > absf(reg_pv.feet[1].position.x) * 1.5,
			"%s foot stance is wider than regular pattern enemy" % String(b_kind))
		expect(not pv.identity_parts.is_empty() and pv.identity_parts[0].get_child_count() >= 3,
			"%s builds distinct identity silhouette parts" % String(b_kind))
		expect(pv.body_color != PatternVisualScript.STONE and boss.base_body_color == pv.body_color,
			"%s uses a distinct non-stone boss palette" % String(b_kind))

		var body_hex := pv.body_color.to_html()
		var accent_hex := pv.accent_color.to_html()
		expect(not seen_body_colors.has(body_hex) and not seen_accent_colors.has(accent_hex),
			"%s has a unique body/accent palette among bosses" % String(b_kind))
		seen_body_colors.append(body_hex)
		seen_accent_colors.append(accent_hex)

		# Weakpoint readability & camera fit
		expect(pv.core != null and (pv.core.material_override as StandardMaterial3D).no_depth_test,
			"%s core weakpoint material stays unoccluded (no_depth_test)" % String(b_kind))
		expect(is_equal_approx(boss.movement_radius(), PatternVisualScript.silhouette_radius(b_kind)),
			"%s movement_radius matches silhouette_radius" % String(b_kind))
		var flow := FlowScript.new()
		var slots := flow.layout(&"line", [b_kind], Vector3.ZERO, director.cover, 1, [])
		expect(slots.size() == 1 and FlowScript.readable_from_player(slots[0]["position"], boss.movement_radius(), Vector3.ZERO),
			"%s full silhouette fits within gameplay camera frustum at combat arrival distance" % String(b_kind))
		expect(not pv.countdown.visible and not boss.feedback_label.visible,
			"%s keeps overhead 3D labels hidden" % String(b_kind))

		# Boss escort recommendation check: smaller minions + ranged, no large pattern monuments
		for hard_mode in [false, true]:
			var escorts := PatternEnemyScript.recommended_boss_escorts(b_kind, hard_mode)
			expect(escorts.size() >= 3 and escorts.has(&"ranged"),
				"%s recommended escort mix includes ranged support (hard=%s)" % [String(b_kind), str(hard_mode)])
			for monument: StringName in [&"loop", &"zigzag", &"pair", &"warden", &"brute"]:
				expect(not escorts.has(monument),
					"%s recommended escort mix avoids large monument/heavy add %s (hard=%s)" % [String(b_kind), String(monument), str(hard_mode)])

	expect(not regular_pair.pattern_visual.boss and not regular_zigzag.pattern_visual.boss,
		"Regular pair and zigzag pattern visuals are non-boss")
	metrics["boss_palettes"] = seen_body_colors
	director.clear()
	director.queue_free()

	# 2. Ranged standoff distance, retreat/approach without constant path recomputation, and fair escape lanes.
	var trial := NavFixture.new()
	root.add_child(trial)
	trial.director.navigation.sync_region()
	for i in range(180):
		await physics_frame
		if trial.ready_maps():
			break
	expect(trial.ready_maps(), "Navigation fixture maps ready for ranged movement checks")

	if trial.ready_maps():
		# 2a. Close-range retreat to useful standoff distance before windup, with bounded path refreshes
		trial.director.clear()
		trial.director.cover.set_rectangles([])
		trial.player.position = Vector3(12, 0, 0)
		trial.player.time_controller.begin_attempt()
		var close_shooter: CombatEnemy = trial.director.spawn(&"ranged", Vector3(12, 0, -2.2))
		var initial_dist := close_shooter.position.distance_to(trial.player.position)
		for step_i in range(70):
			trial.director.step(0.05, trial.player)
			await physics_frame
			if close_shooter.attack_phase == &"windup":
				break
		var windup_dist := close_shooter.position.distance_to(trial.player.position)
		metrics["ranged_retreat_start_dist"] = initial_dist
		metrics["ranged_retreat_windup_dist"] = windup_dist
		metrics["ranged_retreat_refreshes"] = close_shooter.navigation.refreshes
		expect(windup_dist >= EnemyScript.RANGED_MIN_DIST - 0.1 and windup_dist > initial_dist + 1.5,
			"Close ranged unit retreats to useful standoff distance (%.2fm -> %.2fm) before windup" % [initial_dist, windup_dist])
		expect(close_shooter.attack_phase == &"windup" and close_shooter.ranged_warning.visible,
			"Retreated ranged unit enters telegraphed windup once at useful distance")
		expect(close_shooter.navigation.refreshes <= 2,
			"Ranged retreat uses stable standoff intent without constant path recomputation (refreshes=%d)" % close_shooter.navigation.refreshes)

		# 2b. Far-range approach into standoff band without constant path recomputation
		trial.director.clear()
		var far_shooter: CombatEnemy = trial.director.spawn(&"ranged", Vector3(12, 0, -14.0))
		for step_i in range(60):
			trial.director.step(0.05, trial.player)
			await physics_frame
			if far_shooter.attack_phase == &"windup":
				break
		var far_windup_dist := far_shooter.position.distance_to(trial.player.position)
		metrics["ranged_approach_windup_dist"] = far_windup_dist
		metrics["ranged_approach_refreshes"] = far_shooter.navigation.refreshes
		expect(far_windup_dist < 14.0 and far_windup_dist >= EnemyScript.RANGED_MIN_DIST,
			"Far ranged unit approaches to useful distance (%.2fm) and enters windup" % far_windup_dist)
		expect(far_shooter.navigation.refreshes <= 2,
			"Ranged approach avoids constant path recomputation (refreshes=%d)" % far_shooter.navigation.refreshes)

		# 2c. Multiple ranged units spread standoff intents to leave fair escape lanes
		trial.director.clear()
		trial.player.position = Vector3.ZERO
		var r1: CombatEnemy = trial.director.spawn(&"ranged", Vector3(-1.0, 0, -3.0))
		var r2: CombatEnemy = trial.director.spawn(&"ranged", Vector3(0.0, 0, -3.0))
		var r3: CombatEnemy = trial.director.spawn(&"ranged", Vector3(1.0, 0, -3.0))
		var peer_group := [r1, r2, r3]
		var intent1 := r1._ranged_standoff_intent(Vector3.ZERO, r1.position, Vector3.BACK, peer_group)
		var intent2 := r2._ranged_standoff_intent(Vector3.ZERO, r2.position, Vector3.BACK, peer_group)
		var intent3 := r3._ranged_standoff_intent(Vector3.ZERO, r3.position, Vector3.BACK, peer_group)
		expect(intent1.distance_to(intent2) > 1.8 and intent2.distance_to(intent3) > 1.8,
			"Multiple ranged peers spread their standoff targets laterally (>1.8m) to preserve fair escape lanes")

		# 2d. Cover-blocked ranged unit routes instead of firing into wall
		trial.director.clear()
		trial.director.cover.set_rectangles([Rect2(-2.0, -5.0, 4.0, 1.0)])
		var blocked_shooter: CombatEnemy = trial.director.spawn(&"ranged", Vector3(0, 0, -8.0))
		trial.director.step(0.05, trial.player)
		expect(blocked_shooter.attack_phase == &"approach" and trial.director.projectiles.is_empty(),
			"Cover-blocked ranged unit does not lock windup into a wall; it routes first")

	trial.queue_free()

	# 3. Cone knockback & mass resistance hierarchy and reliable orange heating inside cone range.
	var cone_dir := EnemiesScript.new()
	root.add_child(cone_dir)
	cone_dir.cover = preload("res://scenes/prototype/cover.gd").new()
	cone_dir.cover.set_rectangles([])

	var e_blue: CombatEnemy = cone_dir.spawn(&"blue", Vector3(0, 0, -4))
	var e_ranged: CombatEnemy = cone_dir.spawn(&"ranged", Vector3(0, 0, -4))
	var e_swarmer: CombatEnemy = cone_dir.spawn(&"swarmer", Vector3(0, 0, -4))
	var e_brute: CombatEnemy = cone_dir.spawn(&"brute", Vector3(0, 0, -4))
	var e_warden: CombatEnemy = cone_dir.spawn(&"warden", Vector3(0, 0, -4))
	var e_guard: CombatEnemy = cone_dir.spawn(&"front_guard", Vector3(0, 0, -4))
	var e_boss: CombatPatternEnemy = cone_dir.spawn(&"sequence_boss", Vector3(0, 0, -4))

	var b_scale := float(e_blue.mass_resistance()["impulse_scale"])
	var r_scale := float(e_ranged.mass_resistance()["impulse_scale"])
	var s_scale := float(e_swarmer.mass_resistance()["impulse_scale"])
	var br_scale := float(e_brute.mass_resistance()["impulse_scale"])
	var w_scale := float(e_warden.mass_resistance()["impulse_scale"])
	var g_closed_scale := float(e_guard.mass_resistance()["impulse_scale"])
	var boss_scale := float(e_boss.mass_resistance()["impulse_scale"])

	expect(b_scale > r_scale and r_scale > s_scale and s_scale > br_scale and br_scale > w_scale and w_scale > g_closed_scale and g_closed_scale > boss_scale,
		"Mass impulse resistance follows monotonic hierarchy from light blue/ranged/swarmer down to heavy guard/boss")

	e_guard.plate_broken = true
	var g_open_scale := float(e_guard.mass_resistance()["impulse_scale"])
	expect(g_open_scale > g_closed_scale * 2.0,
		"Breaking a guard's heavy plate increases its knockback susceptibility (%.2f -> %.2f)" % [g_closed_scale, g_open_scale])

	e_boss.apply_control(Vector3.BACK, 22.0, 0.85)
	expect(e_boss.stagger_timer < 0.9, "Boss cone stagger remains bounded (<0.9s)")
	var boss_start := e_boss.position
	for i in range(60):
		e_boss.step_enemy(1.0 / 60.0, null)
	expect(e_boss.position.distance_to(boss_start) < 0.4,
		"Boss resists cone knockback displacement (<0.4m)")

	# Real HeatBellows continuous hold on an orange enemy at mid-outer range (3.4m) melts plate without ejecting out of 5m cone
	cone_dir.clear()
	var orange_target: CombatEnemy = cone_dir.spawn(&"orange", Vector3(0, 0, -3.4))
	var gear := WeaponEquipment.new()
	var bellows := HeatBellowsScript.new()
	root.add_child(bellows)
	bellows.bind(gear, cone_dir.cover)
	bellows.press(Vector3.ZERO, Vector3(0, 0, -4.0))
	for tick in range(80):
		bellows.step(1.0 / 60.0, 1.0 / 60.0, Vector3.ZERO, Vector3.ZERO, cone_dir.enemies)
		if is_instance_valid(orange_target) and orange_target.health > 0:
			orange_target.step_enemy(1.0 / 60.0, null)
		if orange_target.plate_broken:
			break
	expect(orange_target.plate_broken and orange_target.health <= 0.0,
		"Continuous HeatBellows hold from 3.4m melts and kills orange enemy without pushing it out of cone range")

	bellows.queue_free()
	cone_dir.clear()
	cone_dir.queue_free()

	await process_frame
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures, "metrics": metrics}))
	quit(0 if failures.is_empty() else 1)
