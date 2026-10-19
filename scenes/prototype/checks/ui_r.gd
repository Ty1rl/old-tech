extends SceneTree
## UI integration on base 25cf66f with an explicit disposable audio contract
## adapter (in seat receipt), never an edit to JAM-6's production files.
const OUT := "/home/mattlongname/game-jams/state/old-tech-jam-7/exports/round-r"
var checks := 0
var failures: Array[String] = []
var scenes: Node
var audio: Node
var state: Node
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); print("FAIL: ",message)
func settle(count: int = 6) -> void:
	for i in range(count): await process_frame
func wait_transition() -> void:
	await settle()
	while scenes.is_transitioning(): await process_frame
	await settle()
func held(action: String, down: bool) -> void:
	if down: Input.action_press(action)
	else: Input.action_release(action)
func fresh(difficulty: StringName = &"easy", skip_tutorials: bool = false) -> Node:
	var popup = scenes.push_popup(&"NewGame")
	await settle()
	popup.skip_tutorials.button_pressed = skip_tutorials
	popup.hard.button_pressed = difficulty == &"hard"
	popup.easy.button_pressed = difficulty == &"easy"
	var result=popup.intro
	popup.start_button.pressed.emit()
	await settle()
	return result if is_instance_valid(result) else null
func return_menu() -> void:
	audio.stop_dialogue()
	scenes.return_main();await wait_transition()
func run() -> void:
	create_timer(48,true).timeout.connect(func():
		failures.append("UI R watchdog");print(JSON.stringify({"status":"failed","checks":checks,"failures":failures}));quit(1))
	scenes=root.get_node("SceneManager");audio=root.get_node("AudioManager");state=root.get_node("GameState")
	var transport_ready:=false
	for method in scenes.get_method_list():
		if method.name==&"start_play":transport_ready=method.args.size()>=3
	if not transport_ready:
		expect(false,"Real JAM-5 start_play third argument is required; no transport stub is installed")
		print(JSON.stringify({"status":"failed","checks":checks,"failures":failures}));quit(1);return
	var saved: Dictionary=state.preferences()
	state.set_setting("sound",true);state.set_setting("volume",.8);state.set_setting("voice_volume",.9)
	state.set_setting("fullscreen",false);state.set_setting("tutorial",false);state.set_setting("skip_tutorials",false)
	# No production compatibility ladder: this explicit fixture exists only in
	# this isolated base checkout, before JAM-6's independent delivery is merged.
	var fixture:=FileAccess.open(OUT+"/audio_contract_fixture.gd",FileAccess.WRITE)
	fixture.store_string(FileAccess.get_file_as_string("res://scenes/prototype/checks/ui_r_audio_contract.gd.txt"));fixture.close()
	audio.set_script(load(OUT+"/audio_contract_fixture.gd"));audio.install()
	var full_library: DialogueLibrary = audio.library
	var actual_intro: AudioStream=full_library.clips[&"narration.intro"][0]
	print("Actual intro seconds: ", actual_intro.get_length())
	scenes.fade_duration=.04
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main);current_scene=main;state.open_menu();await settle()
	var menu=main.get_node("MainMenu")
	expect(audio.played_events.is_empty() and audio.music_context==&"menu","Menu sets music context without narration")
	expect(menu.get_node("Margin/Scroll/Column/Tagline").text=="Old tech. Borrowed time.","Exact menu subtitle")
	# Run actual recorded narration to its natural end, with the real player.
	var intro=await fresh(&"hard")
	expect(current_scene==main and intro.active and audio.is_speaking(&"narration.intro"),"Hard story plays before Campaign construction")
	expect(audio.music_context==&"intro","Intro owns controls and selects silent music context")
	expect(main.process_mode==Node.PROCESS_MODE_DISABLED,"Underlying scene cannot receive gameplay during story")
	audio.speech_finished.emit(&"narration.intro",true);await settle()
	expect(intro.active and intro.phase==intro.Phase.NARRATING,"A stale terminal signal never bypasses the lifetime query")
	intro._on_pause();await settle()
	var pos:float=audio.voice.get_playback_position()
	await create_timer(.25,true).timeout
	expect(paused and absf(audio.voice.get_playback_position()-pos)<.06,"Native pause preserves narration position")
	intro._on_settings();await settle()
	expect(scenes.get_popup(&"Settings")!=null and scenes.get_popup(&"")==scenes.get_popup(&"Settings"),"Native settings stacks above black intro")
	intro._on_skip();intro._on_pause();await settle()
	expect(paused and intro.active and audio.is_speaking(&"narration.intro"),"Covered intro controls cannot act through native Settings")
	scenes.close_popup(&"Settings");await settle()
	expect(paused and intro.active and audio.is_speaking(&"narration.intro"),"Closing settings retains paused narration")
	intro._on_pause();await settle()
	expect(not paused and audio.process_mode==Node.PROCESS_MODE_ALWAYS,"Resume continues speech with native pause-aware manager")
	var began:=Time.get_ticks_msec()
	while audio.is_speaking(&"narration.intro"):
		expect(current_scene==main,"No Campaign frame precedes actual narration completion")
		await create_timer(.2,true).timeout
	await wait_transition()
	expect(current_scene.scene_file_path=="res://scenes/prototype/campaign.tscn" and scenes.params.difficulty==&"hard" and scenes.params.new_run and not scenes.params.skip_tutorials,"Natural completion fades into real Hard Campaign")
	expect(Time.get_ticks_msec()-began >= (actual_intro.get_length()-.7)*1000,"Actual recorded narration retains full duration")
	expect(audio.process_mode==Node.PROCESS_MODE_ALWAYS and not paused,"Successful start restores manager lifetime and unpauses")
	var stories:int=audio.played_events.count(&"narration.intro")
	current_scene.set_physics_process(false)
	scenes.request_restart_room();await settle()
	expect(audio.played_events.count(&"narration.intro")==stories,"Retry does not replay intro")
	await return_menu()
	expect(audio.played_events.count(&"narration.intro")==stories,"Returning to menu does not narrate")
	# Cancel, explicit skip, held movement/accept, and absent audio.
	intro=await fresh()
	intro._on_menu();await settle()
	expect(scenes.get_popup(&"NewGame")==null and state.is_in_menu() and not paused and not audio.is_speaking(&"narration.intro"),"Menu cancels speech and closes overlay")
	expect(current_scene.process_mode!=Node.PROCESS_MODE_DISABLED and audio.process_mode==Node.PROCESS_MODE_ALWAYS,"Cancel restores both owned process modes")
	held("ui_accept",true)
	intro=await fresh(&"easy",true)
	intro._on_skip();await settle()
	expect(intro.active and audio.is_speaking(&"narration.intro"),"Held initial accept cannot skip newly opened story")
	held("ui_accept",false);await settle()
	held("move_left",true);intro._on_skip();await settle()
	expect(intro.active and current_scene.scene_file_path=="res://scenes/main.tscn","Skip waits for held movement release")
	held("move_left",false);await wait_transition()
	expect(scenes.params.difficulty==&"easy" and scenes.params.skip_tutorials and current_scene.scene_file_path=="res://scenes/prototype/campaign.tscn","Real manager transports skip-enabled Easy only after controls release")
	await return_menu()
	var empty:=DialogueLibrary.new();audio.library=empty
	intro=await fresh(&"hard");await wait_transition()
	expect(current_scene.scene_file_path=="res://scenes/prototype/campaign.tscn" and scenes.params.difficulty==&"hard","Unavailable narration never sticks on black")
	audio.library=full_library;await return_menu()
	var queued_library:=DialogueLibrary.new();queued_library.clips=full_library.clips.duplicate()
	var blocker:=AudioStreamWAV.new();blocker.format=AudioStreamWAV.FORMAT_16_BITS;blocker.mix_rate=22050
	var silence:=PackedByteArray();silence.resize(44100);blocker.data=silence
	queued_library.clips[&"fixture.blocker"]=[blocker]
	audio.library=queued_library;audio.queue_intro=true
	intro=await fresh()
	expect(audio.current_event==&"fixture.blocker" and audio.is_speaking(&"narration.intro") and intro.phase==intro.Phase.NARRATING,"Queued narration gates Campaign before it becomes current speech")
	intro._on_menu();await settle()
	expect(not audio.is_speaking(&"narration.intro") and audio._queue.is_empty(),"Cancel terminates both queued narration and its blocker")
	audio.library=full_library
	intro=await fresh();scenes.close_popup(&"NewGame");await settle()
	expect(not audio.is_speaking(&"narration.intro") and not paused and audio.process_mode==Node.PROCESS_MODE_ALWAYS,"External close cleans speech and native pause ownership")
	intro=await fresh();intro._on_quit();await settle()
	expect(audio.quit_requested==1 and not audio.is_speaking(&"narration.intro") and not paused,"Quit explicitly cancels before forwarding native quit")
	scenes.close_popup(&"NewGame");await settle()
	# Fresh narration starts each intentional new story, despite the old app-once flag.
	audio._intro_played=true
	intro=await fresh();expect(audio.is_speaking(&"narration.intro"),"Deliberate new story is independent of prior app intro flag")
	intro.cancel();scenes.close_popup(&"NewGame");await settle()
	for setting in saved:state.set_setting(setting,saved[setting])
	audio.stop_dialogue();audio.voice.stream=null
	queued_library=null;blocker=null
	await create_timer(.3,true).timeout
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
