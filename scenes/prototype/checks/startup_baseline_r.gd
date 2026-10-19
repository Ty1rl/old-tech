extends SceneTree
## Baseline phase probe: same synchronous resource/scene pipeline as base manager.
## No campaign preload: the first measured load is cold in this engine process.
const OUT := "/home/mattlongname/game-jams/state/old-tech-jam-5/exports/round-r/"
var samples: Array[Dictionary] = []
var gaps: Array[int] = []
var last_frame := 0
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	process_frame.connect(_frame)
	call_deferred("run")
func _frame() -> void:
	var now := Time.get_ticks_usec()
	if last_frame: gaps.append(now-last_frame)
	last_frame=now
func draw_frame() -> void:
	await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
func run() -> void:
	create_timer(50,true).timeout.connect(func(): print(JSON.stringify({"status":"failed","checks":checks,"failures":["baseline watchdog"]}));quit(1))
	var manager=root.get_node("SceneManager")
	var state=root.get_node("GameState")
	state.set_setting("fullscreen",false)
	var menu=load("res://scenes/main.tscn").instantiate()
	root.add_child(menu);current_scene=menu;state.open_menu()
	await draw_frame()
	for run_index in range(2):
		var row={"cache":"process-cold" if run_index==0 else "process-warm","driver":DisplayServer.get_name(),"os_cache":"untouched"}
		gaps.clear()
		var begin:=Time.get_ticks_usec()
		current_scene.process_mode=Node.PROCESS_MODE_DISABLED
		await manager._fade_to(1)
		row.fade_out_usec=Time.get_ticks_usec()-begin
		manager.clear_popups()
		manager.params={"new_run":true,"difficulty":&"easy"}
		state.start_game()
		var mark:=Time.get_ticks_usec()
		var packed:=load("res://scenes/prototype/campaign.tscn") as PackedScene
		row.resource_usec=Time.get_ticks_usec()-mark
		mark=Time.get_ticks_usec()
		var campaign:=packed.instantiate()
		row.instantiate_usec=Time.get_ticks_usec()-mark
		mark=Time.get_ticks_usec()
		var err:=change_scene_to_node(campaign)
		await scene_changed
		row.swap_ready_usec=Time.get_ticks_usec()-mark
		mark=Time.get_ticks_usec()
		await draw_frame()
		row.first_draw_wait_usec=Time.get_ticks_usec()-mark
		mark=Time.get_ticks_usec()
		await manager._fade_to(0)
		row.fade_in_usec=Time.get_ticks_usec()-mark
		row.total_usec=Time.get_ticks_usec()-begin
		row.max_frame_gap_usec=gaps.max() if not gaps.is_empty() else 0
		row.frames=gaps.size()
		row.campaign_mode=String(campaign.mode)
		checks+=1
		if err!=OK or current_scene!=campaign: failures.append("campaign swap")
		campaign.set_physics_process(false)
		samples.append(row)
		# Keep the first resource reference through the warm repeat, as normal
		# same-process script/dependency caches can remain hot on returning to menu.
		if run_index==0:
			manager.go_to(&"Main",{},false)
			while manager.is_transitioning(): await process_frame
			state.open_menu()
			await draw_frame()
	root.get_node("AudioManager").stop_dialogue()
	if current_scene: current_scene.queue_free()
	await process_frame
	var result={"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"samples":samples}
	FileAccess.open(OUT+"baseline-"+DisplayServer.get_name()+".json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result));quit(0 if failures.is_empty() else 1)
