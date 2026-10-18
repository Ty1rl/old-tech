extends SceneTree

const Equipment = preload("res://scenes/prototype/equipment.gd")
const RepairScene = preload("res://scenes/prototype/repair.tscn")
const Gestures = preload("res://scenes/prototype/repair_gestures.gd")
const EXPORT_DIR := "/home/mattlongname/game-jams/state/old-tech-jam-3/exports/round-m"

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("capture")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func frames(count: int = 4) -> void:
	for _i in range(count):
		await process_frame


func save_png(filename: String) -> String:
	await frames(5)
	var img := root.get_texture().get_image()
	expect(img != null and img.get_width() > 0 and img.get_height() > 0, filename + ": non-empty capture image")
	var out_path := EXPORT_DIR + "/" + filename
	var err := img.save_png(out_path)
	expect(err == OK, filename + ": saved PNG to " + out_path)
	return out_path


func _make_card(parent: Control, pos: Vector2, card_size: Vector2, gear: RefCounted, tool_id: StringName) -> Control:
	var holder := Control.new()
	holder.position = pos
	holder.size = card_size
	parent.add_child(holder)

	var rep: Control = RepairScene.instantiate()
	rep.preview_rect = Rect2(Vector2.ZERO, card_size)
	holder.add_child(rep)
	rep.setup({"equipment": gear, "tool": tool_id})
	rep._update_layout()
	return rep


func capture() -> void:
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	root.size = Vector2i(1280, 800)
	await frames(4)

	# 1. Capture 2x2 Overview of all 4 tool backdrops & Spin operations at full 1280x800 layout
	var sheet := Control.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(sheet)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.07, 0.10, 1.0)
	sheet.add_child(bg)

	var title := Label.new()
	title.text = "JAM-3 ROUND M — FORGIVING BIDIRECTIONAL SPIN, E-TOGGLE REPAIR & TOOL SWITCHING (4 TOOLS)"
	title.position = Vector2(16, 8)
	title.add_theme_font_size_override("font_size", 15)
	sheet.add_child(title)

	var vp := root.get_visible_rect().size
	var cell_w := floorf((vp.x - 48.0) * 0.5)
	var cell_h := floorf((vp.y - 54.0) * 0.5)
	var cell_size := Vector2(cell_w, cell_h)
	var g_beam := Equipment.new()
	g_beam.spend(&"beam", g_beam.capacity(&"beam"))
	var g_clock := Equipment.new()
	g_clock.spend(&"clock", g_clock.capacity(&"clock"))
	var g_ring := Equipment.new()
	g_ring.spend(&"ring", g_ring.capacity(&"ring"))
	var g_cone := Equipment.new()
	g_cone.spend(&"cone", g_cone.capacity(&"cone"))

	var c_beam := _make_card(sheet, Vector2(16, 32), cell_size, g_beam, &"beam")
	var c_clock := _make_card(sheet, Vector2(32 + cell_w, 32), cell_size, g_clock, &"clock")
	var c_ring := _make_card(sheet, Vector2(16, 42 + cell_h), cell_size, g_ring, &"ring")
	var c_cone := _make_card(sheet, Vector2(32 + cell_w, 42 + cell_h), cell_size, g_cone, &"cone")

	for card in [c_beam, c_clock, c_ring, c_cone]:
		card.panel.position = Vector2.ZERO
		card.panel.size = cell_size
		card._queue_redraws()

	var p1 := await save_png("repair-4tools-overview.png")

	# 2. Capture Round M Spin states: CCW oval drag, banked regrip progress, Ready state, and Connect state
	title.text = "JAM-3 ROUND M — CCW OVAL SPIN (65%), BANKED REGRIP PROGRESS (52%), READY ✓ STATE & CONNECT"
	# Top-left (beam): mid-Spin CCW (65% spun around lens ring with live grip handle)
	c_beam.dragging = true
	c_beam.spin_grip_angle = 2.2
	c_beam.spin_accum = c_beam.spin_required * 0.65
	c_beam.spin_locked_dir = -1.0
	c_beam.feedback.text = "Spinning CCW · 65%"
	c_beam._queue_redraws()

	# Top-right (clock): Banked partial arc after regrip release (52% saved in spin_base_accum)
	c_clock.dragging = false
	c_clock.trace_bad = false
	c_clock.spin_grip_angle = -PI * 0.5
	c_clock.spin_base_accum = c_clock.spin_required * 0.52
	c_clock.spin_accum = c_clock.spin_base_accum
	c_clock.spin_locked_dir = 1.0
	c_clock.feedback.text = "Released early (52% spun). Progress saved — drag again to finish."
	c_clock._queue_redraws()

	# Bottom-left (ring): Completed 100% Full tool remaining displayed as READY ✓ inside repair
	g_ring.reset_state()
	c_ring.switch_tool(&"ring")
	c_ring.panel.position = Vector2.ZERO
	c_ring.panel.size = cell_size
	c_ring._queue_redraws()

	# Bottom-right (cone): Stage 3 light wear (89% condition: Op 1 Spin ✓, Op 2 Trace ✓, Pair ▲A ✓, only ■B left)
	g_cone.reset_state()
	g_cone.spend(&"cone", 2.0)
	c_cone.setup({"equipment": g_cone, "tool": &"cone"})
	c_cone.panel.position = Vector2.ZERO
	c_cone.panel.size = cell_size
	c_cone._queue_redraws()

	var p2 := await save_png("repair-progress-states.png")
	sheet.queue_free()
	await frames(2)

	# 3. Capture live Arena with fullscreen transparent E-toggled Repair view open during active Spin
	var arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	arena.equipment.spend(&"ring", arena.equipment.capacity(&"ring"))
	var scenes: Node = root.get_node("SceneManager")
	var live_popup: Control = scenes.push_popup(&"Repair", {"equipment": arena.equipment, "tool": &"ring", "arena": arena})
	await frames(5)
	arena._update_hud()
	live_popup.dragging = true
	live_popup.spin_grip_angle = -PI * 0.35
	live_popup.spin_accum = live_popup.spin_required * 0.58
	live_popup.spin_locked_dir = 1.0
	live_popup.feedback.text = "Spinning CW · 58% · Tab / 1–4 switch tools · WASD move · Space slow"
	live_popup._queue_redraws()
	await frames(3)
	expect(live_popup != null and arena.equipment.repairing == &"ring", "Live arena repair popup opened for ring")
	var p3 := await save_png("repair-in-arena.png")

	scenes.close_popup(&"Repair")
	arena.queue_free()
	await frames(2)
	await create_timer(0.10).timeout

	var summary := {
		"status": "passed" if failures.is_empty() else "failed",
		"checks": checks,
		"failures": failures,
		"renders": [p1, p2, p3],
	}
	print(JSON.stringify(summary))
	quit(0 if failures.is_empty() else 1)
