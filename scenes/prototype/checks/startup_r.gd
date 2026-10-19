extends SceneTree
## Real SceneManager/campaign transitions; no stub start_play or loader path.
const OUT := "/home/mattlongname/game-jams/state/old-tech-jam-5/exports/round-r/"
var checks := 0
var failures: Array[String] = []
var profiles: Array[Dictionary] = []
var changed: Array[StringName] = []
var errors: Array[StringName] = []
var frame_count := 0
var timer_count := 0
var manager: Node
func _initialize() -> void:
	process_frame.connect(func(): frame_count+=1)
	call_deferred("run")
func expect(value: bool, text: String) -> void:
	checks+=1
	if not value: failures.append(text)
func settle(count:=3) -> void:
	for i in range(count): await process_frame
func done() -> void:
	while manager.is_transitioning(): await process_frame
	profiles.append(manager.last_transition_profile.duplicate(true))
	await settle()
func stop_world() -> void:
	if current_scene != null: current_scene.set_physics_process(false)
func run() -> void:
	create_timer(50,true).timeout.connect(func(): print(JSON.stringify({"status":"failed","checks":checks,"failures":failures+["startup watchdog"]}));quit(1))
	manager=root.get_node("SceneManager")
	var state=root.get_node("GameState")
	var saved: Dictionary=state.preferences()
	state.set_setting("fullscreen",false)
	manager.fade_duration=.02
	manager.scene_changed.connect(func(key: StringName): changed.append(key))
	manager.transition_failed.connect(func(key: StringName,_reason: String): errors.append(key))
	var heartbeat:=Timer.new()
	heartbeat.wait_time=.005;heartbeat.process_mode=Node.PROCESS_MODE_ALWAYS
	heartbeat.timeout.connect(func(): timer_count+=1)
	root.add_child(heartbeat);heartbeat.start()
	var main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main);current_scene=main;state.open_menu()
	await settle()
	expect(manager._loading_path.is_empty() and not manager.is_transitioning(),"No campaign request/construction before explicit start (intro stays separate)")
	expect(not manager.cancel_transition(),"Idle cancel is harmless")
	manager.params={"sentinel":17}
	var popup=manager.push_popup(&"NewGame")
	await settle()
	var before_frames:=frame_count
	var before_timers:=timer_count
	popup.hard.button_pressed=true
	popup.start_button.grab_focus()
	popup._on_start()
	expect(manager.is_transitioning(),"Existing New Game callback starts a real transition")
	expect(not manager.start_play(false,&"easy",false),"Duplicate starts are rejected")
	expect(not manager.reload_current_scene(),"Reload cannot race an active start")
	while manager._loading_path.is_empty() and manager.is_transitioning(): await process_frame
	await settle(2)
	expect(manager.is_transitioning() and manager._loading.visible,"Real cold request yields with loading feedback")
	expect(current_scene==main and not main.is_queued_for_deletion(),"Original scene remains owned until commit")
	expect(manager.params=={"sentinel":17},"Pending load does not publish new-run params")
	expect(frame_count-before_frames>=3 and timer_count>before_timers,"Main-loop frames and always timer continue during load")
	var enter:=InputEventKey.new()
	enter.keycode=KEY_ENTER;enter.physical_keycode=KEY_ENTER;enter.pressed=true
	root.push_input(enter)
	var released:=InputEventKey.new()
	released.keycode=KEY_ENTER;released.physical_keycode=KEY_ENTER
	root.push_input(released)
	expect(manager._cancel_requested,"Native Enter reaches focused Cancel while loading")
	expect(not manager.cancel_transition(),"Pending load accepts exactly one cancellation")
	await done()
	expect(current_scene==main and main.process_mode!=Node.PROCESS_MODE_DISABLED,"Cancellation restores original scene processing")
	expect(state.is_in_menu() and not paused,"Cancellation restores pre-start GameState and pause state")
	expect(manager.get_popup(&"NewGame")==popup and manager.params=={"sentinel":17},"Cancellation keeps popup and previous params")
	expect(not manager._loading.visible and not manager._fade_rect.visible,"Cancellation removes loading/fade blockers")
	expect(not popup.start_button.disabled and root.gui_get_focus_owner()==popup.start_button,"Cancelled New Game restores enabled Start and focus")
	expect(changed.is_empty(),"Cancelled request emits no scene_changed")
	expect(manager.start_play(true),"Different-path retry accepted after cancellation")
	expect(manager.cancel_transition(),"Different-path transition can cancel before resource work")
	await done()
	expect(current_scene==main and manager.params=={"sentinel":17},"Different-path cancellation preserves ownership and params")
	# Same-path retry resumes through ordinary cached dependencies, no stale state.
	expect(manager.start_play(false,&"hard",true),"Start succeeds after cancelled load")
	await done();stop_world()
	expect(current_scene.scene_file_path=="res://scenes/prototype/campaign.tscn","Production loader enters the real campaign")
	expect(manager.params=={"new_run":true,"difficulty":&"hard","skip_tutorials":true},"Real campaign receives Hard and independent skip flag")
	expect(current_scene.difficulty_id==&"hard","Real campaign consumes transported Hard value")
	expect(not manager.has_popup() and not is_instance_valid(popup),"Committed start clears old popup")
	expect(changed==[&"Campaign"],"Successful swap emits one event after ready")
	expect(current_scene.process_mode!=Node.PROCESS_MODE_DISABLED and not manager._loading.visible,"Committed scene resumes after loading/fade")
	manager.request_restart_room();await settle();stop_world()
	expect(manager.params.skip_tutorials and manager.params.difficulty==&"hard","Encounter-owned retry preserves run params")
	expect(not manager.start_play(false,&"invalid",true),"Invalid difficulty cannot alter run")
	expect(manager.params.skip_tutorials and manager.params.difficulty==&"hard","Rejected start preserves flags")
	# Legacy reload retains params; supported scene-tree ownership and ready signal.
	expect(manager.reload_current_scene(false),"No-fade reload accepted")
	await done();stop_world()
	expect(manager.params.skip_tutorials and current_scene.difficulty_id==&"hard","Reload retains difficulty/skip params")
	manager.return_main();await done()
	expect(state.is_in_menu(),"Public return_main restores menu state")
	# Legacy zero-argument path defaults Easy, skip false.
	expect(manager.start_play(),"Legacy default start accepted")
	await done();stop_world()
	expect(manager.params.difficulty==&"easy" and not manager.params.skip_tutorials,"Legacy defaults include tutorials on")
	manager.return_main();await done()
	expect(manager.start_play(true),"Legacy sandbox start accepted")
	await done();stop_world()
	expect(current_scene.scene_file_path=="res://scenes/prototype/arena.tscn" and not manager.params.skip_tutorials,"Sandbox uses actual arena with skip false")
	manager.return_main();await done()
	var previous:=current_scene
	var prior_params: Dictionary=manager.params.duplicate(true)
	var prior_focus:=root.gui_get_focus_owner()
	# A real loadable non-scene resource exercises asynchronous type failure,
	# without corrupt files/engine errors or a mocked ResourceLoader implementation.
	manager._change(&"BadResource","res://scenes/navigation/navigation_settings.tres",{"bad":true},true)
	await done()
	expect(errors==[&"BadResource"],"Wrong-type async resource emits one failure")
	expect(current_scene==previous and manager.params==prior_params,"Failure preserves original scene and params")
	expect(previous.process_mode!=Node.PROCESS_MODE_DISABLED and state.is_in_menu(),"Failure restores processing and state")
	expect(manager._loading.visible and manager._loading_cancel.text=="Back","Failure presents a recoverable message")
	manager._loading_cancel.pressed.emit()
	expect(not manager._loading.visible and not manager.is_transitioning() and root.gui_get_focus_owner()==prior_focus,"Failure dismissal restores keyboard focus and menu input")
	# Capture params at acceptance, not through a mutable caller dictionary.
	var supplied={"debug_room":0,"debug_wave":0,"skip_tutorials":true,"difficulty":&"easy"}
	expect(manager.go_to(&"Campaign",supplied,false),"Encounter-style direct go_to accepted")
	supplied.difficulty=&"hard";supplied.skip_tutorials=false
	await done();stop_world()
	expect(manager.params.difficulty==&"easy" and manager.params.skip_tutorials,"Accepted transition owns a copy of supplied params")
	expect(current_scene.wave_index==0,"Encounter params still reach campaign debug path")
	expect(not manager.cancel_transition(),"Commit-complete cancel cannot remove current scene")
	for i in range(5): await process_frame
	expect(manager._loading_path.is_empty(),"Completed/cancelled resource work releases transition state")
	root.get_node("AudioManager").stop_dialogue()
	manager.clear_popups()
	if current_scene: current_scene.queue_free()
	await settle()
	for setting in saved: state.set_setting(setting,saved[setting])
	state.open_menu();heartbeat.queue_free()
	await create_timer(1.2).timeout
	var orphan_nodes:=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	expect(orphan_nodes==0,"All temporary and replaced scene nodes are freed")
	if orphan_nodes>0: Node.print_orphan_nodes()
	var result={"orphan_nodes":orphan_nodes,"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"profiles":profiles}
	FileAccess.open(OUT+"checks.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result));quit(0 if failures.is_empty() else 1)
