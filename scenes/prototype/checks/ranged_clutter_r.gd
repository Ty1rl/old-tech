extends SceneTree

const EnemyScript := preload("res://scenes/prototype/enemy.gd")
const EnemiesScript := preload("res://scenes/prototype/enemies.gd")
const PatternEnemyScript := preload("res://scenes/prototype/pattern_enemy.gd")
const FocusedFlashScript := preload("res://scenes/weapons/focused_flash.gd")
const Rooms := preload("res://scenes/prototype/rooms.gd")
const Tuning := preload("res://scenes/prototype/tuning.gd")

var checks := 0
var failures: Array[String] = []
var metrics := {}


class ProbePlayer:
	extends Node3D
	var can_act := true
	var health := 100.0
	var max_health := 100.0
	var last_damage := 0.0

	func take_damage(amount: float) -> void:
		last_damage = amount
		health = maxf(0.0, health - amount)


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)


func run() -> void:
	# 1. Ordinary unprotected ranged enemy dies to one quick yellow hit in both Easy and Hard.
	for preset: StringName in [&"easy", &"hard"]:
		var diff: CampaignDifficulty = CampaignDifficulty.load_for(preset)
		expect(diff != null and diff.id == preset, "difficulty spec loads for %s" % String(preset))
		var room_defs: Array[Dictionary] = Rooms.definitions(diff)
		expect(not room_defs.is_empty(), "%s room definitions load" % String(preset))

		# Real FocusedFlash quick uncharged yellow release (charge = 0.0)
		var director := EnemiesScript.new()
		root.add_child(director)
		var ranged_enemy: Node3D = director.spawn(&"ranged", Vector3(0.0, 0.0, -5.0))
		ranged_enemy.facing = Vector3.BACK
		var ranged_start_hp: float = ranged_enemy.health
		metrics["ranged_start_hp_%s" % String(preset)] = ranged_start_hp
		expect(ranged_start_hp <= float(Tuning.BEAM.min_damage) + 0.001, "%s: ordinary ranged health (%.1f) fits within one quick yellow shot (%.1f)" % [String(preset), ranged_start_hp, float(Tuning.BEAM.min_damage)])

		var gear := WeaponEquipment.new()
		var weapon := FocusedFlashScript.new()
		root.add_child(weapon)
		weapon.bind(gear, null)
		weapon.press()
		weapon.release(Vector3.ZERO, Vector3(0.0, 0.0, -5.0), Vector3.ZERO)
		expect(weapon.pulses.size() == 1 and is_equal_approx(float(weapon.pulses[0].get("charge", -1.0)), 0.0), "%s: quick yellow release has 0.0 charge" % String(preset))
		weapon.step(0.0, 0.35, [ranged_enemy], Vector3.ZERO)
		expect(ranged_enemy.health <= 0.0, "%s: ordinary unprotected ranged enemy dies to one quick yellow FocusedFlash hit" % String(preset))
		weapon.queue_free()
		director.queue_free()

		# Direct receive_attack quick yellow probe (charge = 0.0)
		var probe_ranged := EnemyScript.new()
		root.add_child(probe_ranged)
		probe_ranged.configure(&"ranged", Vector3(0.0, 0.0, -5.0), 1)
		probe_ranged.facing = Vector3.BACK
		var probe_res := probe_ranged.receive_attack(&"beam", 1.0, probe_ranged.position, {
			"charge": 0.0,
			"segment_start": Vector3.ZERO,
			"segment_end": Vector3(0.0, 0.0, -10.0),
			"radius": float(Tuning.BEAM.radius),
		})
		expect(bool(probe_res.get("killed", false)) and probe_ranged.health <= 0.0, "%s: ordinary ranged dies to one quick beam receive_attack probe" % String(preset))
		probe_ranged.queue_free()

	# 2. Protected variants and pattern enemies/bosses retain defense rules and charged core finishes.
	var protected_variants: Array[StringName] = [&"blue", &"orange", &"side_guard", &"front_guard", &"warden", &"brute"]
	for kind: StringName in protected_variants:
		var enemy := EnemyScript.new()
		root.add_child(enemy)
		enemy.configure(kind, Vector3(0.0, 0.0, -4.0), 10)
		enemy.facing = Vector3.BACK
		var quick_res := enemy.receive_attack(&"beam", float(Tuning.BEAM.min_damage), enemy.position + Vector3(0.0, 0.0, 0.75), {
			"charge": 0.0,
			"segment_start": Vector3.ZERO,
			"segment_end": Vector3(0.0, 0.0, -8.0),
			"radius": float(Tuning.BEAM.radius),
		})
		expect(not bool(quick_res.get("killed", false)) and enemy.health > 0.0, "%s retains defense against one quick yellow hit" % String(kind))
		enemy.queue_free()

	# Exposed warden still requires a charged yellow shot (uncharged beam does not break core).
	var warden := EnemyScript.new()
	root.add_child(warden)
	warden.configure(&"warden", Vector3.ZERO, 20)
	warden.facing = Vector3.BACK
	var points := warden.cable_world_points()
	var cut_mid := (points[1] + points[2]) * 0.5
	warden.receive_attack(&"ring", 20.0, cut_mid, {
		"segment_start": cut_mid + Vector3(0.0, 0.0, 1.0),
		"segment_end": cut_mid + Vector3(0.0, 0.0, -1.0),
		"radius": 0.35,
	})
	expect(warden.is_core_exposed(), "warden core exposed after cable cut")
	var uncharged_warden := warden.receive_attack(&"beam", float(Tuning.BEAM.min_damage), warden.core_world_position(), {
		"charge": 0.1,
		"segment_start": Vector3(0.0, 0.0, 3.0),
		"segment_end": Vector3(0.0, 0.0, -3.0),
		"radius": 0.25,
	})
	expect(uncharged_warden.get("cue", &"") != &"core_break" and not warden.core_broken, "exposed warden does not core-break from uncharged yellow hit")
	var charged_warden := warden.receive_attack(&"beam", float(Tuning.BEAM.max_damage), warden.core_world_position(), {
		"charge": 1.0,
		"segment_start": Vector3(0.0, 0.0, 3.0),
		"segment_end": Vector3(0.0, 0.0, -3.0),
		"radius": 0.25,
	})
	expect(charged_warden.get("cue", &"") == &"core_break" and warden.core_broken, "exposed warden core-breaks from charged yellow hit")
	warden.queue_free()

	# Pattern enemies and bosses retain closed defenses and charged core finishes.
	for pattern_kind: StringName in [&"pair", &"loop", &"zigzag", &"loop_boss", &"sequence_boss", &"final_boss"]:
		var pat := PatternEnemyScript.new()
		root.add_child(pat)
		pat.configure(pattern_kind, Vector3(0.0, 0.0, -4.0), 30)
		pat.facing = Vector3.BACK
		var closed_quick := pat.receive_attack(&"beam", float(Tuning.BEAM.min_damage), pat.position, {
			"charge": 0.0,
			"segment_start": Vector3.ZERO,
			"segment_end": Vector3(0.0, 0.0, -8.0),
			"radius": float(Tuning.BEAM.radius),
		})
		expect(not bool(closed_quick.get("killed", false)) and pat.health > 0.0, "pattern %s retains closed defense against quick yellow hit" % String(pattern_kind))
		pat.queue_free()

	# 3. Floating overhead action text is absent on enemy heads while colored part visuals stay readable.
	var forbidden_captions := [
		"Click yellow",
		"Charge yellow",
		"Heat orange",
		"Cut blue",
		"Cut blue / Heat orange",
		"MOVE ASIDE",
	]
	for kind: StringName in [&"ranged", &"yellow", &"blue", &"orange", &"side_guard", &"front_guard", &"warden", &"swarmer", &"skirmisher", &"brute"]:
		var enemy := EnemyScript.new()
		root.add_child(enemy)
		enemy.configure(kind, Vector3(0.0, 0.0, -6.0), 40)
		enemy.facing = Vector3.BACK
		enemy.set_instruction_visible(true)
		if is_instance_valid(enemy.part_visual):
			enemy.part_visual.set_instruction_visible(true)
			expect(enemy.part_visual.instruction.text == "" and not enemy.part_visual.instruction.visible, "%s creature_visual instruction text is blank and hidden" % String(kind))
		expect(enemy.feedback_label.text == "" and not enemy.feedback_label.visible, "%s feedback_label is blank and hidden on spawn" % String(kind))

		var player := ProbePlayer.new()
		root.add_child(player)
		player.position = Vector3.ZERO
		enemy.step_enemy(0.1, player)
		for phrase: String in forbidden_captions:
			expect(not enemy.feedback_label.text.contains(phrase), "%s feedback_label does not show '%s'" % [String(kind), phrase])
			if is_instance_valid(enemy.part_visual):
				expect(not enemy.part_visual.instruction.text.contains(phrase), "%s creature_visual instruction does not show '%s'" % [String(kind), phrase])

		if kind == &"ranged":
			expect(enemy.attack_phase == &"windup" and is_instance_valid(enemy.ranged_warning) and enemy.ranged_warning.visible and is_instance_valid(enemy.ranged_lens) and enemy.ranged_lens.visible, "ranged enemy keeps visible warning lane and lens without floating text")
		elif kind == &"blue":
			expect(enemy.part_visual.cable.visible and enemy.part_visual.cable_marker.visible, "blue enemy keeps colored cable part visual without floating text")
		elif kind == &"orange":
			expect(enemy.part_visual.plate.visible, "orange enemy keeps colored plate part visual without floating text")
		elif kind == &"front_guard":
			expect(enemy.part_visual.plate.visible and enemy.part_visual.shield_rim.visible, "front_guard enemy keeps colored plate and shield_rim visual without floating text")
		elif kind == &"yellow":
			expect(enemy.part_visual.core.visible and enemy.part_visual.core_marker.visible, "yellow enemy keeps colored core part visual without floating text")

		player.queue_free()
		enemy.queue_free()

	await process_frame
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures, "metrics": metrics}))
	quit(0 if failures.is_empty() else 1)
