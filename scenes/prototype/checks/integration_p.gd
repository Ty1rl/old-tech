extends SceneTree
## Real room/navigation and repair/carousel contracts after all Wave A commits.
var checks := 0
var failures: Array[String] = []
var room_metrics: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("FAIL: " + description)

func settle(count: int = 4) -> void:
	for i in range(count):
		await process_frame
		await physics_frame

func run() -> void:
	create_timer(35, true).timeout.connect(func():
		failures.append("Integrated room/repair watchdog")
		finish())
	var state := root.get_node("GameState")
	var manager := root.get_node("SceneManager")
	var saved: Dictionary = state.preferences()
	var old_size := root.size
	state.set_setting("fullscreen", false)
	state.set_setting("tutorial", false)
	var arena: Node3D = load("res://scenes/prototype/campaign.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await settle()
	arena.set_physics_process(false)
	expect(arena.get_node("LessonDemo") is LessonDemo and arena.get_node("RewindLesson") is RewindLesson,
		"Campaign mounts both authored demonstration components")
	expect(arena.get_node("Overlay/Tutorial/Card") is PanelContainer,
		"Campaign instantiates the authored tutorial hierarchy")
	for room_index in range(4):
		arena.debug_start(room_index, 0)
		arena.director.clear()
		var nav: ExhibitNavigation = arena.director.navigation
		nav.sync_region()
		for i in range(120):
			await physics_frame
			if nav.ready_for(.65) and nav.ready_for(3.6):
				break
		expect(nav.ready_for(.65) and nav.ready_for(3.6),
			"Room %d publishes native small and full-pattern clearance maps" % room_index)
		var active_regions := 0
		for region: NavigationRegion3D in get_nodes_in_group("museum_navigation"):
			if region.enabled:
				active_regions += 1
		expect(active_regions == 1, "Room %d has exactly one active authored navigation source" % room_index)
		var enemy: CombatEnemy = arena.director.spawn(&"blue", Vector3(0, 0, -10))
		var start := enemy.position
		var clear := true
		for i in range(90):
			arena.director.step(.05, arena.player)
			clear = clear and not enemy.overlaps_cover()
			await physics_frame
		expect(clear and enemy.position.distance_to(start) > .5,
			"Room %d real enemy advances around partner exhibits without cover penetration" % room_index)
		room_metrics.append({"room": room_index, "distance": enemy.position.distance_to(start),
			"clear": clear, "polygons": nav.polygon_counts.duplicate()})
		arena.director.clear()
	await settle()
	arena.debug_start(3, 0)
	arena.director.clear()
	var guard: CombatEnemy = arena.director.spawn(&"side_guard", Vector3(0, 0, -10))
	expect(not guard.part_visual.instruction.visible, "Real creature teaching captions default to quiet")
	guard.part_visual.set_instruction_visible(true)
	expect(guard.part_visual.instruction.text == "Cut blue / Heat orange",
		"Guard caption describes the actual available opening routes")
	var cable: Array[Vector3] = guard.cable_world_points()
	guard.receive_attack(&"ring", 36, cable[0], {"segment_start": cable[0], "segment_end": cable[1], "radius": .1})
	expect(guard.part_visual.instruction.text == "Charge yellow",
		"Real cut changes the creature caption to its yellow finisher")
	guard.part_visual.set_instruction_visible(false)
	expect(not guard.part_visual.instruction.visible, "Completed teaching can hide real creature captions")
	arena.director.clear()
	arena.equipment.spend(&"ring", 12)
	arena.equipment.spend(&"beam", 40)
	arena.equipment.spend(&"cone", 25)
	arena.weapons.select_tool(2)
	expect(arena._open_smart_repair(), "Real arena opens mobile repair on its equipped tool")
	await settle()
	var repair: WeaponRepair = manager.get_popup(&"Repair")
	if repair != null:
		expect(repair.carousel.selected == &"beam" and repair.condition_view == repair.carousel.condition,
			"Selected condition and actual repair model share the mounted carousel")
		expect(repair.carousel.left.tool == &"ring" and repair.carousel.right.tool == &"cone",
			"Real acquired loadout supplies the two distinct side models")
		for size in [Vector2i(1280, 800), Vector2i(640, 360)]:
			root.size = size
			await settle(8)
			var region := repair.get_model_region()
			expect(repair.board.get_global_rect().encloses(region),
				"Visible model envelope uses viewport coordinates at %s" % str(size))
			var arc: Dictionary = repair.condition_view.arc_geometry()
			var center: Vector2 = repair.condition_view.get_global_transform_with_canvas() * arc.center
			expect(center.distance_to(region.get_center()) < 1,
				"Mounted condition arc stays centered on the selected model at %s" % str(size))
			expect(root.get_visible_rect().encloses(repair.carousel.left.get_global_rect())
				and root.get_visible_rect().encloses(repair.carousel.right.get_global_rect()),
				"Both neighbor previews remain on screen at %s" % str(size))
		repair.carousel.left.hit_area.pressed.emit()
		await settle()
		expect(repair.tool == &"ring" and arena.weapons.selected_tool == 1 and repair.carousel.selected == &"ring",
			"Side click switches the actual equipped weapon and the active repair session together")
		var before := repair.get_model_region()
		repair.dragging = true
		repair._sync_tool_canvas()
		expect(before == repair.get_model_region(), "Active gesture does not shift after carousel composition")
		repair.dragging = false
		manager.close_popup(&"Repair")
	await settle()
	# A sustained burst includes the real recurring pulse costs, not just capacity.
	arena.equipment.reset_state()
	arena.weapons.bellows.press(Vector3.ZERO, Vector3.FORWARD)
	for i in range(600):
		arena.weapons.bellows.step(1.0/60, 1.0/60, Vector3.ZERO, Vector3.ZERO, [])
	expect(arena.equipment.condition(&"cone") > .6,
		"Orange retains over 60 percent after ten real seconds including knockback-pulse wear")
	arena.weapons.bellows.release()
	var flash: FocusedFlash = arena.weapons.flash
	flash.reset_state()
	flash.press()
	flash.release(Vector3.ZERO, Vector3(0, 0, -20), Vector3.ZERO)
	flash.step(.18, .1, [], Vector3.ZERO)
	expect(flash.pulses.size() == 1 and absf(flash.pulses[0].pos.z) >= 7.9,
		"Yellow travels quickly using world delta")
	flash.press()
	expect(flash.charging, "Yellow accepts a follow-up shot after 180ms")
	flash.cancel_input()
	await create_timer(.1).timeout
	arena.feedback.reset_state()
	arena.queue_free()
	await settle()
	await create_timer(.3).timeout
	root.size = old_size
	for key in saved:
		state.set_setting(key, saved[key])
	finish()

func finish() -> void:
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks,
		"failures": failures, "rooms": room_metrics}))
	quit(0 if failures.is_empty() else 1)
