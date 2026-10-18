extends SceneTree

const Equipment = preload("res://scenes/prototype/equipment.gd")
const RepairScene = preload("res://scenes/prototype/repair.tscn")
const Gestures = preload("res://scenes/prototype/repair_gestures.gd")
const OUT := "/home/mattlongname/game-jams/state/old-tech-jam-3/exports/repair-view-l"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)

func frames() -> void:
	for i in range(5):
		await process_frame

func pointer(panel: Control, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = panel.board.get_global_transform_with_canvas() * (panel._board_offset() + point * panel._board_scale())
	event.global_position = event.position
	root.push_input(event, true)

func gesture(panel: Control) -> void:
	var points: Array = panel.route.duplicate()
	pointer(panel, points[0], true)
	for point: Vector2 in points.slice(1):
		var event := InputEventMouseMotion.new()
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		event.position = panel.board.get_global_transform_with_canvas() * (panel._board_offset() + point * panel._board_scale())
		event.global_position = event.position
		root.push_input(event, true)
	pointer(panel, points[-1], false)

func connect_pair(panel: Control, idx: int) -> void:
	var pair: Dictionary = panel.active_op["pairs"][idx]
	for side in ["a", "b"]:
		pointer(panel, pair[side], true)
		pointer(panel, pair[side], false)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1280, 800)
	var arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await frames()
	arena.set_physics_process(false)
	var gear = arena.equipment
	var scenes := root.get_node("SceneManager")
	for tool: StringName in [&"ring", &"beam", &"cone", &"clock"]:
		gear.reset_state()
		gear.spend(tool, gear.capacity(tool))
		arena.player.position = Vector3.ZERO
		var panel: Control = scenes.push_popup(&"Repair", {"equipment": gear, "tool": tool})
		await frames()
		expect(not paused, "%s leaves world simulation unpaused" % tool)
		var before: Vector3 = arena.player.position
		Input.action_press("move_right")
		for tick in range(6):
			arena.player.step(1.0 / 30.0, Vector3(10, 0, 0))
		Input.action_release("move_right")
		expect(arena.player.position.x > before.x, "%s player movement remains available behind repair" % tool)
		expect(panel.panel.get_theme_stylebox("panel") is StyleBoxEmpty, "%s has no opaque panel" % tool)
		expect(panel.sub_viewport.transparent_bg, "%s model viewport has alpha" % tool)
		expect(panel.panel.size.x > panel.size.x * 0.9, "%s repair spans viewport width" % tool)
		expect(panel.board.size.y > panel.size.y * 0.65, "%s tool uses most screen height" % tool)
		for dims: Vector2i in [Vector2i(1280, 800), Vector2i(960, 600), Vector2i(640, 480), Vector2i(1440, 720)]:
			root.size = dims
			await frames()
			var canvas: Vector2 = panel.BOARD * panel._board_scale()
			expect(panel.viewport_container.size.is_equal_approx(canvas), "%s projection matches target canvas at %s" % [tool, dims])
			expect(panel.viewport_container.position.is_equal_approx(panel._board_offset()), "%s projection matches target offset at %s" % [tool, dims])
			expect(root.get_visible_rect().encloses(panel.panel.get_global_rect()), "%s repair stays on screen at %s: visible %s panel %s" % [tool, dims, root.get_visible_rect(), panel.panel.get_global_rect()])
		root.size = Vector2i(1280, 800)
		await frames()
		# Exercise actual GUI coordinates for an angular gesture, then checkpoint resume.
		gesture(panel)
		expect(gear.stage(tool) == 1, "%s fullscreen pointer spin saves first checkpoint" % tool)
		if DisplayServer.get_name() != "headless":
			await frames()
			expect(root.get_texture().get_image().save_png(OUT + "/" + String(tool) + ".png") == OK, "%s live world capture saved" % tool)
		var release := InputEventKey.new()
		release.physical_keycode = KEY_E
		release.keycode = KEY_E
		release.pressed = false
		root.push_input(release, true)
		await frames()
		expect(scenes.has_popup(&"Repair") and gear.stage(tool) == 1, "%s release E keeps repair open" % tool)
		var toggle_close := InputEventKey.new()
		toggle_close.physical_keycode = KEY_E
		toggle_close.keycode = KEY_E
		toggle_close.pressed = true
		root.push_input(toggle_close, true)
		await frames()
		expect(not scenes.has_popup(&"Repair") and gear.stage(tool) == 1, "%s pressing E toggles repair closed and retains checkpoint" % tool)
		panel = scenes.push_popup(&"Repair", {"equipment": gear, "tool": tool})
		await frames()
		expect(panel.active_op_index == 1, "%s resumes next operation" % tool)
		if panel.active_kind == &"connect":
			connect_pair(panel, 0)
			connect_pair(panel, 1)
		else:
			gesture(panel)
		expect(gear.stage(tool) == 2, "%s second operation restores half capacity: %s" % [tool, panel.feedback.text])
		if panel.active_kind == &"connect":
			connect_pair(panel, 0)
			expect(gear.stage(tool) == 3, "%s first final socket pair saves third checkpoint" % tool)
			connect_pair(panel, 1)
		else:
			gesture(panel)
		await frames()
		expect(gear.is_full(tool) and gear.repairing == &"" and scenes.has_popup(&"Repair") and panel.progress.text.contains("Ready"), "%s full GUI gesture sequence completes to Ready state" % tool)
		scenes.close_popup(&"Repair")
		await frames()
	arena.queue_free()
	await frames()
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
