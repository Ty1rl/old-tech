extends SceneTree
var Tutorial: Script
var failures: Array[String] = []
var checks := 0
var resume_count := 0
var setting_events := 0
var restart_count := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func settle(frames: int = 3) -> void:
	for i in range(frames):
		await process_frame

func run() -> void:
	Tutorial = load("res://scenes/ui/tutorial.gd")
	create_timer(15, true).timeout.connect(func():
		failures.append("UI check watchdog expired")
		print(JSON.stringify({"status": "failed", "checks": checks, "failures": failures}))
		quit(1))
	var state = root.get_node("GameState")
	var scenes = root.get_node("SceneManager")
	var saved: Dictionary = state.preferences()
	var original_size := root.size
	var original_fade: float = scenes.fade_duration
	scenes.fade_duration = 0
	state.settings_changed.connect(func(_values): setting_events += 1)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	state.open_menu()
	await settle()
	expect(scenes.play_key() == &"Prototype", "Missing campaign safely chooses sandbox")
	expect(scenes.play_key(true) == &"Prototype", "Explicit sandbox path stays available")
	for i in range(3):
		var settings: Control = scenes.push_popup(&"Settings")
		await settle()
		expect(settings != null and scenes.has_popup(&"Settings"), "Settings opens from menu")
		expect(state.is_in_menu() and not paused, "Menu settings preserves menu state")
		expect(scenes.push_popup(&"Settings") == null, "Duplicate settings popup refused")
		settings.widgets.sound.button_pressed = false
		settings.widgets.volume.value = 37
		settings.widgets.hud.select(2)
		settings.widgets.hud.item_selected.emit(2)
		expect(not state.preferences().sound and is_equal_approx(state.preferences().volume, 0.37), "Settings controls apply actual values")
		expect(AudioServer.is_bus_mute(0) and absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.37)) < 0.01, "Master bus sound and volume applied")
		scenes.close_popup(&"Settings")
		await settle()
		expect(state.is_in_menu() and not scenes.has_popup(), "Settings Back returns to menu without starting play")
	state.reload_preferences()
	expect(not state.preferences().sound and state.preferences().hud == 2 and is_equal_approx(state.preferences().volume, 0.37), "Audio, volume and HUD survive preference reload")
	state.set_setting("tutorial", false)
	state.set_setting("fullscreen", true)
	state.reload_preferences()
	expect(not state.preferences().tutorial and state.preferences().fullscreen, "Tutorial and fullscreen mode persist")
	state.set_setting("fullscreen", false)
	expect(setting_events > 0, "Live settings signal emitted")
	state.set_setting("tutorial", true)
	state.set_setting("sound", true)
	state.set_setting("hud", 1)
	var old_main := current_scene
	var arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	old_main.queue_free()
	await settle(8)
	expect(state.is_playing(), "Real baseline arena is runnable")
	state.set_setting("sound", false)
	state.set_setting("hud", 2)
	expect(arena.feedback.muted and arena.status_hud.readout_mode == 2, "Settings adapt existing arena audio and HUD live")
	arena.feedback.toggle_mute()
	arena.status_hud.cycle_readout()
	var external: Dictionary = state.preferences()
	expect(external.sound and external.hud == 0, "Existing M/F7 preferences flow back to settings")
	arena.weapons.select_tool(2)
	state.pause()
	await settle()
	expect(paused and scenes.has_popup(&"PauseMenu"), "Pause holds gameplay and opens menu")
	var settings: Control = scenes.push_popup(&"Settings")
	await settle()
	expect(not state.resume(), "Cannot resume underneath settings")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = Vector2(20, 20)
	mouse.pressed = true
	root.push_input(mouse)
	await settle()
	expect(not arena.weapons.beam_charging, "Settings mouse press cannot start attack in paused arena")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape)
	await settle()
	expect(not scenes.has_popup(&"Settings") and paused and state.is_paused(), "Escape from settings returns to original paused state")
	expect(scenes.has_popup(&"PauseMenu"), "Pause remains under closed settings")
	state.resume()
	await settle()
	mouse.pressed = false
	root.push_input(mouse)
	await settle()
	expect(not arena.weapons.beam_charging and arena.weapons.beam_cooldown <= 0, "Closing settings and resuming cannot fire a stale mouse release")
	var layer := CanvasLayer.new()
	layer.layer = 60
	root.add_child(layer)
	var tutorial = Tutorial.new()
	layer.add_child(tutorial)
	tutorial.setup(arena.player.camera)
	tutorial.resume_requested.connect(func(_id): resume_count += 1)
	var enemy = arena.director.spawn(&"blue", Vector3(0, 0, -5))
	var targets: Array[Vector3] = enemy.cable_world_points()
	tutorial.show_known_lesson(&"cut", targets)
	tutorial._process(0.1)
	expect(tutorial.blocking and not paused, "Lesson blocks via contract without pausing UI tree")
	expect(tutorial.projected.size() == targets.size(), "Highlights use every actual world position")
	expect(tutorial.projected[0].distance_to(arena.player.camera.unproject_position(targets[0])) < 0.1, "Highlight matches camera projection")
	expect(not tutorial.show_known_lesson(&"heat", targets) and tutorial.active_id == &"cut", "New context cannot replace a pending lesson")
	tutorial.complete_lesson(&"cut")
	expect(not tutorial.is_learned(&"cut"), "Text alone cannot complete a lesson")
	var first: Vector2 = tutorial.projected[0]
	arena.player.camera.position.x += 1
	arena.player.camera.force_update_transform()
	arena.player.camera.reset_physics_interpolation()
	await settle()
	tutorial._process(0.1)
	expect(first.distance_to(tutorial.projected[0]) > 1, "Highlight follows camera movement")
	arena.player.camera.position.x -= 1
	tutorial.world_points[0] += Vector3.RIGHT * 2
	tutorial._process(0.1)
	expect(first.distance_to(tutorial.projected[0]) > 1, "Highlight follows changed target positions")
	tutorial.world_points.assign([arena.player.camera.global_position + arena.player.camera.global_basis.z * 4])
	tutorial._process(0.1)
	expect(tutorial.offscreen[0], "Behind-camera targets are marked offscreen")
	expect(tutorial.projected[0].y >= tutorial.size.y - 37, "Directly behind target uses viewport edge indicator")
	tutorial.world_points = targets
	tutorial.request_practice()
	tutorial.request_practice()
	expect(not tutorial.blocking and tutorial.practicing and resume_count == 1, "Practice resumes once and keeps success gate pending")
	expect(not tutorial.is_learned(&"cut"), "Crowd gate remains closed through practice")
	tutorial.complete_lesson(&"heat")
	expect(not tutorial.is_learned(&"heat") and tutorial.active_id == &"cut", "Unrelated success cannot complete active lesson")
	var midpoint: Vector3 = (targets[0] + targets[1]) * 0.5
	enemy.receive_attack(&"ring", 1, midpoint, {"segment_start": midpoint + Vector3.FORWARD, "segment_end": midpoint - Vector3.FORWARD, "radius": 0.1})
	expect(enemy.cable_cut, "Practice uses actual baseline cable-cut success")
	if enemy.cable_cut:
		tutorial.complete_lesson(&"cut")
	expect(tutorial.is_learned(&"cut") and not tutorial.visible, "Observed real success opens lesson gate")
	tutorial.show_known_lesson(&"cut", targets)
	expect(not tutorial.blocking and not tutorial.visible, "Learned lesson does not freeze again on spawn")
	tutorial.reset_run()
	expect(not tutorial.is_learned(&"cut"), "New run resets learned lessons")
	for id in Tutorial.LESSONS:
		tutorial.show_known_lesson(id, targets)
		expect(tutorial.blocking and tutorial.body_label.text.length() > 20 and not tutorial.ghost.is_empty(), "Ready-to-use copy and gesture: " + id)
		tutorial.reset_run()
	tutorial.show_known_lesson(&"rewind", targets)
	expect("injury" in tutorial.body_label.text and "Escape" in tutorial.body_label.text, "Rewind teaches injury recovery and cancellation")
	state.set_setting("tutorial", false)
	expect(not tutorial.blocking and not tutorial.visible and tutorial.is_learned(&"loop"), "Disabling tutorials releases active gate safely")
	state.set_setting("tutorial", true)
	root.size = Vector2i(640, 360)
	await settle()
	tutorial.show_known_lesson(&"cut", targets)
	await settle()
	expect(root.get_visible_rect().encloses(tutorial.card.get_global_rect()), "Tutorial card fits small viewport")
	tutorial.reset_run()
	state.pause()
	settings = scenes.push_popup(&"Settings")
	await settle()
	var panels := settings.find_children("*", "PanelContainer", true, false)
	expect(not panels.is_empty() and root.get_visible_rect().encloses(panels[0].get_global_rect()), "Settings panel fits small viewport with scrolling")
	var back: Button = settings.find_child("BackButton", true, false)
	back.grab_focus()
	await settle()
	expect(root.get_visible_rect().encloses(back.get_global_rect()), "Keyboard focus scrolls Settings Back into view in small window")
	scenes.close_popup(&"Settings")
	await settle()
	var restart_action := func(): restart_count += 1
	scenes.restart_room_requested.connect(restart_action)
	scenes.request_restart_room()
	expect(restart_count == 1 and paused, "Restart request is handed to campaign while held safely")
	scenes.restart_room_requested.disconnect(restart_action)
	for won in [false, true]:
		scenes.show_run_result(won)
		await settle()
		expect(state.is_game_over() and paused and scenes.has_popup(&"RunResult"), "Win/retry UI holds actions")
		scenes.push_popup(&"Settings")
		await settle()
		scenes.close_popup(&"Settings")
		await settle()
		expect(state.is_game_over() and paused and scenes.has_popup(&"RunResult"), "Result settings Back retains result state")
	scenes.clear_popups()
	state.start_game()
	for key in saved:
		state.set_setting(key, saved[key])
	root.size = original_size
	scenes.fade_duration = original_fade
	layer.queue_free()
	current_scene = null
	arena.queue_free()
	await settle()
	var legacy = load("res://scenes/game.tscn").instantiate()
	root.add_child(legacy)
	current_scene = legacy
	await settle()
	expect(legacy.get_node("Player") != null and scenes.SCENES.has(&"Game"), "Original Game scene and registered path remain runnable")
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
