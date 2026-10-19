extends SceneTree
var checks:=0
var failures: Array[String]=[]
var scenes: Node
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, text: String) -> void:
	checks+=1
	if not ok: failures.append(text)
func done() -> void:
	while scenes.is_transitioning(): await process_frame
	if current_scene!=null:current_scene.set_physics_process(false)
func run() -> void:
	create_timer(35,true).timeout.connect(func():print(JSON.stringify({"status":"failed","checks":checks,"failures":["transition watchdog"]}));quit(1))
	scenes=root.get_node("SceneManager");scenes.fade_duration=.01
	expect(scenes.start_play(true,&"hard",true),"Three-argument legacy sandbox start accepted")
	expect(not scenes.start_play() and not scenes.reload_current_scene(),"Duplicate starts/reload rejected during transition")
	await done()
	expect(current_scene.scene_file_path=="res://scenes/prototype/arena.tscn","Actual sandbox is current scene")
	expect(scenes.params.difficulty==&"hard" and scenes.params.skip_tutorials,"Sandbox transports independent flags")
	expect(scenes.reload_current_scene(false),"No-fade reload accepted")
	await done()
	expect(scenes.params.difficulty==&"hard" and scenes.params.skip_tutorials,"Reload retains flags")
	scenes.return_main();await done()
	# Hold the real resource to exercise the native cache fast path explicitly.
	var cached: PackedScene=load("res://scenes/prototype/campaign.tscn")
	expect(cached!=null and scenes.start_play(),"Zero-argument start accepted with actual cached campaign")
	await done()
	expect(scenes.last_transition_profile.cached_root and scenes.last_transition_profile.resource_steps==0,"Cached root bypasses the dependency sweep")
	expect(current_scene.difficulty_id==&"easy" and not scenes.params.skip_tutorials,"Legacy defaults preserve Easy and teaching")
	var previous: Dictionary=scenes.params.duplicate(true)
	expect(not scenes.start_play(false,&"invalid",true) and scenes.params==previous,"Invalid difficulty preserves current run")
	scenes.request_restart_room()
	expect(scenes.params==previous and not scenes.is_transitioning(),"Campaign owns room restart without replacing run params")
	scenes.return_main();await done()
	var supplied={"difficulty":&"hard","skip_tutorials":true,"debug_room":0,"debug_wave":0}
	expect(scenes.go_to(&"Campaign",supplied,false),"Encounter-style direct transition accepted")
	supplied.difficulty=&"easy";supplied.skip_tutorials=false
	await done()
	expect(scenes.params.difficulty==&"hard" and scenes.params.skip_tutorials,"Accepted params are copied")
	expect(current_scene.difficulty_id==&"hard" and current_scene.wave_index==0,"Actual campaign receives difficulty and encounter")
	scenes.return_main();await done()
	var audio=root.get_node("AudioManager")
	audio.stop_dialogue();audio.set_music_context(&"intro")
	current_scene.queue_free();await process_frame
	root.get_node("GameState").open_menu()
	await create_timer(.4).timeout
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
