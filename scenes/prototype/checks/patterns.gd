extends SceneTree
const PatternEnemy = preload("res://scenes/prototype/pattern_enemy.gd")
const Enemy = preload("res://scenes/prototype/enemy.gd")
var checks := 0
var failures: Array[String] = []
var enemy: Node3D

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)
func reset(mode: StringName) -> void:
	enemy.configure(mode, Vector3.ZERO, 53)
	enemy.position = Vector3.ZERO
	enemy.facing = Vector3.FORWARD
func segment(tool: StringName, a: Vector3, b: Vector3, extra: Dictionary = {}, amount: float = 36) -> Dictionary:
	var context := {"segment_start": a, "segment_end": b, "radius": 0.01}
	context.merge(extra, true)
	return enemy.receive_attack(tool, amount, a, context)
func cut(index: int, already: bool = true) -> Dictionary:
	var points: Array[Vector3] = enemy.cable_world_points()
	return segment(&"ring", points[index * 2], points[index * 2 + 1], {"already_hit": already})
func shot_at(point: Vector3, charge: float = 0) -> Dictionary:
	return segment(&"beam", point + Vector3(0, 0, -0.12), point + Vector3(0, 0, 0.12), {"charge": charge}, 30)
func full_cut() -> void:
	var count: int = enemy.cable_world_points().size() / 2
	for i in range(count): cut(i, i > 0)
func run() -> void:
	enemy = PatternEnemy.new()
	root.add_child(enemy)
	for mode: StringName in [&"loop", &"zigzag", &"pair", &"final_boss"]:
		reset(mode)
		expect(PatternEnemy.handles(mode) and enemy.kind == mode, "Factory accepts " + String(mode))
		expect(enemy.lesson_state().has_all(["pattern", "progress", "total", "open", "complete", "phase"]), "Teaching schema: " + String(mode))
	for mode: StringName in [&"loop", &"zigzag"]:
		reset(mode)
		var result := cut(0, false)
		var hp: float = enemy.health
		expect(result.cue == &"link_cut" and enemy.lesson_state().progress == 1, "Actual first link cut: " + String(mode))
		var snapshot: Dictionary = enemy.capture_state()
		enemy.step_enemy(0, null)
		expect(enemy.window_timer == 6.5, "Frozen world preserves pattern window: " + String(mode))
		enemy.step_enemy(6.4, null)
		expect(enemy.lesson_state().progress == 1, "Partial lasts almost the fixed 6.5-world-second window: " + String(mode))
		enemy.step_enemy(0.11, null)
		expect(enemy.link_mask == 0 and enemy.health == hp, "Timeout reconnects links, preserves damage: " + String(mode))
		enemy.restore_state(snapshot)
		expect(enemy.lesson_state().progress == 1 and enemy.window_timer == 6.5 and enemy.health == hp, "Rewind restores mid-pattern timer and damage: " + String(mode))
		expect(not enemy.pattern_visual.links[0].visible and enemy.pattern_visual.links[1].visible, "Rewind restores derived link geometry: " + String(mode))
		cut(1, false)
		expect(enemy.link_mask == 3, "Second launch retains partial links: " + String(mode))
		reset(mode)
		full_cut()
		expect(enemy.is_core_exposed() and enemy.window_timer == 0, "Whole single-launch pattern opens permanently: " + String(mode))
		enemy.step_enemy(30, null)
		expect(enemy.is_core_exposed(), "Completed opening survives timeout: " + String(mode))
		var open_snapshot: Dictionary = enemy.capture_state()
		var low := shot_at(enemy.core_world_position(), 0.2)
		expect(not low.killed and not enemy.core_broken, "Low charge cannot finish cut unit: " + String(mode))
		var short_miss := segment(&"beam", enemy.core_world_position() + Vector3(0, 0, -2), enemy.core_world_position() + Vector3(0, 0, -0.6), {"charge": 1})
		expect(short_miss.cue != &"core_break", "Short/blocked ray never extends to core: " + String(mode))
		var finish := shot_at(enemy.core_world_position(), 1)
		expect(finish.killed and finish.cue == &"core_break", "Charged aimed finisher kills opened unit: " + String(mode))
		enemy.restore_state(open_snapshot)
		expect(enemy.health > 0 and enemy.is_core_exposed() and enemy.pattern_visual.core.visible, "Rewind revives completed opening: " + String(mode))
		reset(mode)
		enemy.receive_attack(&"cone", 16, Vector3.ZERO, {"dt": 1})
		expect(enemy.plate_broken, "Heat destroys orange: " + String(mode))
		var bare_hit: Dictionary = enemy.receive_attack(&"beam", 30, Vector3.ZERO)
		cut(0, false)
		var damaged: float = enemy.health
		enemy.step_enemy(6.6, null)
		expect(enemy.plate_broken and enemy.health == damaged, "Timeout preserves destroyed orange and body health: " + String(mode))
		expect(bare_hit.dealt > 30 * 0.12 and not bare_hit.armored, "Destroyed orange reduces resistance: " + String(mode))
		reset(mode)
		var once := segment(&"ring", Vector3(0.85, 0, 0), Vector3(0.95, 0, 0), {"already_hit": false})
		var once_hp: float = enemy.health
		for i in range(5): segment(&"ring", Vector3(0.85, 0, 0), Vector3(0.95, 0, 0), {"already_hit": true})
		expect(once.dealt > 0 and enemy.health == once_hp, "Repeated launch segments never duplicate body damage: " + String(mode))
		cut(0, true)
		expect(enemy.lesson_state().progress == 1 and enemy.health == once_hp, "Later same-launch segment still cuts after body hit: " + String(mode))
	reset(&"loop")
	var empty := segment(&"ring", Vector3(-1.8, 0.7, -1.0), Vector3(-1.8, 0.7, 1.0), {"already_hit": true})
	expect(enemy.link_mask == 0 and not empty.connected, "Empty gap between separate spans is never a phantom cable")
	reset(&"pair")
	shot_at(enemy.valve_world_position(1))
	expect(enemy.pair_progress == 0, "Closed B cannot start pair")
	var a := shot_at(enemy.valve_world_position(0))
	expect(a.cue == &"valve_b" and enemy.pair_progress == 1, "Quick A opens B")
	var pair_state: Dictionary = enemy.capture_state()
	var pair_hp: float = enemy.health
	enemy.step_enemy(2.41, null)
	expect(enemy.pair_progress == 0 and enemy.health == pair_hp, "Late pair resets shutters only")
	enemy.restore_state(pair_state)
	expect(enemy.pair_progress == 1 and enemy.window_timer == 2.4, "Rewind restores B shutter and timer")
	shot_at(enemy.valve_world_position(0))
	expect(enemy.pair_progress == 0 and enemy.health < pair_hp, "Wrong shot resets shutters, preserves ordinary damage")
	shot_at(enemy.valve_world_position(0))
	var b := shot_at(enemy.valve_world_position(1))
	expect(b.killed and enemy.lesson_state().complete, "Two accurate quick yellow hits finish Twin Valve")
	reset(&"final_boss")
	var boss_start: Dictionary = enemy.capture_state()
	shot_at(enemy.valve_world_position(0))
	shot_at(enemy.valve_world_position(1))
	expect(enemy.phase == 0 and enemy.is_core_exposed(), "Boss pair opens central finisher")
	shot_at(enemy.core_world_position(), 1)
	expect(enemy.phase == 1 and enemy.health == 900 and not enemy.pattern_visual.sections[0].visible, "Pair finisher removes boss yoke and advances to zigzag")
	var boss_mid: Dictionary = enemy.capture_state()
	full_cut()
	shot_at(enemy.core_world_position(), 1)
	expect(enemy.phase == 2 and enemy.health == 600 and not enemy.pattern_visual.sections[1].visible, "Zigzag finisher removes side columns and advances to loop")
	full_cut()
	shot_at(enemy.core_world_position(), 1)
	expect(enemy.phase == 3 and enemy.health == 300 and enemy.is_core_exposed(), "Loop finisher removes outriggers and opens final core")
	var final := shot_at(enemy.core_world_position(), 1)
	expect(final.killed, "Final exposed charged core ends boss")
	enemy.restore_state(boss_mid)
	expect(enemy.phase == 1 and enemy.health == 900 and enemy.active_pattern() == &"zigzag" and enemy.pattern_visual.links.size() == 3, "Rewind across phases restores links, health and missing sections")
	enemy.restore_state(boss_start)
	expect(enemy.phase == 0 and enemy.pattern_visual.sections[0].visible, "Rewind to first phase restores physical yoke")
	for mode: StringName in [&"loop", &"zigzag", &"pair", &"final_boss"]:
		for tool: StringName in [&"ring", &"beam", &"cone"]:
			reset(mode)
			for i in range(350): enemy.receive_attack(tool, 36, Vector3.ZERO)
			expect(enemy.health == 0, "Ordinary damage kill route: " + String(mode) + "/" + String(tool))
	reset(&"loop")
	var saved: Dictionary = enemy.capture_state()
	var encoded := var_to_bytes(saved)
	expect(not encoded.is_empty() and bytes_to_var(encoded).link_mask == 0, "Snapshots contain serializable values")
	# Reuse as a legacy Enemy remains safe for unsupported factory kinds.
	reset(&"target")
	expect(not PatternEnemy.handles(&"target") and enemy.receive_attack(&"beam", 20, Vector3.ZERO).dealt == 20, "Legacy kinds preserve ordinary Enemy behavior")
	enemy.free()
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
