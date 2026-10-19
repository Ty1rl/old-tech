extends SceneTree
const OUT := "/home/mattlongname/frankenstein/.daedalus-dev-state/game-jams/state/old-tech-jam-7/exports/round-k"

func _initialize() -> void:
	call_deferred("run")

func settle(frames: int = 5) -> void:
	for i in range(frames):
		await process_frame

func snap(name: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(OUT + "/" + name + ".png")
	assert(result == OK)
	print("Saved ", name)

func run() -> void:
	create_timer(35, true).timeout.connect(func(): push_error("UI capture watchdog expired"); quit(1))
	var state = root.get_node("GameState")
	var scenes = root.get_node("SceneManager")
	var saved: Dictionary = state.preferences()
	state.set_setting("tutorial", true)
	state.set_setting("fullscreen", true)
	await settle()
	assert(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "Fullscreen applies on private display")
	state.set_setting("fullscreen", false)
	await settle()
	assert(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "Windowed mode applies on private display")
	print("Fullscreen/windowed private display checks: 2 passed")
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	state.open_menu()
	await snap("main-menu")
	scenes.push_popup(&"Settings")
	await snap("settings")
	scenes.close_popup(&"Settings")
	await settle()
	main.queue_free()
	await settle()
	state.set_setting("hud", 2)
	var preview = load("res://scenes/tutorial_preview/preview.tscn").instantiate()
	root.add_child(preview)
	current_scene = preview
	await settle(40)
	await snap("cut-explanation")
	preview.tutorial.request_practice()
	await snap("cut-practice")
	state.pause()
	await snap("pause")
	scenes.push_popup(&"Settings")
	await snap("paused-settings")
	scenes.close_popup(&"Settings")
	await settle()
	state.resume()
	await settle()
	preview.tutorial.reset_run()
	var loop_targets: Array[Vector3] = []
	# The isolated baseline has no future loop unit. Four actual cable specimens
	# demonstrate projection, rather than drawing markers over empty floor.
	for point in [Vector3(-3, 0, -8), Vector3(3, 0, -8), Vector3(3, 0, -3), Vector3(-3, 0, -3)]:
		var support = preview.arena.director.spawn(&"blue", point)
		support.move_speed = 0
		support.contact_damage = 0
		var endpoints: Array[Vector3] = support.cable_world_points()
		loop_targets.append((endpoints[0] + endpoints[1]) * 0.5)
	preview.tutorial.show_known_lesson(&"loop", loop_targets)
	await snap("loop-explanation")
	preview.tutorial.reset_run()
	var rewind_targets: Array[Vector3] = [preview.arena.player.global_position + Vector3.UP * 0.5]
	preview.tutorial.show_known_lesson(&"rewind", rewind_targets)
	await snap("rewind-explanation")
	scenes.show_run_result(true)
	await snap("win")
	scenes.show_run_result(false)
	await snap("retry")
	scenes.clear_popups()
	state.start_game()
	root.size = Vector2i(640, 360)
	scenes.push_popup(&"Settings")
	await snap("settings-small")
	scenes.close_popup(&"Settings")
	await settle()
	preview.tutorial.reset_run()
	preview.arena.director.clear()
	preview.specimen = preview.arena.director.spawn(&"blue", Vector3(0, 0, -5))
	preview.specimen.move_speed = 0
	preview.specimen.contact_damage = 0
	preview.tutorial.show_known_lesson(&"cut", preview.specimen.cable_world_points())
	await snap("tutorial-small")
	for key in saved:
		state.set_setting(key, saved[key])
	print("Round K UI capture complete")
	quit(0)
