extends SceneTree

const Equipment = preload("res://scenes/prototype/equipment.gd")
const RepairScene = preload("res://scenes/prototype/repair.tscn")
const Gestures = preload("res://scenes/prototype/repair_gestures.gd")
const EXPORT_DIR := "/home/mattlongname/game-jams/state/old-tech-jam-3/exports/round-k"

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
	root.size = Vector2i(1280, 800)
	await frames(2)

	# 1. Capture 2x2 Overview of all 4 tool backdrops & operations (matching mockups 2, 3, 4, 5)
	var sheet := Control.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(sheet)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.07, 0.10, 1.0)
	sheet.add_child(bg)

	var title := Label.new()
	title.text = "JAM-3 ROUND K — TOOL-SPECIFIC REPAIR INTERACTIONS (SPIN · TRACE · CONNECT ON 4 TOOL BACKDROPS)"
	title.position = Vector2(16, 8)
	title.add_theme_font_size_override("font_size", 14)
	sheet.add_child(title)

	var cell_size := Vector2(452, 268)
	var gear_overview := Equipment.new()
	# Spend all tools so Operation 1 is active and all 3 operations are visible on each tool
	for t: StringName in [&"beam", &"clock", &"ring", &"cone"]:
		gear_overview.spend(t, gear_overview.capacity(t))

	var g_beam := Equipment.new()
	g_beam.spend(&"beam", g_beam.capacity(&"beam"))
	var g_clock := Equipment.new()
	g_clock.spend(&"clock", g_clock.capacity(&"clock"))
	var g_ring := Equipment.new()
	g_ring.spend(&"ring", g_ring.capacity(&"ring"))
	var g_cone := Equipment.new()
	g_cone.spend(&"cone", g_cone.capacity(&"cone"))

	var c_beam := _make_card(sheet, Vector2(16, 34), cell_size, g_beam, &"beam")
	var c_clock := _make_card(sheet, Vector2(492, 34), cell_size, g_clock, &"clock")
	var c_ring := _make_card(sheet, Vector2(16, 316), cell_size, g_ring, &"ring")
	var c_cone := _make_card(sheet, Vector2(492, 316), cell_size, g_cone, &"cone")

	for card in [c_beam, c_clock, c_ring, c_cone]:
		card.panel.position = Vector2.ZERO
		card.panel.size = cell_size
		card._queue_redraws()

	var p1 := await save_png("repair-4tools-overview.png")

	# 2. Capture active mid-gesture & interrupted / partial repair states across the 4 tools
	title.text = "JAM-3 ROUND K — ACTIVE GESTURES & INTERRUPTED / PARTIAL REPAIR STATES (OP 1 SPIN, OP 2 CONNECT, OP 3 TRACE, LIGHT WEAR)"
	# Top-left (beam): mid-Spin (60% spun around lens ring)
	c_beam.dragging = true
	c_beam.spin_accum = c_beam.spin_required * 0.65
	c_beam.spin_locked_dir = -1.0
	c_beam._queue_redraws()

	# Top-right (clock): Stage 1 (Op 2 Pendulum Trace active, Op 1 Spin ✓ completed)
	g_clock.complete_step(&"clock")
	c_clock._refresh()
	c_clock.panel.position = Vector2.ZERO
	c_clock.panel.size = cell_size
	c_clock.dragging = true
	c_clock.next_contact = 2
	c_clock.stroke.assign([c_clock.route[0], c_clock.route[1], c_clock.route[1].lerp(c_clock.route[2], 0.5)])
	c_clock._queue_redraws()

	# Bottom-left (ring): Stage 1 (Op 2 Connect active with Pair ▲A connected ✓ and ■B selected)
	g_ring.complete_step(&"ring")
	c_ring._refresh()
	c_ring.panel.position = Vector2.ZERO
	c_ring.panel.size = cell_size
	c_ring.connected_pairs.assign([0])
	var ring_pairs: Array = c_ring.active_op["pairs"]
	c_ring.selected_terminal = {
		"pair_index": 1,
		"pair_id": &"B",
		"shape": &"square",
		"label": "B",
		"side": "a",
		"position": ring_pairs[1]["a"],
	}
	c_ring.feedback.text = "Connected ▲A. Selected ■B — click matching ■B terminal."
	c_ring._queue_redraws()

	# Bottom-right (cone): Stage 3 light wear (89% condition: Op 1 Spin ✓, Op 2 Trace ✓, Pair ▲A ✓, only ■B left!)
	g_cone.reset_state()
	g_cone.spend(&"cone", 5.0)
	c_cone.setup({"equipment": g_cone, "tool": &"cone"})
	c_cone.panel.position = Vector2.ZERO
	c_cone.panel.size = cell_size
	c_cone._queue_redraws()

	var p2 := await save_png("repair-progress-states.png")
	sheet.queue_free()
	await frames(2)

	# 3. Capture live Arena with top-right Repair popup open (showing player visible at center)
	var arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	arena.equipment.spend(&"cone", arena.equipment.capacity(&"cone"))
	var popup_layer := CanvasLayer.new()
	popup_layer.layer = 50
	arena.add_child(popup_layer)
	var live_popup: Control = RepairScene.instantiate()
	popup_layer.add_child(live_popup)
	live_popup.setup({"equipment": arena.equipment, "tool": &"cone"})
	await frames(5)
	expect(live_popup != null and arena.equipment.repairing == &"cone", "Live arena repair popup opened for cone")
	var p3 := await save_png("repair-in-arena.png")

	live_popup.queue_free()
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
