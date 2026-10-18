extends SceneTree

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func run() -> void:
	var packed := load("res://scenes/prototype/arena.tscn") as PackedScene
	var arena = packed.instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	var state = root.get_node("GameState")
	var scenes = root.get_node("SceneManager")
	expect(state.is_playing() and not paused, "Direct arena launch enters playing state")
	expect(arena.player.camera.current, "Prototype camera is current")
	expect(arena.player.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "Top-down camera uses perspective")
	var origin: Vector3 = arena.player.position
	Input.action_press("move_right")
	for frame in range(8):
		await physics_frame
	Input.action_release("move_right")
	expect(arena.player.position.x > origin.x + 0.1, "WASD input moves the inherited player")
	var popup: Node = scenes.push_popup(&"PauseMenu")
	expect(popup != null and not paused, "Popup can open without pausing world simulation")
	scenes.close_popup(&"PauseMenu")
	await process_frame
	state.pause()
	expect(paused and scenes.has_popup(&"PauseMenu"), "Existing pause flow opens popup and pauses")
	state.resume()
	await process_frame
	expect(not paused and not scenes.has_popup(), "Existing resume clears pause popup")
	arena.player.take_damage(12.0)
	expect(arena.player.health < 100.0, "Player receives contact damage")
	arena.reset_arena()
	expect(arena.player.health == 100.0 and arena.player.velocity == Vector3.ZERO, "Reset restores player health and clears motion")
	expect(arena.player.world_scale == 1.0, "Reset restores normal world time")
	expect(Engine.time_scale == 1.0, "Prototype leaves engine clock unscaled")
	# Exercise visibility through the real hotkey, and restore the tester's preference.
	var initial_mode: int = arena.status_hud.readout_mode
	var toggle := InputEventKey.new()
	toggle.physical_keycode = KEY_F7
	toggle.pressed = true
	var modes: Dictionary = {}
	for i in range(3):
		arena._unhandled_input(toggle)
		modes[arena.status_hud.readout_mode] = true
		expect(arena.status_hud.visible, "F7 retains the player gauges")
		if arena.status_hud.readout_mode == 2:
			expect(not arena.hud.visible and not arena.slow_bar.visible, "Hidden readout hides numbers and old clock bar")
		elif arena.status_hud.readout_mode == 1:
			expect(arena.hud.visible and arena.hud.modulate.a < 0.3, "Dim readout retains faint debugging information")
	expect(modes.size() == 3 and arena.status_hud.readout_mode == initial_mode, "F7 cycles all modes and restores initial choice")
	var settings := ConfigFile.new()
	settings.load(arena.StatusHud.READOUT_FILE)
	expect(int(settings.get_value("hud", "readout", -1)) == initial_mode, "Readout choice is saved across launches")
	arena.equipment.spend(&"ring", arena.equipment.capacity(&"ring") * 0.75)
	arena.weapons.select_tool(3)
	arena._update_hud()
	expect(is_equal_approx(arena.status_hud.fractions[0], 0.25) and arena.status_hud.selected == 2,
		"Player gauges reflect real wear and current tool")
	expect(arena.status_hud.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Player gauges let weapon mouse input pass through")
	expect(arena.status_hud.key_hint.get_global_rect().end.y <= root.get_visible_rect().end.y
		and arena.status_hud.key_hint.global_position.y >= 0,
		"Readout hotkey hint stays inside the viewport")
	arena.player.position.x += 5
	arena.player.reset_physics_interpolation()
	arena.status_hud._process(0.0)
	expect(absf(arena.status_hud.center.x - root.get_visible_rect().size.x * 0.5) < 0.01,
		"Gauges stay centered on the rendered player when camera and player jump together")
	arena.reset_arena()
	# Follow the actual pause-menu exit and Play button, avoiding the legacy Game scene.
	var old_fade: float = scenes.fade_duration
	scenes.fade_duration = 0.0
	state.pause()
	var pause_menu: Control = scenes._popups.back().get_child(1)
	pause_menu._on_exit_button_pressed()
	for frame in range(12):
		await process_frame
	expect(current_scene.scene_file_path == "res://scenes/main.tscn" and state.is_in_menu(),
		"Pause-menu exit returns to main menu")
	current_scene.get_node("MainMenu").get_node("%PlayButton").pressed.emit()
	for frame in range(12):
		await process_frame
	expect(current_scene.scene_file_path == "res://scenes/prototype/campaign.tscn" and state.is_playing(),
		"Main-menu Play launches the taught museum campaign")
	scenes.fade_duration = old_fade
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
