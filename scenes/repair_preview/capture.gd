extends SceneTree

const Equipment = preload("res://scenes/prototype/equipment.gd")
const RepairScene = preload("res://scenes/prototype/repair.tscn")
const Gestures = preload("res://scenes/prototype/repair_gestures.gd")
const EXPORT_DIR := "/home/mattlongname/game-jams/state/old-tech-jam-3/exports/round-n-wave2"

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
	rep.setup({"equipment": gear, "tool": tool_id, "allow_full_preview": true})
	rep._update_layout()
	return rep


func capture() -> void:
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	root.size = Vector2i(1280, 800)
	await frames(4)

	# 1. Capture 3-Weapon Overview (Ring, Beam, Cone) + Smart Target & Time Cost Summary
	var sheet := Control.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(sheet)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.07, 0.10, 1.0)
	sheet.add_child(bg)

	var title := Label.new()
	title.text = "JAM-3 ROUND N WAVE 2 — THREE-WEAPON REPAIR (RING, BEAM, CONE), SMART TARGETING & ATOMIC TIME SPEND"
	title.position = Vector2(16, 8)
	title.add_theme_font_size_override("font_size", 15)
	sheet.add_child(title)

	var vp := root.get_visible_rect().size
	var cell_w := floorf((vp.x - 48.0) * 0.5)
	var cell_h := floorf((vp.y - 54.0) * 0.5)
	var cell_size := Vector2(cell_w, cell_h)
	var g_ring := Equipment.new()
	g_ring.spend(&"ring", g_ring.capacity(&"ring"))
	var g_beam := Equipment.new()
	g_beam.spend(&"beam", g_beam.capacity(&"beam"))
	var g_cone := Equipment.new()
	g_cone.spend(&"cone", g_cone.capacity(&"cone"))
	var g_connect := Equipment.new()
	g_connect.spend(&"cone", 2.0)

	var c_ring := _make_card(sheet, Vector2(16, 32), cell_size, g_ring, &"ring")
	var c_beam := _make_card(sheet, Vector2(32 + cell_w, 32), cell_size, g_beam, &"beam")
	var c_cone := _make_card(sheet, Vector2(16, 42 + cell_h), cell_size, g_cone, &"cone")
	var c_connect := _make_card(sheet, Vector2(32 + cell_w, 42 + cell_h), cell_size, g_connect, &"cone")

	for card in [c_ring, c_beam, c_cone, c_connect]:
		card.panel.position = Vector2.ZERO
		card.panel.size = cell_size
		card._queue_redraws()

	var p1 := await save_png("repair-3weapons-overview.png")

	# 2. Capture Wave 2 Spin / Time Recharge / Auto-Advance States
	title.text = "JAM-3 ROUND N WAVE 2 — CCW SPIN (65%), IDLE RECHARGE FEEDBACK, AUTO-ADVANCE & TRACE"
	c_beam.dragging = true
	c_beam.spin_grip_angle = 2.2
	c_beam.spin_accum = c_beam.spin_required * 0.65
	c_beam.spin_locked_dir = -1.0
	c_beam.feedback.text = "Spinning CCW · 65%"
	c_beam._queue_redraws()

	c_ring.dragging = false
	c_ring.trace_bad = true
	c_ring.spin_grip_angle = -PI * 0.5
	c_ring.spin_base_accum = c_ring.spin_required
	c_ring.spin_accum = c_ring.spin_required
	c_ring.spin_locked_dir = 1.0
	c_ring.feedback.text = "Not enough time for checkpoint — pause gesture to let time recharge."
	c_ring._queue_redraws()

	g_cone.complete_step(&"cone", c_cone._session)
	c_cone._refresh()
	c_cone.feedback.text = "Checkpoint complete (+4.5). Next operation ready · E or Esc close."
	c_cone._queue_redraws()

	var p2 := await save_png("repair-wave2-states.png")
	sheet.queue_free()
	await frames(2)

	# 3. Capture Live Arena with Transparent E-Toggled Repair Open and StatusHUD Visible
	var arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	arena.equipment.spend(&"ring", arena.equipment.capacity(&"ring") * 0.50)
	arena.equipment.spend(&"cone", arena.equipment.capacity(&"cone") * 0.75)
	arena.weapons.select_tool(1)
	arena._open_smart_repair()
	await frames(5)
	var live_popup: Control = arena._active_repair_panel()
	expect(live_popup != null and live_popup.tool == &"ring" and arena.status_hud.visible,
		"Live arena repair popup opened on damaged equipped Ring with StatusHUD visible")
	live_popup.dragging = true
	live_popup.next_contact = 2
	live_popup.stroke.assign([live_popup.route[0], live_popup.route[1], live_popup.route[1].lerp(live_popup.route[2], 0.5)])
	live_popup.feedback.text = "Tracing saw ring arc · 2/4 contacts · Tab / 1–3 switch tools · WASD move · Space slow"
	live_popup._queue_redraws()
	await frames(3)
	var p3 := await save_png("repair-in-arena-wave2.png")

	arena._close_repair()
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
