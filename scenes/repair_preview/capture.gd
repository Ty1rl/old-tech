extends SceneTree

const Equipment = preload("res://scenes/prototype/equipment.gd")
const RepairScene = preload("res://scenes/prototype/repair.tscn")
const Gestures = preload("res://scenes/prototype/repair_gestures.gd")
const ToolStyle = preload("res://scenes/prototype/tool_style.gd")
const EXPORT_DIR := "/home/mattlongname/game-jams/state/old-tech-jam-3/exports/round-p-a"

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

	# 1. Capture 3-Weapon Active-Step-Only Left-to-Right Overview (1280x800)
	var sheet := Control.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(sheet)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.08, 0.11, 1.0)
	sheet.add_child(bg)

	var title := Label.new()
	title.text = "JAM-3 ROUND P WAVE A — ACTIVE-STEP-ONLY REPAIR UI, NEUTRAL IVORY GUIDES & LEFT-TO-RIGHT ANCHORS"
	title.position = Vector2(16, 8)
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", ToolStyle.REPAIR_GUIDE)
	sheet.add_child(title)

	var vp := root.get_visible_rect().size
	var cell_w := floorf((vp.x - 48.0) * 0.5)
	var cell_h := floorf((vp.y - 54.0) * 0.5)
	var cell_size := Vector2(cell_w, cell_h)

	var g_ring := Equipment.new()
	g_ring.spend(&"ring", g_ring.capacity(&"ring") * 0.75) # Step 2/3: Arch Contacts (middle)
	var g_beam := Equipment.new()
	g_beam.spend(&"beam", g_beam.capacity(&"beam")) # Step 1/3: Lens Spin (left)
	var g_cone_spin := Equipment.new()
	g_cone_spin.spend(&"cone", g_cone_spin.capacity(&"cone")) # Step 1/3: Intake Fan Spin (left)
	var g_cone_coils := Equipment.new()
	g_cone_coils.spend(&"cone", g_cone_coils.capacity(&"cone") * 0.35) # Step 3/3: Heating Coils (right)

	var c_ring := _make_card(sheet, Vector2(16, 32), cell_size, g_ring, &"ring")
	var c_beam := _make_card(sheet, Vector2(32 + cell_w, 32), cell_size, g_beam, &"beam")
	var c_cone_spin := _make_card(sheet, Vector2(16, 42 + cell_h), cell_size, g_cone_spin, &"cone")
	var c_cone_coils := _make_card(sheet, Vector2(32 + cell_w, 42 + cell_h), cell_size, g_cone_coils, &"cone")

	for card in [c_ring, c_beam, c_cone_spin, c_cone_coils]:
		card.panel.position = Vector2.ZERO
		card.panel.size = cell_size
		card._sync_tool_canvas()
		card._refresh()

	var p1 := await save_png("repair-round-p-a-3weapons.png")

	# 2. Capture Left-to-Right Trace (1->4), Active Spin, Finite Demo & Neutral Completion Check
	title.text = "JAM-3 ROUND P WAVE A — LEFT-TO-RIGHT TRACE (1->4), FROZEN GESTURE DRAG & FINITE STAGE DEMO"
	var g_ring_trace := Equipment.new()
	g_ring_trace.spend(&"ring", g_ring_trace.capacity(&"ring") * 0.40) # Step 3/3: Blade Rim Trace (right)
	c_ring.setup({"equipment": g_ring_trace, "tool": &"ring", "allow_full_preview": true})
	c_ring._refresh()

	var g_beam_trace := Equipment.new()
	g_beam_trace.spend(&"beam", g_beam_trace.capacity(&"beam") * 0.40) # Step 3/3: Bellows Trace (right)
	c_beam.setup({"equipment": g_beam_trace, "tool": &"beam", "allow_full_preview": true})
	c_beam._refresh()
	c_beam.dragging = true
	c_beam.next_contact = 2
	c_beam.stroke.assign([c_beam.route[0], c_beam.route[0].lerp(c_beam.route[1], 0.72)])
	c_beam.feedback.text = "Tracing 1 -> 4 left-to-right · Targets frozen while dragging"
	c_beam._queue_redraws()

	c_cone_spin.show_stage_hint("Spin the intake fan")
	c_cone_spin._stage_hint_phase = 0.58
	c_cone_spin._queue_redraws()

	var g_cone_trace := Equipment.new()
	g_cone_trace.spend(&"cone", g_cone_trace.capacity(&"cone") * 0.75) # Step 2/3: Leather Seams Trace (middle)
	c_cone_coils.setup({"equipment": g_cone_trace, "tool": &"cone", "allow_full_preview": true})
	c_cone_coils._refresh()
	var flash_op: Dictionary = c_cone_coils.projected_operations[0].duplicate(true)
	c_cone_coils._completion_flash_op = flash_op
	c_cone_coils._completion_flash_until_usec = Time.get_ticks_usec() + 350000
	c_cone_coils._queue_redraws()

	var p2 := await save_png("repair-round-p-a-steps.png")
	sheet.queue_free()
	await frames(2)

	# 3. Capture Live Arena at Large Window (1280x800) Showing Translucent Model Over Combat World
	var arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	arena.equipment.spend(&"ring", arena.equipment.capacity(&"ring") * 0.42) # Step 3/3: Blade Rim Trace
	arena.equipment.spend(&"beam", arena.equipment.capacity(&"beam") * 0.75)
	arena.weapons.select_tool(1)
	arena._open_smart_repair()
	await frames(5)
	var live_popup: Control = arena._active_repair_panel()
	expect(live_popup != null and live_popup.tool == &"ring" and arena.status_hud.visible,
		"Live arena repair popup opened on damaged equipped Ring with StatusHUD visible")
	if live_popup != null:
		live_popup.dragging = true
		live_popup.next_contact = 2
		live_popup.stroke.assign([live_popup.route[0], live_popup.route[0].lerp(live_popup.route[1], 0.65)])
		live_popup.feedback.text = "E / Esc close · Tab / 1–3 switch · WASD move · Space slow"
		live_popup._queue_redraws()
	await frames(3)
	var p3 := await save_png("repair-round-p-a-arena-large.png")

	# 4. Capture Live Arena at Small Window (640x360)
	DisplayServer.window_set_size(Vector2i(640, 360))
	root.size = Vector2i(640, 360)
	await frames(5)
	if live_popup != null:
		live_popup.dragging = false
		live_popup._update_layout()
		live_popup._refresh()
	await frames(3)
	var p4 := await save_png("repair-round-p-a-arena-small.png")

	arena._close_repair()
	arena.queue_free()
	await frames(2)
	await create_timer(0.10).timeout

	var summary := {
		"status": "passed" if failures.is_empty() else "failed",
		"checks": checks,
		"failures": failures,
		"renders": [p1, p2, p3, p4],
	}
	print(JSON.stringify(summary))
	quit(0 if failures.is_empty() else 1)
