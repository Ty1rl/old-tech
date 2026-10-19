extends SceneTree

const Enemy = preload("res://scenes/prototype/enemy.gd")
const Tuning = preload("res://scenes/prototype/tuning.gd")
var failures: Array[String] = []
var checks: int = 0
var enemy: Node3D


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func reset() -> void:
	enemy.configure(&"warden", Vector3.ZERO, 71)
	enemy.facing = Vector3.FORWARD


func sweep(tool: StringName, start: Vector3, finish: Vector3, amount: float = 10.0, charge: float = 0.0) -> Dictionary:
	return enemy.receive_attack(tool, amount, start, {"segment_start": start, "segment_end": finish, "radius": 0.03, "charge": charge})


func run() -> void:
	enemy = Enemy.new()
	root.add_child(enemy)
	reset()
	expect(enemy.kind == &"warden" and enemy.health == 240.0, "Warden has its own configured archetype")
	expect(enemy.warden_visual.get_child_count() > 20 and enemy.warden_visual.shield_hinges.size() == 2 and enemy.warden_visual.cable_spans.size() == 3, "Mechanized geometry includes frame, hinges, pistons, cable, core and vents")
	var initial: Dictionary = enemy.capture_state()
	var front: Dictionary = enemy.hit(20.0, Vector3(0.0, 0.0, -2.0))
	expect(front.armored and front.dealt > 0.0 and front.dealt < 20.0, "Closed directional armor reduces front damage without immunity")
	var flank: Dictionary = enemy.hit(20.0, Vector3(-2.0, 0.0, 0.0))
	expect(not flank.armored and is_equal_approx(flank.dealt, 20.0), "Flanking deals full ordinary damage")
	reset()
	var broad_miss := sweep(&"ring", Vector3(-0.3, 0.0, 1.45), Vector3(0.3, 0.0, 1.45))
	expect(not broad_miss.connected and enemy.health == 240.0 and not enemy.cable_cut, "Expanded ring broadphase alone causes no damage or cable cut")
	var body_hit := sweep(&"ring", Vector3(-0.9, 0.0, -2.0), Vector3(-0.9, 0.0, 2.0))
	expect(body_hit.connected and not enemy.cable_cut and body_hit.cue == &"", "Body crossing on opposite side does not falsely cut cable")
	reset()
	var cable: Array[Vector3] = enemy.cable_world_points()
	var cut := sweep(&"ring", cable[1].lerp(cable[2], 0.25), cable[1].lerp(cable[2], 0.75), 20.0)
	expect(cut.connected and enemy.cable_cut and cut.cue == &"cable_cut", "Ring must physically sweep the exposed cyan cable")
	expect(cut.dealt >= 80.0 and not cut.armored and enemy.is_core_exposed(), "Cable sever grants significant damage and permanently disables shield")
	expect(not enemy.warden_visual.cable_spans[1].visible and enemy.warden_visual.core.visible, "Cable cut derives missing cable and revealed yellow core visuals")
	reset()
	sweep(&"ring", Vector3(-0.9, 0.0, -2.0), Vector3(-0.9, 0.0, 2.0), 20.0)
	var before_late_cut: float = enemy.health
	var duplicate_body: Dictionary = enemy.receive_attack(&"ring", 20.0, Vector3(-2.0, 0.0, 0.0), {"segment_start": Vector3(-0.9, 0.0, -2.0), "segment_end": Vector3(-0.9, 0.0, 2.0), "radius": 0.03, "already_hit": true})
	expect(not duplicate_body.connected and enemy.health == before_late_cut and enemy.has_cuttable_part(), "Already-hit ring may continue searching without repeating chassis damage")
	var late_cut: Dictionary = enemy.receive_attack(&"ring", 20.0, cable[1], {"segment_start": cable[1].lerp(cable[2], 0.25), "segment_end": cable[1].lerp(cable[2], 0.75), "radius": 0.03, "already_hit": true})
	expect(late_cut.cue == &"cable_cut" and is_equal_approx(late_cut.dealt, float(Tuning.PARTS.cable_bonus)) and not enemy.has_cuttable_part(), "Later segment of same stroke cuts cable for bonus only after chassis hit")
	var cut_snapshot: Dictionary = enemy.capture_state()
	enemy.step_enemy(9.0, null)
	expect(enemy.cable_cut and enemy.is_core_exposed(), "Cable sever remains permanent across world time")
	var repeat_cut := sweep(&"ring", cable[1].lerp(cable[2], 0.25), cable[1].lerp(cable[2], 0.75))
	expect(not repeat_cut.connected and repeat_cut.cue == &"", "Severed protruding cable cannot repeatedly grant hits or transition cues")
	enemy.restore_state(initial)
	expect(not enemy.cable_cut and not enemy.is_core_exposed() and enemy.warden_visual.cable_spans[1].visible, "Rewind restores intact cable, closed shield, and derived geometry")
	expect(enemy.last_hit_result.get("cue", &"") == &"" and enemy.feedback_label.text == "", "Snapshot restore emits no combat cue or new feedback")

	var warm: Dictionary = enemy.receive_attack(&"cone", 1.0, Vector3(0.0, 0.0, -enemy.radius), {"dt": 0.5})
	expect(warm.connected and not enemy.is_core_exposed() and enemy.shield_heat > 0.0, "Cone builds heat on actual orange shield contact")
	var warm_snapshot: Dictionary = enemy.capture_state()
	enemy.step_enemy(0.0, null)
	expect(is_equal_approx(enemy.shield_heat, 0.5), "Paused world does not cool heat")
	enemy.step_enemy(0.2, null)
	expect(enemy.shield_heat < 0.5 and enemy.shield_heat > 0.0, "Heat cooling uses world seconds")
	enemy.restore_state(warm_snapshot)
	expect(is_equal_approx(enemy.shield_heat, 0.5), "Rewind restores accumulated heat")
	var opened: Dictionary = enemy.receive_attack(&"cone", 1.0, Vector3(0.0, 0.0, -enemy.radius), {"dt": 0.7})
	expect(opened.cue == &"vent" and enemy.is_core_exposed() and is_equal_approx(enemy.shield_open_timer, 4.0), "Sustained cone heat opens shield for four world seconds")
	var open_snapshot: Dictionary = enemy.capture_state()
	var low := sweep(&"beam", Vector3(0.0, 0.0, -3.0), Vector3(0.0, 0.0, -1.0), 10.0, 0.4)
	expect(low.connected and low.cue == &"" and not enemy.core_broken and is_equal_approx(low.dealt, 10.0), "Uncharged flash cannot break exposed core")
	var aim_miss := sweep(&"beam", Vector3(-0.9, 0.0, -3.0), Vector3(-0.9, 0.0, 0.0), 10.0, 1.0)
	expect(aim_miss.connected and aim_miss.cue == &"" and not enemy.core_broken and is_equal_approx(aim_miss.dealt, 10.0), "Charged flash hitting chassis away from core grants no bonus")
	var core_hit := sweep(&"beam", Vector3(0.0, 0.0, -3.0), Vector3(0.0, 0.0, -1.0), 10.0, 1.0)
	expect(core_hit.cue == &"core_break" and enemy.core_broken and core_hit.dealt >= 90.0, "Charged aimed ray extends through body and breaks exposed yellow core")
	var repeat_core := sweep(&"beam", Vector3(0.0, 0.0, -3.0), Vector3(0.0, 0.0, -1.0), 10.0, 1.0)
	expect(repeat_core.cue == &"" and is_equal_approx(repeat_core.dealt, 10.0), "Broken core bonus and transition cue occur once")
	enemy.restore_state(open_snapshot)
	expect(not enemy.core_broken and enemy.is_core_exposed() and enemy.last_hit_result.get("cue", &"") == &"", "Rewind restores unbroken core and open timer silently")
	enemy.step_enemy(3.9, null)
	expect(enemy.is_core_exposed(), "Vented shield stays open until world-time window expires")
	enemy.step_enemy(0.11, null)
	expect(not enemy.is_core_exposed() and not enemy.warden_visual.core.visible, "Shield recloses and conceals core when timer expires")
	var closed_core := sweep(&"beam", Vector3(0.0, 0.0, -3.0), Vector3(0.0, 0.0, -1.0), 10.0, 1.0)
	expect(closed_core.armored and not enemy.core_broken and closed_core.cue == &"", "Charged aimed flash cannot break closed core")
	enemy.restore_state(cut_snapshot)
	expect(enemy.cable_cut and enemy.is_core_exposed() and not enemy.core_broken, "Snapshot restores cable route independently of heat route")
	reset()
	var missing_cable_context: Dictionary = enemy.receive_attack(&"ring", 10.0, Vector3(0.0, 0.0, -enemy.radius))
	expect(missing_cable_context.connected and not enemy.cable_cut, "Legacy contact-only ring hit cannot invent cable crossing")
	for tool: StringName in [&"ring", &"beam", &"cone"]:
		reset()
		for i in range(30):
			enemy.receive_attack(tool, 20.0, Vector3(-enemy.radius, 0.0, 0.0))
		expect(enemy.health <= 0.0 and not enemy.cable_cut and not enemy.core_broken, "Every tool can kill through base damage and flanking: " + String(tool))
	reset()
	expect(not enemy.cable_cut and enemy.shield_heat == 0.0 and enemy.shield_open_timer == 0.0 and not enemy.core_broken, "Configure resets all mechanism state")
	enemy.free()
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
