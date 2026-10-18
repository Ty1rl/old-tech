extends SceneTree
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func expect(value: bool, text: String) -> void:
	checks += 1
	if not value: failures.append(text)
func settle(count: int = 4) -> void:
	for i in range(count): await process_frame
func key(code: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = true; event.shift_pressed = shift
	root.push_input(event)
func run() -> void:
	create_timer(25,true).timeout.connect(func():
		failures.append("UI M watchdog expired")
		print(JSON.stringify({"status":"failed","checks":checks,"failures":failures}));quit(1))
	var scenes = root.get_node("SceneManager")
	var state = root.get_node("GameState")
	var saved: Dictionary = state.preferences()
	var developer: bool = scenes.developer_tools
	var old_size := root.size
	var old_fade: float = scenes.fade_duration
	scenes.fade_duration = .01
	var menu = load("res://scenes/main.tscn").instantiate()
	root.add_child(menu);current_scene = menu;state.open_menu()
	await settle()
	var view: Control = menu.get_node("MainMenu")
	var play: Button = view.get_node("%PlayButton")
	expect(root.gui_get_focus_owner()==play,"New Game has initial keyboard focus")
	key(KEY_TAB);await settle()
	expect(root.gui_get_focus_owner()==view.get_node("%SettingsButton"),"Tab advances to Settings")
	key(KEY_TAB,true);await settle()
	expect(root.gui_get_focus_owner()==play,"Shift Tab returns to New Game")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_DPAD_DOWN;pad.pressed = true
	expect(pad.is_action_pressed("ui_down"),"Built-in controller D-pad navigation mapping exists")
	root.push_input(pad);await settle()
	expect(root.gui_get_focus_owner()==view.get_node("%SettingsButton"),"Controller D-pad moves to Settings")
	# Close/open before the original deferred focus/layout callbacks can finish.
	var settings = scenes.push_popup(&"Settings")
	scenes.close_popup(&"Settings")
	settings = scenes.push_popup(&"Settings")
	await settle(8)
	expect(settings.is_ancestor_of(root.gui_get_focus_owner()),"Rapid popup replacement keeps focus in the new settings")
	expect(root.gui_get_focus_owner()==settings.widgets.sound,"Replacement settings starts on Sound")
	key(KEY_TAB);await settle(6)
	expect(root.gui_get_focus_owner()==settings.widgets.fullscreen,"Deferred focus reconciliation preserves deliberate navigation inside Settings")
	settings.widgets.volume.value = 43
	settings.widgets.hud.select(1);settings.widgets.hud.item_selected.emit(1)
	settings.widgets.sound.button_pressed = not saved.sound
	state.reload_preferences()
	expect(is_equal_approx(state.preferences().volume,.43) and state.preferences().hud==1 and state.preferences().sound!=saved.sound,"Settings controls persist volume, HUD and sound through reload")
	scenes.close_popup(&"Settings");await settle()
	expect(state.is_in_menu() and not paused,"Settings returns to menu without starting play")
	root.size=Vector2i(640,360);await settle()
	var small_font: int = play.get_theme_font_size("font_size")
	expect(small_font>=30,"Small-window menu uses readable scaled controls")
	for i in range(7): key(KEY_TAB);await settle(1)
	var focused := root.gui_get_focus_owner()
	expect(focused!=null and root.get_visible_rect().encloses(focused.get_global_rect()),"Keyboard traversal scrolls the focused small-window button into view")
	settings=scenes.push_popup(&"Settings");await settle()
	var back: Button=settings.find_child("BackButton",true,false)
	back.grab_focus();await settle()
	expect(root.get_visible_rect().encloses(back.get_global_rect()),"Settings Back is reachable in the small viewport")
	var title_visible:=false
	for label in settings.find_children("*","Label",true,false):
		if label.text=="Settings":title_visible=root.get_visible_rect().encloses(label.get_global_rect())
	expect(title_visible,"Settings title stays visible when keyboard focus scrolls to Back")
	key(KEY_ESCAPE);await settle()
	expect(not scenes.has_popup() and state.is_in_menu(),"Escape closes only settings")
	# Exit immediately after resize: no deferred work may dereference this menu.
	for i in range(8):
		settings=scenes.push_popup(&"Settings")
		settings.resized.emit()
		scenes.close_popup(&"Settings")
	await settle(8)
	expect(not scenes.has_popup(),"Repeated immediate-close callbacks finish cleanly")
	scenes.developer_tools=false
	var blocked=scenes.push_popup(&"Developer")
	await settle()
	expect(not is_instance_valid(blocked) and not scenes.has_popup(),"One developer switch blocks a directly opened encounter picker")
	scenes.developer_tools=true
	root.size=Vector2i(1280,800);await settle()
	var picker=scenes.push_popup(&"Developer");await settle()
	root.size=Vector2i(640,360);await settle()
	var picker_panel=picker.find_children("*","PanelContainer",true,false)[0]
	expect(root.get_visible_rect().encloses(picker_panel.get_global_rect()),"Encounter picker fits small viewport")
	var picker_scroll: ScrollContainer=picker.room_picker.get_parent().get_parent()
	expect(picker_scroll.get_global_rect().encloses(picker.room_picker.get_global_rect()),"Focused room selector stays inside its scroll clip after header layout")
	root.size=Vector2i(1280,800);await settle()
	expect(picker.room_picker.item_count==4,"Picker exposes the four current rooms")
	var boss_count:=0
	for room_index in range(4):
		picker.room_picker.select(room_index);picker._update_encounters()
		for wave in range(picker.encounter_picker.item_count):
			picker.encounter_picker.select(wave);picker._update_phases()
			if not picker.phase_picker.disabled:
				boss_count+=1
				expect(picker.phase_picker.item_count in [4,5],"Boss phase choices stay within the declared phase count")
			else:
				expect(picker.phase_picker.item_count==1 and picker.phase_picker.selected==0,"Non-boss has only the normal phase")
	expect(boss_count==3,"All three bosses remain available")
	picker.room_picker.select(3);picker._update_encounters()
	picker.encounter_picker.select(picker.encounter_picker.item_count-1);picker._update_phases();picker.phase_picker.select(3)
	picker._launch()
	for i in range(30):
		await create_timer(.03).timeout
		if not scenes.is_transitioning():break
	var arena=current_scene
	expect(arena.has_method("debug_start") and arena.room_index==3,"Picker actually loads the chosen campaign checkpoint")
	arena.set_physics_process(false)
	expect(arena.weapons.available_tools==[2,3,1,4],"Selected late checkpoint receives the exact acquired equipment")
	expect(arena.director.enemies.size()==1 and arena.director.enemies[0].phase==2,"Selected phase reaches a real final boss")
	var hud=arena.status_hud
	hud.update_status(arena.player,arena.weapons,arena.equipment)
	expect(hud.fractions.size()==4 and hud.health_fraction==1,"Four condition gauges and ivory health retain real values")
	arena.player.take_damage(20);hud.update_status(arena.player,arena.weapons,arena.equipment)
	expect(is_equal_approx(hud.health_fraction,.8) and hud.damage_bright>0,"Ivory health arc and damage pulse follow an actual player hit")
	arena.director.clear()
	arena.equipment.reset_state();arena.weapons.select_tool(2)
	hud.update_status(arena.player,arena.weapons,arena.equipment)
	expect("full" in hud.caption,"Full selected gear has a calm explicit status")
	arena.equipment.spend(&"beam",arena.equipment.capacity(&"beam")*.4)
	hud.update_status(arena.player,arena.weapons,arena.equipment)
	expect("60%" in hud.caption and "E toggle" in hud.caption,"Damaged gear communicates condition and E toggle repair")
	arena.equipment.begin_repair(&"beam")
	hud.update_status(arena.player,arena.weapons,arena.equipment)
	expect("E close" in hud.caption and not "automatic" in hud.caption,"Repair caption describes closing rather than hold/release")
	arena.equipment.end_repair()
	arena.weapons.available_tools.assign([2]);arena.weapons.selected_tool=1
	hud.update_status(arena.player,arena.weapons,arena.equipment)
	expect("locked" in hud.caption,"Unavailable selection is described as locked rather than broken")
	arena.weapons.available_tools.clear();hud.update_status(arena.player,arena.weapons,arena.equipment)
	expect(hud.caption=="Find the illuminated exhibit","No gear gives only the pickup prompt")
	arena.weapons.available_tools.assign([2,3,1,4]);arena.weapons.select_tool(2)
	arena.weapons.beam_charging=true;arena.weapons.beam_charge=.7
	hud.update_status(arena.player,arena.weapons,arena.equipment)
	expect(hud.charging and is_equal_approx(hud.charge_fraction,.7),"Cursor charge reads real weapon charge")
	arena.weapons.beam_charging=false
	hud.update_timeline(arena.history,0,"",12)
	expect(not hud.inspecting,"Timeline is absent during ordinary play")
	arena.player.position.x+=2;arena.player.reset_physics_interpolation();await settle()
	hud._process(0)
	var expected: Vector2=arena.player.camera.unproject_position(arena.player.get_global_transform_interpolated()*Vector3(0,.5,0))
	expect(hud.center.distance_to(expected)<1,"HUD follows actual perspective projection after camera/position update")
	scenes.developer_tools=false;hud.set_combat_hint(false)
	expect(not "F10" in hud.key_hint.text and "hold Space" in hud.key_hint.text and "E toggle" in hud.key_hint.text,"Player hints use manual slow/E toggle and hide developer shortcuts")
	scenes.developer_tools=true;hud.set_combat_hint(true)
	expect("F10" in hud.key_hint.text and "off" in hud.key_hint.text,"Developer and sound changes update cached hints")
	state.pause();await settle()
	settings=scenes.push_popup(&"Settings");await settle()
	arena.weapons.select_tool(2)
	var click:=InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_LEFT;click.position=root.get_visible_rect().size*.5;click.pressed=true
	root.push_input(click);await settle()
	expect(not arena.weapons.beam_charging,"Mouse press in paused Settings cannot start an attack")
	key(KEY_ESCAPE);await settle()
	expect(paused and state.is_paused() and scenes.has_popup(&"PauseMenu"),"Closing nested settings preserves the original pause")
	expect(root.gui_get_focus_owner()!=null and root.gui_get_focus_owner().is_visible_in_tree(),"Pause focus is restored visibly")
	state.resume();await settle()
	click.pressed=false;root.push_input(click);await settle()
	expect(not arena.weapons.beam_charging and arena.weapons.beam_cooldown<=0,"Resuming after Settings cannot fire a stale release")
	for won in [false,true]:
		scenes.show_run_result(won);await settle()
		var result: Control=scenes._popups.back().get_child(1)
		expect(result.is_ancestor_of(root.gui_get_focus_owner()) and paused,"Win/retry starts with focus in its own menu")
		scenes.push_popup(&"Settings");await settle()
		scenes.close_popup(&"Settings");await settle(8)
		expect(result.is_ancestor_of(root.gui_get_focus_owner()) and state.is_game_over() and paused,"Result settings returns focus without resuming gameplay")
		scenes.clear_popups();state.start_game();await settle()
	# Popup and menu destruction during a scene transition must be safe.
	scenes.return_main()
	for i in range(30):
		await create_timer(.03).timeout
		if not scenes.is_transitioning():break
	expect(state.is_in_menu() and current_scene.scene_file_path=="res://scenes/main.tscn","Return main completes a real transition without stray resume")
	for setting in saved:state.set_setting(setting,saved[setting])
	root.size=old_size;scenes.developer_tools=developer;scenes.fade_duration=old_fade
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
