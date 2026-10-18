extends SceneTree
## A-base consumer check. capability_time.gd is a disposable flags-only fixture
## in this seat's receipt directory, NOT a production fallback or time engine.
const OUT := "/home/mattlongname/game-jams/state/old-tech-jam-7/exports/round-o"
var checks := 0
var failures: Array[String] = []
var capability_script: Script
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
func settle(count: int = 6) -> void:
	for i in range(count): await process_frame
func key(code: Key, shift: bool = false) -> void:
	var event := InputEventKey.new(); event.keycode=code;event.physical_keycode=code;event.pressed=true;event.shift_pressed=shift
	root.push_input(event)
func release(code: Key) -> void:
	var event := InputEventKey.new();event.keycode=code;event.physical_keycode=code;root.push_input(event)
func pad_down() -> void:
	var event := InputEventJoypadButton.new();event.button_index=JOY_BUTTON_DPAD_DOWN;event.pressed=true;root.push_input(event)
func _fixture_capabilities(node: Node) -> void:
	# Actual start transitions into the unchanged campaign. Supply ONLY the two
	# forthcoming flags to its real controller before its consumers bind it.
	if node is TimeController: node.set_script(capability_script)
func transition_done(manager: Node) -> void:
	for i in range(30):
		await create_timer(.02).timeout
		if not manager.is_transitioning(): return
func run() -> void:
	create_timer(25,true).timeout.connect(func():
		failures.append("UI O watchdog"); print(JSON.stringify({"status":"failed","checks":checks,"failures":failures}));quit(1))
	capability_script=load(OUT+"/capability_time.gd")
	node_added.connect(_fixture_capabilities)
	var scenes = root.get_node("SceneManager");var state = root.get_node("GameState")
	var saved: Dictionary=state.preferences(); var old_size:=root.size;var old_fade:float=scenes.fade_duration
	state.set_setting("fullscreen",false);state.set_setting("tutorial",false);scenes.fade_duration=.01
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main);current_scene=main;state.open_menu();await settle()
	var menu=main.get_node("MainMenu")
	menu.play.pressed.emit();await settle()
	var start=scenes.get_popup(&"NewGame")
	expect(start != null and start != start.get_parent(),"New Game opens authored content through public popup API")
	expect(start.selected_difficulty()==&"easy" and root.gui_get_focus_owner()==start.easy,"Easy is default and initially focused")
	var authored=start.easy;authored.text="Easy · inspector edit";await settle()
	expect(start.easy==authored and authored.text=="Easy · inspector edit","Scene-owned difficulty button survives ready/focus work")
	pad_down();await settle()
	expect(root.gui_get_focus_owner()==start.hard,"D-pad moves from Easy to Hard")
	key(KEY_SPACE);release(KEY_SPACE);await settle()
	expect(start.selected_difficulty()==&"hard" and not start.easy.button_pressed,"Native Space selects Hard exclusively")
	key(KEY_TAB,true);await settle()
	expect(root.gui_get_focus_owner()==start.easy,"Shift Tab returns from Hard to Easy")
	key(KEY_SPACE);release(KEY_SPACE);await settle()
	expect(start.selected_difficulty()==&"easy" and not start.hard.button_pressed,"Native Space can select Easy again")
	pad_down();await settle();key(KEY_SPACE);release(KEY_SPACE);await settle()
	key(KEY_TAB);await settle()
	expect(root.gui_get_focus_owner()==start.start_button,"Tab reaches Start without changing selected difficulty")
	root.size=Vector2i(640,360);await settle(10)
	expect(root.get_visible_rect().encloses(start.panel.get_global_rect()),"Start dialog fits small viewport")
	expect(start.scroll.get_global_rect().encloses(start.start_button.get_global_rect()),"Focused Start remains inside small scroll clip")
	start.get_node("%BackButton").grab_focus();await settle()
	expect(root.get_visible_rect().encloses(start.get_node("%BackButton").get_global_rect()),"Small-window Back is reachable")
	start.get_node("%BackButton").pressed.emit()
	expect(scenes.get_popup(&"NewGame")==null,"Closing popup disappears from public API immediately")
	await settle()
	expect(root.gui_get_focus_owner()==menu.play and state.is_in_menu(),"Back restores main-menu focus without starting")
	menu.play.pressed.emit();await settle();start=scenes.get_popup(&"NewGame")
	start.hard.button_pressed=true;start.start_button.grab_focus();await settle()
	key(KEY_ENTER);release(KEY_ENTER);await transition_done(scenes);await settle()
	expect(current_scene.scene_file_path=="res://scenes/prototype/campaign.tscn" and scenes.params.difficulty==&"hard" and scenes.params.new_run,"Actual Enter start reaches Campaign with Hard params")
	expect(scenes.get_popup(&"NewGame")==null,"Successful start removes the difficulty dialog")
	current_scene.set_physics_process(false)
	scenes.request_restart_room();await settle()
	expect(scenes.params.difficulty==&"hard" and scenes.get_popup(&"NewGame")==null,"Room retry keeps Hard without reopening or changing difficulty")
	scenes.return_main();await transition_done(scenes);await settle()
	menu=current_scene.get_node("MainMenu");menu.play.pressed.emit();await settle();start=scenes.get_popup(&"NewGame")
	expect(start.selected_difficulty()==&"easy","Fresh start dialog does not retain a prior run's difficulty")
	start.start_button.pressed.emit();await transition_done(scenes);await settle()
	expect(scenes.params.difficulty==&"easy" and current_scene.scene_file_path=="res://scenes/prototype/campaign.tscn","Actual default start passes Easy through the same manager")
	current_scene.set_physics_process(false)
	var before: Dictionary=scenes.params.duplicate()
	expect(not scenes.start_play(false,&"invalid") and scenes.params==before,"Unknown difficulty cannot alter current run params")
	state.pause();await settle();var pause=scenes.get_popup(&"PauseMenu")
	pause.get_node("%SettingsButton").pressed.emit();await settle()
	var settings=scenes.get_popup(&"Settings")
	expect(scenes.get_popup(&"")==settings and scenes.get_popup(&"PauseMenu")==pause,"Public API finds top content and keyed lower popup")
	settings.queue_free()
	expect(scenes.get_popup(&"Settings")==null,"Public API excludes content queued for deletion before wrapper cleanup")
	await settle(10)
	expect(root.gui_get_focus_owner()!=null and pause.is_ancestor_of(root.gui_get_focus_owner()),"Public-API focus returns to pause after nested settings")
	state.resume();await settle()
	expect(scenes.get_popup(&"Missing")==null and scenes.get_popup(&"")==null,"Absent popup keys and empty stack return null")
	# Preserve existing one-argument API with an actual sandbox start.
	expect(scenes.start_play(true),"Legacy one-argument start remains accepted")
	await transition_done(scenes);await settle()
	expect(current_scene.scene_file_path=="res://scenes/prototype/arena.tscn" and scenes.params.difficulty==&"easy","Legacy sandbox start defaults to Easy params")
	current_scene.set_physics_process(false)
	var arena=current_scene
	var controller: TimeController=arena.time_controller
	var hud=arena.status_hud
	controller.set_capabilities(false,false);hud.readout_mode=0;await settle()
	expect(not "Space" in hud.key_hint.text and not hud.rewind_pips_visible(),"Locked capabilities suppress slow hint and charge pips")
	expect(hud.time_readout().begins_with("Time") and not "rewind" in hud.time_readout(),"Survival meter stays readable while rewind is locked")
	controller.set_capabilities(true,false);await settle()
	expect("Space" in hud.key_hint.text and not hud.rewind_pips_visible(),"Slow unlock updates cached hint without exposing rewind")
	controller.set_capabilities(false,true);await settle()
	expect(not "Space" in hud.key_hint.text and hud.rewind_pips_visible() and "rewinds left" in hud.time_readout(),"Rewind unlock exposes pips/count independently of slow")
	controller.set_capabilities(true,true);controller.try_spend(20);await settle()
	expect("80%" in hud.time_readout(),"Meter reads live controller spending")
	# Real settings, wear and completed checkpoint signals drive shared repair view.
	var equipment:=WeaponEquipment.new();var condition_settings:WeaponConditionSettings=equipment.settings.duplicate()
	condition_settings.repair_steps=5;equipment=WeaponEquipment.new(condition_settings)
	equipment.spend(&"ring",equipment.capacity(&"ring")*.7)
	var view=load("res://scenes/ui/repair_condition.tscn").instantiate();root.add_child(view);view.bind_equipment(equipment,&"ring");await settle()
	expect(view.segment_count()==5 and view.filled_segments()==1 and view.progress.text.contains("30%"),"Repair segments use nondefault actual equipment settings and wear")
	var session_id:=equipment.begin_repair(&"ring");var restored:=equipment.complete_step(&"ring",session_id);await settle(1)
	expect(restored>0 and view.filled_segments()==2 and view.progress.text.contains("40%") and view._flash>0,"Actual checkpoint signal fills the next segment and triggers feedback")
	hud.update_status(arena.player,arena.weapons,equipment)
	expect(hud.checkpoints==view.segment_count() and is_equal_approx(hud.fractions[0], .4),"Player HUD and repair view share the same live segmentation and condition")
	var snapshot:=equipment.capture_state();equipment.complete_step(&"ring",session_id);await settle()
	expect(view.filled_segments()==3,"Another actual checkpoint fills exactly one more segment")
	equipment.restore_state(snapshot);await settle()
	expect(view.filled_segments()==2,"Rewinding equipment condition also rewinds displayed completed repairs")
	var other:=WeaponEquipment.new();view.bind_equipment(other,&"beam");view.bind_equipment(other,&"beam");await settle()
	expect(equipment.repaired.get_connections().is_empty() and other.repaired.get_connections().size()==1,"Rebind releases old equipment signal and is idempotent")
	var condition_before:=other.capture_state();view.bind_equipment(null,&"");await settle()
	expect(other.capture_state()==condition_before and other.repaired.get_connections().is_empty(),"Unbind neither changes balance nor leaves signals")
	view.bind_equipment(other,&"beam");view.queue_free();await settle()
	expect(other.repaired.get_connections().is_empty(),"Freeing bound repair view releases its equipment connection")
	# Real emergency session while fixture capability flags satisfy Round O contract.
	var rewind:EmergencyRewind=arena.emergency_rewind
	var emergency=arena.emergency_view
	controller.begin_attempt();rewind.history.clear()
	for i in range(100):rewind.history.record(.05,func()->Dictionary:return arena.capture_state())
	controller.force_depletion();await settle()
	expect(emergency.visible and rewind.active and not hud.key_hint.visible,"Real depletion opens recovery without ordinary combat hints")
	for window_size in [Vector2i(1280,800),Vector2i(640,360)]:
		root.size=window_size;await settle(10)
		for index in [0,45,99]:
			rewind.select(index);await settle()
			var instruction:Label=emergency.get_node("%Instructions")
			expect(instruction.is_visible_in_tree() and "Enter" in instruction.text and root.get_visible_rect().encloses(instruction.get_global_rect()),"Enter remains fully visible throughout scrubbing at "+str(window_size)+" / "+str(index))
	key(KEY_ENTER);release(KEY_ENTER);await settle()
	expect(not rewind.active and not emergency.visible and controller.charges_remaining==2,"Arena-owned Enter confirms recovery with one charge spent")
	for setting in saved:state.set_setting(setting,saved[setting])
	root.size=old_size;scenes.fade_duration=old_fade
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
