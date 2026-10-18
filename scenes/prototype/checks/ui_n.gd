extends SceneTree
## Real GUI input + actual time-core sessions. World fixtures deliberately have
## no health field: the HUD must only read the shared time authority.
class DisplayPlayer extends Node3D:
	var camera: Camera3D
class DisplayWeapon extends Node3D:
	var selected_tool := 1
	var available_tools: Array[int] = [1, 2, 3]
	var charge := 0.0
	func presentation_state() -> Dictionary:
		return {"charging": charge > 0, "charge": charge}
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func expect(value: bool, text: String) -> void:
	checks += 1
	if not value: failures.append(text)
func settle(count: int = 6) -> void:
	for i in range(count): await process_frame
func key(code: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = true; event.shift_pressed = shift
	root.push_input(event)
func run() -> void:
	create_timer(25, true).timeout.connect(func():
		failures.append("UI N watchdog expired")
		print(JSON.stringify({"status":"failed","checks":checks,"failures":failures})); quit(1))
	var scenes = root.get_node("SceneManager")
	var state = root.get_node("GameState")
	var saved: Dictionary = state.preferences()
	var old_size := root.size
	var old_developer: bool = scenes.developer_tools
	state.set_setting("fullscreen", false)
	var main = load("res://scenes/main.tscn").instantiate()
	var menu: Control = main.get_node("MainMenu")
	# Inspector edit survives _ready; authored children are never deleted/rebuilt.
	var authored_play: Button = menu.get_node("%PlayButton")
	authored_play.text = "NEW GAME · authored edit"
	root.add_child(main); current_scene = main; state.open_menu()
	await settle()
	expect(menu.play == authored_play and authored_play.text.ends_with("authored edit"), "Main menu preserves authored node identity and text edits")
	expect(root.gui_get_focus_owner() == authored_play, "New Game receives initial focus")
	key(KEY_TAB); await settle()
	expect(root.gui_get_focus_owner() == menu.get_node("%SettingsButton"), "Tab reaches Settings")
	key(KEY_TAB, true); await settle()
	expect(root.gui_get_focus_owner() == authored_play, "Shift Tab returns to New Game")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_DPAD_DOWN; pad.pressed = true
	root.push_input(pad); await settle()
	expect(root.gui_get_focus_owner() == menu.get_node("%SettingsButton"), "Controller D-pad reaches Settings")
	menu.get_node("%SettingsButton").pressed.emit(); await settle()
	var settings = scenes._popups.back().get_child(1)
	expect(root.gui_get_focus_owner() == settings.sound, "Scene-connected Settings button opens focused Sound control")
	settings.volume.value = 43
	settings.hud.select(0); settings.hud.item_selected.emit(0)
	settings.sound.button_pressed = not saved.sound
	state.reload_preferences()
	expect(is_equal_approx(state.preferences().volume, .43) and state.preferences().hud == 0 and state.preferences().sound != saved.sound, "Authored settings signals persist volume/readout/sound")
	settings.get_node("%BackButton").pressed.emit(); await settle()
	expect(not scenes.has_popup() and state.is_in_menu(), "Authored Back closes only Settings")
	settings = scenes.push_popup(&"Settings"); scenes.close_popup(&"Settings")
	settings = scenes.push_popup(&"Settings"); await settle(10)
	expect(root.gui_get_focus_owner() == settings.sound, "Rapid popup replacement safely focuses the new Settings")
	key(KEY_TAB); await settle()
	expect(root.gui_get_focus_owner() == settings.fullscreen, "Deferred focus does not steal deliberate navigation")
	root.size = Vector2i(640, 360); await settle(12)
	settings.get_node("%BackButton").grab_focus(); await settle()
	expect(root.get_visible_rect().encloses(settings.panel.get_global_rect()), "Authored settings panel fits small viewport")
	expect(root.get_visible_rect().encloses(settings.get_node("%Title").get_global_rect()), "Pinned title stays visible after small-window scrolling")
	expect(settings.scroll.get_global_rect().encloses(settings.get_node("%BackButton").get_global_rect()), "Small-window Back scrolls into its clip")
	key(KEY_ESCAPE); await settle()
	for i in range(4):
		settings = scenes.push_popup(&"Settings"); settings.resized.emit(); scenes.close_popup(&"Settings")
	await settle(8)
	expect(not scenes.has_popup(), "Immediate resize/close drains callbacks safely")
	scenes.developer_tools = false
	var blocked = scenes.push_popup(&"Developer"); await settle()
	expect(not is_instance_valid(blocked) and not scenes.has_popup(), "Direct developer entry respects the shared gate")
	scenes.developer_tools = true
	var picker = scenes.push_popup(&"Developer"); await settle(12)
	expect(picker.room_picker.item_count == 4 and root.get_visible_rect().encloses(picker.panel.get_global_rect()), "Authored encounter scene exposes rooms and fits small window")
	var bosses := 0
	for room_index in range(4):
		picker.room_picker.select(room_index); picker.room_picker.item_selected.emit(room_index)
		for wave in range(picker.encounter_picker.item_count):
			picker.encounter_picker.select(wave); picker.encounter_picker.item_selected.emit(wave)
			if not picker.phase_picker.disabled:
				bosses += 1
				expect(picker.phase_picker.item_count in [4, 5], "Authored selector signals populate valid boss phases")
	expect(bosses == 3, "Encounter selector retains all three bosses")
	scenes.close_popup(&"Developer"); await settle()
	state.start_game(); state.pause(); await settle()
	var pause = scenes._popups.back().get_child(1)
	expect(root.gui_get_focus_owner() == pause.resume_button and paused, "Authored pause opens with Resume focus")
	pause.get_node("%SettingsButton").pressed.emit(); await settle()
	scenes.close_popup(&"Settings"); await settle(10)
	expect(paused and pause.is_ancestor_of(root.gui_get_focus_owner()), "Nested Settings returns focus while keeping pause")
	pause.resume_button.pressed.emit(); await settle()
	expect(not paused and not scenes.has_popup(), "Authored Resume signal resumes once")
	for won in [false, true]:
		scenes.show_run_result(won); await settle()
		var result = scenes._popups.back().get_child(1)
		expect(result.retry.text == ("Play again" if won else "Retry room") and result.title.text == ("The museum is quiet" if won else "Another chance"), "Result setup updates named authored text")
		result.get_node("%SettingsButton").pressed.emit(); await settle()
		scenes.close_popup(&"Settings"); await settle(10)
		expect(paused and result.is_ancestor_of(root.gui_get_focus_owner()), "Result Settings closes without resuming or losing focus")
		scenes.clear_popups(); state.start_game(); await settle()
	root.size = Vector2i(1280, 800); await settle()
	main.queue_free(); current_scene = null; await settle()
	var world := Node3D.new(); root.add_child(world)
	var player := DisplayPlayer.new(); world.add_child(player)
	player.camera = Camera3D.new(); world.add_child(player.camera)
	player.camera.position = Vector3(0, 10, 12); player.camera.look_at(Vector3.ZERO); player.camera.current = true
	var weapons := DisplayWeapon.new(); world.add_child(weapons)
	var equipment = load("res://scenes/prototype/equipment.gd").new()
	var core = load("res://scenes/time/time_core.tscn").instantiate(); root.add_child(core)
	var controller: TimeController = core.get_node("TimeController"); controller.auto_advance = false; controller.set_physics_process(false)
	var session: EmergencyRewind = core.get_node("EmergencyRewind")
	var hud = load("res://scenes/prototype/status_hud.gd").new(); root.add_child(hud)
	hud.bind_time_controller(controller); hud.bind_time_controller(controller)
	hud.update_status(player, weapons, equipment); await settle()
	expect(hud.time_controller == controller and controller.hit_taken.get_connections().size() == 1, "HUD binds one controller idempotently without duplicated hit signals")
	expect(hud.available_tools == [1, 2, 3] and hud.fractions.size() == 3 and hud.checkpoints == 4, "HUD has three tools and actual quarter-checkpoint segmentation")
	equipment.spend(&"beam", equipment.capacity(&"beam") * .4); weapons.selected_tool = 2
	hud.update_status(player, weapons, equipment)
	expect(is_equal_approx(hud.fractions[1], .6) and "60%" in hud.caption, "HUD reads real equipment condition")
	equipment.begin_repair(&"beam"); controller.try_spend(30); hud.update_status(player, weapons, equipment)
	expect(hud.visible and hud.repairing and hud.time_controller.meter == 70 and hud.caption.contains("E close"), "HUD remains visible during repair and reads the same spent meter")
	await settle()
	hud.readout_mode = 2
	expect(hud._repair_overlay.visible and hud._repair_overlay.layer > 100, "Repair meter stays above popup art even with optional HUD numbers hidden")
	paused = true; await settle()
	expect(not hud._repair_overlay.visible, "Pause hides the floating repair readout")
	paused = false
	equipment.end_repair(); weapons.available_tools.assign([1]); hud.update_status(player, weapons, equipment)
	expect(hud.available_tools == [1], "Unowned upper arcs are omitted")
	weapons.charge = .7; hud.update_status(player, weapons, equipment)
	expect(hud.charging and is_equal_approx(hud.charge_fraction, .7), "Charge cursor consumes public presentation_state")
	player.position.x = 2; player.reset_physics_interpolation(); await settle()
	var projected: Vector2 = player.camera.unproject_position(player.get_global_transform_interpolated() * Vector3(0, .5, 0))
	expect(hud.center.distance_to(projected) < 1, "Gauges track interpolated perspective projection")
	var view = load("res://scenes/ui/emergency_view.tscn").instantiate(); root.add_child(view)
	view.bind_emergency_rewind(session); view.bind_emergency_rewind(session)
	expect(not view.visible and session.started.get_connections().size() == 1, "Emergency binding is idempotent and hidden before depletion")
	session.history = ReplayHistory.from_settings(controller.settings)
	session.history.seed_checkpoint({"position": Vector3.ZERO})
	session.capture_present = func() -> Dictionary: return {"position": Vector3(2,0,0)}
	controller.apply_hit(1000); await settle()
	expect(controller.emergency_active and view.visible and session.choice_count == 2 and controller.charges_remaining == 2, "Real hit depletion opens checkpoint-capable view and spends one charge")
	expect(not hud.key_hint.visible, "Emergency suppresses ordinary combat hints")
	expect(view.charges.text.contains("1 rewind spent · 2 left") and view.choice.text.contains("NOW"), "Emergency text explains spent charge and NOW")
	# The view must never consume these itself: arena owns input priority.
	key(KEY_ENTER); await settle()
	expect(session.active and controller.charges_remaining == 2, "View has no competing Enter confirmation handler")
	session.step_selection(1); await settle()
	expect(view.choice.text == "ROOM CHECKPOINT" and controller.charges_remaining == 2, "Checkpoint preview updates text without refund")
	await create_timer(.15).timeout
	expect(session.active and controller.meter == 0, "Emergency waits without a browse countdown or meter drain")
	paused = true; session.confirm(); await settle()
	expect(not view.visible and not session.active and controller.charges_remaining == 2 and controller.meter == controller.settings.recovery_floor, "Confirmation while tree paused closes view, restores floor, retains spent charge")
	paused = false
	controller.begin_attempt(); controller.apply_hit(1000); await settle()
	controller.begin_attempt(); await settle()
	expect(not view.visible and not session.active, "New room attempt abandons old emergency view")
	session.history = null; controller.apply_hit(1000); await settle()
	expect(session.choice_count == 1 and view.choice.text.contains("no earlier moments"), "Empty history still explains safe NOW recovery")
	session.confirm(); await settle()
	controller.begin_attempt()
	session.history = ReplayHistory.from_settings(controller.settings)
	for i in range(50): session.history.record(.1, func() -> Dictionary: return {"index": 50})
	controller.apply_hit(1000); session.step_selection(25); await settle()
	expect(view.choice.text.begins_with("−") and session.choice_age(session.selected_index) > 2, "Recorded-history selection displays the actual age")
	var count_before := session.history.snapshot_count
	session.confirm(); await settle()
	expect(session.history.snapshot_count < count_before and controller.charges_remaining == 2 and not view.visible, "Past confirmation trims history without refunding a charge")
	controller.begin_attempt(); controller.apply_hit(1000); await settle()
	view.queue_free(); await settle()
	expect(session.started.get_connections().is_empty() and session.active, "Freeing emergency view disconnects display signals without mutating the session")
	view = load("res://scenes/ui/emergency_view.tscn").instantiate(); root.add_child(view); view.bind_emergency_rewind(session); await settle()
	expect(view.visible, "Rebinding an active emergency refreshes immediately")
	var samples: Array[int] = []
	for batch in range(5):
		var started := Time.get_ticks_usec()
		for i in range(3000):
			hud.update_status(player, weapons, equipment)
			hud._process(0)
		samples.append(Time.get_ticks_usec() - started)
	print(JSON.stringify({"profile":"hud update_status + projection, 3000 calls/batch; drawing excluded", "microseconds":samples}))
	view.bind_emergency_rewind(null); hud.bind_time_controller(null)
	expect(not view.visible and session.started.get_connections().is_empty() and controller.hit_taken.get_connections().is_empty(), "Unbind releases signal connections")
	hud.queue_free(); view.queue_free(); core.queue_free(); world.queue_free(); await settle()
	for setting in saved: state.set_setting(setting, saved[setting])
	root.size = old_size; scenes.developer_tools = old_developer
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
