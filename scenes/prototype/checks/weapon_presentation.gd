extends SceneTree
const Harness = preload("res://scenes/weapons/checks/harness.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func mouse(down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	return e
func run() -> void:
	var harness := Harness.new()
	root.add_child(harness)
	var w: WeaponController = harness.weapons
	var player: Node3D = harness.player
	var cues: Array = []
	w.combat_event.connect(func(kind: StringName, point: Vector3, _strength: float): cues.append({"kind":kind,"point":point}))
	var aim := Vector3(0, 0, -12)
	w.select_tool(2)
	var muzzle: Vector3 = player.visual.muzzle_position(2)
	w.handle_event(mouse(true), player, aim)
	w.step(.5, player, aim, [], 0)
	expect(w.presentation.last_beam_start.is_equal_approx(muzzle), "Charge halo begins at actual visual lens")
	expect(w.presentation.batch.get_surface_count() == 1 and not w.presentation.pierce_ready, "Charge presentation uses one shared mesh")
	w.step(.4, player, aim, [], 0)
	expect(w.presentation.pierce_ready and cues.filter(func(c): return c.kind == &"flash_ready").size() == 1, "Ready cue and halo reflect configured charge threshold exactly once")
	w.handle_event(mouse(false), player, aim)
	expect(cues.any(func(c): return c.kind == &"flash_fire" and c.point.is_equal_approx(muzzle)), "Fire cue uses emitting lens")
	expect(w.flash.pulses.size() == 1 and w.flash.pulses[0].muzzle == muzzle, "Pulse retains exact launch origin")
	w.step(.1, player, aim, [], .1)
	expect(w.presentation.last_beam_start == muzzle and w.presentation.vertices > 0, "Traveling focused light begins at stored lens origin")
	var snapshot := w.capture_state()
	player.position.x += 3
	w.step(.1, player, aim, [], .1)
	expect(w.flash.pulses[0].muzzle == muzzle, "Moving after release cannot drag a launched flash")
	w.restore_state(snapshot)
	expect(w.flash.pulses[0].muzzle == muzzle, "Replay restores lens origin")
	var condition := harness.equipment.remaining(&"beam")
	for tick in range(10): w.rebuild_visuals(player)
	expect(harness.equipment.remaining(&"beam") == condition, "Rendering neither wears condition nor applies hits")
	w.reset_state()
	w.select_tool(3)
	w.handle_event(mouse(true), player, aim)
	w.step(.05, player, aim, [], .05)
	var air_origin: Vector3 = player.visual.muzzle_position(3)
	expect(cues.any(func(c): return c.kind == &"cone_pulse" and c.point.is_equal_approx(air_origin)), "Bellows pulse cue uses actual nozzle")
	expect(w.presentation.last_air_origin == air_origin, "Displaced air starts at nozzle")
	expect(w.presentation.vertices > 200 and w.presentation.vertices < 1000 and w.presentation.batch.get_surface_count() == 1, "Air wisps/rings remain one bounded batch")
	var phase := w.presentation.phase
	w.step(.1, player, aim, [], 0)
	expect(w.presentation.phase == phase, "Zero world delta freezes air motion")
	w.step(.1, player, aim, [], .018)
	expect(is_equal_approx(w.presentation.phase - phase, .018), "Air follows slowed world time")
	var children: Array = w.get_children()
	for tick in range(60): w.rebuild_visuals(player)
	expect(w.get_children() == children, "Repeated presentation never creates/deletes authored scene children")
	w.reset_state()
	expect(w.presentation.batch.get_surface_count() == 0 and w.presentation.phase == 0 and w.ring.stroke.mesh.get_surface_count() == 0, "Reset clears all procedural presentation")
	harness.free()
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
