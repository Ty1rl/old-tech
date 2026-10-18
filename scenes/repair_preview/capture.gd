extends SceneTree

const Equipment = preload("res://scenes/prototype/equipment.gd")
const RepairScene = preload("res://scenes/prototype/repair.tscn")
const Gestures = preload("res://scenes/prototype/repair_gestures.gd")
const EXPORT_DIR := "/home/mattlongname/game-jams/state/old-tech-jam-3/exports/round-o"

var checks := 0
var failures: Array[String] = []


class PreviewConditionArc extends Control:
	var _equipment: WeaponEquipment = null
	var _tool: StringName = &"ring"

	func _init() -> void:
		name = "RepairCondition"
		custom_minimum_size = Vector2(200.0, 155.0)
		size = Vector2(200.0, 155.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func bind_equipment(next_equipment: WeaponEquipment, next_tool: StringName) -> void:
		_equipment = next_equipment
		_tool = next_tool
		queue_redraw()

	func segment_count() -> int:
		return maxi(1, _equipment.repair_steps) if _equipment != null else 4

	func filled_segments() -> int:
		if _equipment == null:
			return 4
		if _equipment.is_full(_tool):
			return segment_count()
		return clampi(_equipment.stage(_tool), 0, segment_count())

	func _draw() -> void:
		var count := segment_count()
		var filled := filled_segments()
		var ratio := clampf(_equipment.condition(_tool), 0.0, 1.0) if _equipment != null else 1.0
		var spec := Gestures.tool_spec(_tool)
		var accent: Color = spec.get("accent", Color("67c9f5"))
		var panel_rect := Rect2(Vector2.ZERO, size)
		draw_rect(panel_rect, Color(0.03, 0.05, 0.08, 0.86), true)
		draw_rect(panel_rect, Color(accent, 0.65), false, 1.6)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(10.0, 18.0),
			String(spec.get("title", "Weapon")).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			Color("e6ecf4")
		)
		var center := Vector2(size.x * 0.50, size.y * 0.56)
		var radius := minf(size.x, size.y) * 0.30
		var start_deg := 145.0
		var total_span := 250.0
		var gap_deg := 10.0
		var seg_span := (total_span - gap_deg * float(maxi(0, count - 1))) / float(count)
		draw_arc(center, radius, deg_to_rad(start_deg), deg_to_rad(start_deg + total_span), 36, Color(0.01, 0.02, 0.03, 0.92), 16.0, true)
		for i in range(count):
			var a0 := deg_to_rad(start_deg + float(i) * (seg_span + gap_deg))
			var a1 := deg_to_rad(start_deg + float(i) * (seg_span + gap_deg) + seg_span)
			var seg_frac := clampf(ratio * float(count) - float(i), 0.0, 1.0)
			draw_arc(center, radius, a0, a1, 14, Color(0.14, 0.19, 0.25, 0.85), 10.0, true)
			if i < filled:
				draw_arc(center, radius, a0, a1, 14, Color("8ad2a3"), 10.0, true)
			elif seg_frac > 0.02:
				draw_arc(center, radius, a0, lerpf(a0, a1, seg_frac), 12, accent, 10.0, true)
		draw_string(
			ThemeDB.fallback_font,
			center + Vector2(-18.0, 5.0),
			"%d%%" % int(round(ratio * 100.0)),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			15,
			Color("e6ecf4")
		)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(10.0, size.y - 10.0),
			"%d / %d SEGMENTS" % [filled, count],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			11,
			Color("8ad2a3") if filled >= count else accent
		)


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


func _mount_preview_condition(rep: Control) -> void:
	var slot := rep.get_node_or_null("Panel/Margin/Column/Board/ConditionSlot") as Control
	if slot != null and slot.get_child_count() == 0:
		var cond := PreviewConditionArc.new()
		slot.add_child(cond)
		rep._sync_condition_view()


func _make_card(parent: Control, pos: Vector2, card_size: Vector2, gear: RefCounted, tool_id: StringName) -> Control:
	var holder := Control.new()
	holder.position = pos
	holder.size = card_size
	parent.add_child(holder)

	var rep: Control = RepairScene.instantiate()
	rep.preview_rect = Rect2(Vector2.ZERO, card_size)
	_mount_preview_condition(rep)
	holder.add_child(rep)
	rep.setup({"equipment": gear, "tool": tool_id, "allow_full_preview": true})
	rep._update_layout()
	return rep


func capture() -> void:
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	root.size = Vector2i(1280, 800)
	await frames(4)

	# 1. Capture 3-Weapon Physical Part Alignment Overview (1280x800)
	var sheet := Control.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(sheet)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.07, 0.10, 1.0)
	sheet.add_child(bg)

	var title := Label.new()
	title.text = "JAM-3 ROUND O WAVE A — PHYSICAL 3D PART ALIGNMENT, LEADER BADGES, MISSING VS INTACT & CONDITION SEGMENTS"
	title.position = Vector2(16, 8)
	title.add_theme_font_size_override("font_size", 15)
	sheet.add_child(title)

	var vp := root.get_visible_rect().size
	var cell_w := floorf((vp.x - 48.0) * 0.5)
	var cell_h := floorf((vp.y - 54.0) * 0.5)
	var cell_size := Vector2(cell_w, cell_h)
	var g_ring := Equipment.new()
	g_ring.spend(&"ring", g_ring.capacity(&"ring") * 0.75) # Stage 1 (Arch Contacts) with Stage 0 intact
	var g_beam := Equipment.new()
	g_beam.spend(&"beam", g_beam.capacity(&"beam")) # Stage 0 (Lens Spin)
	var g_cone := Equipment.new()
	g_cone.spend(&"cone", g_cone.capacity(&"cone")) # Stage 0 (Fan Spin with open cover)
	var g_connect := Equipment.new()
	g_connect.spend(&"cone", g_connect.capacity(&"cone") * 0.35) # Stage 2 (Coil Contacts with partial wear)

	var c_ring := _make_card(sheet, Vector2(16, 32), cell_size, g_ring, &"ring")
	var c_beam := _make_card(sheet, Vector2(32 + cell_w, 32), cell_size, g_beam, &"beam")
	var c_cone := _make_card(sheet, Vector2(16, 42 + cell_h), cell_size, g_cone, &"cone")
	var c_connect := _make_card(sheet, Vector2(32 + cell_w, 42 + cell_h), cell_size, g_connect, &"cone")

	for card in [c_ring, c_beam, c_cone, c_connect]:
		card.panel.position = Vector2.ZERO
		card.panel.size = cell_size
		card._sync_tool_canvas()
		card._refresh()

	var p1 := await save_png("repair-round-o-3weapons.png")

	# 2. Capture Round O States: In-Place 3D Spin Rotation, Stage Hint Demonstration, Completion Flash & Partial Wear
	title.text = "JAM-3 ROUND O WAVE A — IN-PLACE 3D PART ROTATION, STAGE HINT OVERLAY, COMPLETION PULSE & PARTIAL WEAR"
	c_beam.dragging = true
	c_beam.spin_grip_angle = -PI * 0.5
	c_beam.spin_accum = c_beam.spin_required * 0.68
	c_beam.spin_locked_dir = -1.0
	c_beam.spin_visual_angle = -c_beam.spin_accum
	c_beam._update_3d_backdrop()
	c_beam.feedback.text = "Spinning CCW · 68% (Lens rotates around local optical axis)"
	c_beam._queue_redraws()

	c_ring.show_stage_hint("Hint: Click or drag matching triangle and square contacts along the arch.")
	c_ring._stage_hint_phase = 0.62
	c_ring._queue_redraws()

	var flash_op: Dictionary = c_cone.projected_operations[0].duplicate(true)
	g_cone.complete_step(&"cone", c_cone._session)
	c_cone._refresh()
	c_cone._completion_flash_op = flash_op
	c_cone._completion_flash_until_usec = Time.get_ticks_usec() + 350000
	c_cone.feedback.text = "Stage locked (+4.5). Next mechanism ready immediately · E or Esc close."
	c_cone._queue_redraws()

	var p2 := await save_png("repair-round-o-states.png")
	sheet.queue_free()
	await frames(2)

	# 3. Capture Live Arena at Large Window (1280x800) with StatusHUD & ConditionSlot
	var arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	arena.equipment.spend(&"ring", arena.equipment.capacity(&"ring") * 0.42) # Partial wear in Stage 2 (Saw Ring Rim Trace)
	arena.equipment.spend(&"beam", arena.equipment.capacity(&"beam") * 0.75)
	arena.weapons.select_tool(1)
	arena._open_smart_repair()
	await frames(5)
	var live_popup: Control = arena._active_repair_panel()
	expect(live_popup != null and live_popup.tool == &"ring" and arena.status_hud.visible,
		"Live arena repair popup opened on damaged equipped Ring with StatusHUD visible")
	if live_popup != null:
		_mount_preview_condition(live_popup)
		live_popup.dragging = true
		live_popup.next_contact = 2
		live_popup.stroke.assign([live_popup.route[0], live_popup.route[0].lerp(live_popup.route[1], 0.65)])
		live_popup.feedback.text = "Tracing saw ring blade rim · Intact green vs missing dashed channel · WASD move · Space slow"
		live_popup._queue_redraws()
	await frames(3)
	var p3 := await save_png("repair-round-o-arena-large.png")

	# 4. Capture Live Arena at Small Window (640x360)
	DisplayServer.window_set_size(Vector2i(640, 360))
	root.size = Vector2i(640, 360)
	await frames(5)
	if live_popup != null:
		live_popup._update_layout()
		live_popup._refresh()
	await frames(3)
	var p4 := await save_png("repair-round-o-arena-small.png")

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
