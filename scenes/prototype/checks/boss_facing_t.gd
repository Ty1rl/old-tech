extends SceneTree
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func run() -> void:
	create_timer(25).timeout.connect(func(): quit(1))
	var arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	for i in 4: await process_frame
	arena.set_physics_process(false)
	arena.director.clear()
	arena.player.position = Vector3(0, 0, 6)
	for kind: StringName in [&"sequence_boss", &"loop_boss", &"final_boss"]:
		var boss: CombatPatternEnemy = arena.director.spawn(kind, Vector3.ZERO)
		boss.facing = Vector3.FORWARD
		boss.attack_phase = &"recover"
		boss.attack_timer = 10.0
		for i in 120: boss.step_enemy(1.0 / 60.0, arena.player)
		expect(boss.facing.dot(Vector3.BACK) > .98, "%s turns toward a player behind it during recovery" % kind)
		expect(boss.position.is_zero_approx(), "%s recovery stays stationary" % kind)
		boss.facing = Vector3.FORWARD
		boss.ranged_aim = Vector3.FORWARD
		boss.attack_phase = &"windup"
		boss.attack_timer = 2.0
		boss.step_enemy(.5, arena.player)
		expect(boss.facing.is_equal_approx(Vector3.FORWARD) and boss.ranged_aim.is_equal_approx(Vector3.FORWARD), "%s warning aim remains fixed" % kind)
		boss.attack_phase = &"commit"
		boss.attack_timer = 2.0
		boss.step_enemy(.5, arena.player)
		expect(boss.facing.is_equal_approx(Vector3.FORWARD), "%s committed attack stays fixed" % kind)
		boss.attack_phase = &"recover"
		boss.attack_timer = 10.0
		boss.step_enemy(0.0, arena.player)
		expect(boss.facing.is_equal_approx(Vector3.FORWARD), "%s frozen world does not rotate" % kind)
		boss.stagger_timer = 1.0
		boss.step_enemy(.1, arena.player)
		expect(boss.facing.is_equal_approx(Vector3.FORWARD), "%s does not turn while staggered" % kind)
		arena.director.clear()
	var regular: CombatPatternEnemy = arena.director.spawn(&"loop", Vector3.ZERO)
	regular.facing = Vector3.FORWARD
	regular.attack_phase = &"recover"
	regular.attack_timer = 10.0
	regular.step_enemy(1.0, arena.player)
	expect(regular.facing.is_equal_approx(Vector3.FORWARD), "Regular pattern enemies retain their stable recovery pose")
	arena.director.clear()
	var minion: CombatEnemy = arena.director.spawn(&"yellow", Vector3.ZERO)
	minion.move_speed = 0.0
	arena.time_controller.begin_attempt()
	var before: float = arena.time_controller.meter
	# A normal-speed run straight through melee reach should carry some risk.
	for i in 25:
		arena.player.position = Vector3(0, 0, 1.5 - float(i) * .1)
		minion.step_enemy(1.0 / 60.0, arena.player)
	expect(arena.time_controller.meter < before, "Running directly past a minion inside melee reach can take damage")
	minion.attack_phase = &"approach"
	arena.time_controller.begin_attempt()
	arena.player.position = Vector3(0, 0, 1.4)
	minion.step_enemy(.01, arena.player)
	expect(is_equal_approx(arena.time_controller.meter, before), "Melee warning gives time to react before damage")
	for i in 30:
		arena.player.position.z += .1
		minion.step_enemy(1.0 / 60.0, arena.player)
	expect(is_equal_approx(arena.time_controller.meter, before), "Moving away during the warning still avoids the strike")
	var neutral_damage: float = minion.contact_damage
	var damage_by_mode := {}
	var warning_by_mode := {}
	var alignment_by_mode := {}
	for mode: StringName in [&"easy", &"hard"]:
		arena.director.clear()
		arena.director.combat_difficulty = CampaignDifficulty.load_for(mode)
		minion = arena.director.spawn(&"yellow", Vector3.ZERO)
		minion.move_speed = 0.0
		arena.player.position = Vector3(0, 0, 1.0)
		arena.time_controller.begin_attempt()
		minion.step_enemy(.01, arena.player)
		warning_by_mode[mode] = minion.attack_timer
		minion.step_enemy(.4, arena.player)
		damage_by_mode[mode] = before - arena.time_controller.meter
		var saved_damage: float = minion.contact_damage
		arena.director.restore_state(arena.director.capture_state())
		minion = arena.director.enemies[0]
		expect(is_equal_approx(minion.contact_damage, saved_damage), "%s rewind preserves difficulty damage without applying the multiplier twice" % mode)
		arena.director.clear()
		var shooter: CombatEnemy = arena.director.spawn(&"ranged", Vector3.ZERO)
		arena.player.position = Vector3(0, 0, 6)
		shooter.facing = Vector3.FORWARD
		shooter.attack_phase = &"recover"
		shooter.attack_timer = 10.0
		shooter.step_enemy(.5, arena.player)
		alignment_by_mode[mode] = shooter.facing.dot(Vector3.BACK)
		shooter._lock_warning_aim()
		var aim_before := shooter.ranged_aim
		shooter.attack_phase = &"windup"
		shooter.attack_timer = 2.0
		arena.player.position = Vector3(6, 0, 0)
		shooter.step_enemy(.2, arena.player)
		expect(shooter.ranged_aim.is_equal_approx(aim_before), "%s ranged warning stays fixed after aiming" % mode)
	expect(damage_by_mode[&"hard"] > damage_by_mode[&"easy"] and damage_by_mode[&"easy"] > neutral_damage, "Both modes hit harder, with stronger Hard damage")
	expect(warning_by_mode[&"hard"] < warning_by_mode[&"easy"], "Hard melee strikes commit sooner")
	expect(alignment_by_mode[&"hard"] > alignment_by_mode[&"easy"], "Hard ranged enemies reacquire the player faster between shots")
	root.get_node("AudioManager").stop_dialogue()
	root.get_node("AudioManager").set_music_context(&"intro")
	call_group(&"world_audio", &"reset_state")
	arena.queue_free()
	for i in 4: await process_frame
	await create_timer(.2).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
