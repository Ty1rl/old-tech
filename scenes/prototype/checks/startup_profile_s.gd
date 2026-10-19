extends SceneTree
## Actual menu -> public start_play -> actual campaign, cold/warm process cache.
## OS/import/shader caches are untouched. Private software-render timings are not
## a claim about host GPU responsiveness or pure shader compilation duration.
const OUT := "/home/mattlongname/game-jams/state/old-tech-jam-5/exports/round-s/"
var samples: Array[Dictionary] = []
var gaps: Array[int] = []
var previous_tick := 0
var loading_frames := 0
var timer_ticks := 0
var checks := 0
var failures: Array[String] = []
var manager: Node
func _initialize() -> void:
	process_frame.connect(_frame)
	call_deferred("run")
func _frame() -> void:
	var now:=Time.get_ticks_usec()
	if previous_tick: gaps.append(now-previous_tick)
	previous_tick=now
	if is_instance_valid(manager) and not manager._loading_path.is_empty(): loading_frames+=1
func expect(ok: bool, text: String) -> void:
	checks+=1
	if not ok: failures.append(text)
func draw_frame() -> void:
	await process_frame
	if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
func done() -> void:
	while manager.is_transitioning(): await process_frame
func picture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await draw_frame()
	var image:=root.get_texture().get_image()
	expect(image.save_png(OUT+name+".png")==OK,"Capture "+name)
func run() -> void:
	create_timer(50,true).timeout.connect(func(): print(JSON.stringify({"status":"failed","checks":checks,"failures":["profile watchdog"]}));quit(1))
	manager=root.get_node("SceneManager")
	var state=root.get_node("GameState")
	var saved: Dictionary=state.preferences()
	state.set_setting("fullscreen",false)
	var main=load("res://scenes/main.tscn").instantiate()
	root.add_child(main);current_scene=main;state.open_menu()
	await draw_frame()
	var timer:=Timer.new()
	timer.wait_time=.01;timer.process_mode=Node.PROCESS_MODE_ALWAYS
	timer.timeout.connect(func(): timer_ticks+=1)
	root.add_child(timer);timer.start()
	for run_index in range(2):
		gaps.clear();loading_frames=0
		var before_ticks:=timer_ticks
		expect(manager.start_play(false,&"easy" if run_index==0 else &"hard",run_index==1),"Actual start accepted")
		await done()
		var row: Dictionary=manager.last_transition_profile.duplicate(true)
		row.cache="process-cold" if run_index==0 else "process-warm"
		row.os_cache="untouched";row.driver=DisplayServer.get_name()
		row.max_frame_gap_usec=gaps.max() if not gaps.is_empty() else 0
		row.frame_gaps_usec=gaps.duplicate()
		row.frames=gaps.size();row.loading_frames=loading_frames
		row.always_timer_ticks=timer_ticks-before_ticks
		row.campaign_mode=String(current_scene.mode)
		samples.append(row)
		expect(current_scene.scene_file_path=="res://scenes/prototype/campaign.tscn","Actual campaign entered")
		expect((run_index==1 or row.loading_frames>0) and row.always_timer_ticks>0,"Main loop advances through cold loading and warm transitions")
		expect(manager.params.skip_tutorials==(run_index==1),"Skip flag transported on actual path")
		current_scene.set_physics_process(false)
		if run_index==0:
			manager.return_main();await done();await draw_frame()
	await picture("campaign-ready")
	# Review capture outside measured trials. An explicit loading request can be
	# cancelled through the actual visible control; no production time delay added.
	manager.return_main();await done()
	expect(manager.start_play(false,&"hard",true),"Capture-only start accepted")
	while not manager._loading.visible and manager.is_transitioning(): await process_frame
	await picture("loading")
	manager._loading_cancel.pressed.emit()
	await done()
	# If the warm request committed before capture, ownership still stays valid.
	root.get_node("AudioManager").stop_dialogue()
	root.get_node("AudioManager").set_music_context(&"intro")
	if current_scene: current_scene.queue_free()
	await process_frame
	state.open_menu();timer.queue_free()
	for setting in saved: state.set_setting(setting,saved[setting])
	await create_timer(1.2).timeout
	var result={"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"samples":samples}
	FileAccess.open(OUT+"profile-"+DisplayServer.get_name()+".json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result));quit(0 if failures.is_empty() else 1)
