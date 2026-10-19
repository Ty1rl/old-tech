extends SceneTree
## Final-source story/lifetime checks with real base scene stack and real voice.
## Held controls deliberately keep completion before the cross-seat start_play
## seam; no SceneManager transport stub, and no claim of integrated campaign skip.
const OUT := "/home/mattlongname/game-jams/state/old-tech-jam-7/exports/round-r"
var checks := 0
var failures: Array[String] = []
var scenes: Node
var audio: Node
var state: Node
func _initialize() -> void:call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);print("FAIL: ",message)
func settle(count: int = 6) -> void:
	for i in range(count):await process_frame
func pause_key() -> void:
	var event:=InputEventAction.new();event.action=&"pause";event.pressed=true;root.push_input(event)
	event=InputEventAction.new();event.action=&"pause";root.push_input(event)
func fresh(skip_tutorials: bool = false) -> Node:
	var popup=scenes.push_popup(&"NewGame");await settle()
	popup.hard.button_pressed=true;popup.skip_tutorials.button_pressed=skip_tutorials
	popup.start_button.pressed.emit();await settle()
	return popup.intro
func close_story() -> void:
	scenes.close_popup(&"NewGame");await settle()
func run() -> void:
	create_timer(35,true).timeout.connect(func():push_error("Round R final story watchdog");quit(1))
	scenes=root.get_node("SceneManager");audio=root.get_node("AudioManager");state=root.get_node("GameState")
	var saved: Dictionary=state.preferences()
	state.set_setting("sound",true);state.set_setting("volume",.8);state.set_setting("voice_volume",.9);state.set_setting("fullscreen",false)
	var fixture:=FileAccess.open(OUT+"/audio_contract_fixture.gd",FileAccess.WRITE)
	fixture.store_string(FileAccess.get_file_as_string("res://scenes/prototype/checks/ui_r_audio_contract.gd.txt"));fixture.close()
	audio.set_script(load(OUT+"/audio_contract_fixture.gd"));audio.install()
	var library:DialogueLibrary=audio.library
	var recording:AudioStream=library.clips[&"narration.intro"][0]
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main);current_scene=main;state.open_menu();await settle()
	expect(audio.played_events.is_empty() and audio.music_context==&"menu","Menu is free of narration and selects menu music")
	var intro=await fresh(true)
	expect(intro.active and current_scene==main and audio.is_speaking(&"narration.intro"),"Skip tutorials still starts actual story before any Campaign exists")
	expect(intro._difficulty==&"hard" and intro._skip_tutorials,"Start captures Hard and independent skip flag")
	expect(main.process_mode==Node.PROCESS_MODE_DISABLED and audio.music_context==&"intro" and audio.music.stream==null and not audio.music.playing,"Story disables underlying scene, owns Skip, and selects silent context")
	audio.speech_finished.emit(&"narration.intro",true);await settle()
	expect(intro.active and intro.phase==intro.Phase.NARRATING,"Stale terminal signal cannot bypass a live event")
	var f10:=InputEventKey.new();f10.physical_keycode=KEY_F10;f10.pressed=true;root.push_input(f10);f10.pressed=false;root.push_input(f10);await settle()
	expect(not scenes.has_popup(&"Developer"),"Underlying menu shortcut cannot intercept story")
	pause_key();await settle()
	var position:float=audio.voice.get_playback_position()
	await create_timer(.25,true).timeout
	expect(paused and absf(audio.voice.get_playback_position()-position)<.06,"Escape pauses real narration without consuming recording time")
	intro._on_settings();await settle()
	expect(scenes.get_popup(&"Settings")!=null and paused,"Native Settings opens above paused story")
	intro._on_skip();intro._on_pause();await settle()
	expect(paused and audio.is_speaking(&"narration.intro"),"Covered controls cannot skip or resume through Settings")
	pause_key();await settle()
	expect(not scenes.has_popup(&"Settings") and paused and intro.active,"Escape closes only Settings and leaves story paused")
	pause_key();await settle()
	expect(not paused and audio.is_speaking(&"narration.intro"),"Escape resumes the same recording")
	Input.action_press("move_left")
	var start:=Time.get_ticks_msec();var campaign_appeared:=false
	while audio.is_speaking(&"narration.intro"):
		campaign_appeared=campaign_appeared or current_scene!=main
		await create_timer(.1,true).timeout
	await settle()
	expect(not campaign_appeared and current_scene==main,"Campaign remains unconstructed throughout actual recording")
	expect(Time.get_ticks_msec()-start >= (recording.get_length()-.8)*1000,"Actual 13.95-second narration reaches its full natural duration")
	expect(intro.phase==intro.Phase.READY and intro.active and intro.status.text=="Release controls to begin","Natural completion waits at the real held-input boundary")
	intro._on_menu();await settle();Input.action_release("move_left")
	expect(not scenes.has_popup(&"NewGame") and state.is_in_menu() and not paused,"Menu cancels completed story cleanly before transition")
	expect(audio.process_mode==Node.PROCESS_MODE_ALWAYS and main.process_mode!=Node.PROCESS_MODE_DISABLED,"Cancel restores both native process modes")
	Input.action_press("ui_accept");intro=await fresh()
	intro._on_skip();await settle()
	expect(audio.is_speaking(&"narration.intro") and intro.phase==intro.Phase.NARRATING,"Held initial accept cannot skip newly opened story")
	Input.action_release("ui_accept");await settle()
	Input.action_press("move_right");intro._on_skip();await settle()
	expect(intro.phase==intro.Phase.READY and intro.active and not audio.is_speaking(&"narration.intro"),"Explicit Skip terminates speech and waits for held movement")
	await close_story();Input.action_release("move_right")
	expect(not paused and audio.process_mode==Node.PROCESS_MODE_ALWAYS,"External popup removal cleans up ready intro")
	var queued:=DialogueLibrary.new();queued.clips=library.clips.duplicate()
	var blocker:=AudioStreamWAV.new();blocker.format=AudioStreamWAV.FORMAT_16_BITS;blocker.mix_rate=22050
	var silence:=PackedByteArray();silence.resize(44100);blocker.data=silence
	queued.clips[&"fixture.blocker"]=[blocker];audio.library=queued;audio.queue_intro=true
	intro=await fresh()
	expect(audio.current_event==&"fixture.blocker" and audio.is_speaking(&"narration.intro") and intro.phase==intro.Phase.NARRATING,"Queued narration also blocks readiness")
	intro._on_menu();await settle()
	expect(audio._queue.is_empty() and not audio.is_speaking(&"narration.intro"),"Cancel clears queued narration")
	audio.library=DialogueLibrary.new();Input.action_press("move_left");intro=await fresh()
	expect(intro.phase==intro.Phase.READY and intro.active,"Missing audio immediately reaches input-release readiness without awaiting a signal")
	await close_story();Input.action_release("move_left");audio.library=library
	intro=await fresh();pause_key();await settle();await close_story()
	expect(not paused and audio.process_mode==Node.PROCESS_MODE_ALWAYS and not audio.is_speaking(&"narration.intro"),"External removal while paused restores the entire lifetime")
	intro=await fresh();intro._on_quit();await settle()
	expect(audio.quit_requested==1 and not intro.active and not audio.is_speaking(&"narration.intro"),"Quit cancels before forwarding to audio lifetime owner")
	await close_story()
	intro=await fresh();root.close_requested.emit();await settle()
	expect(audio.quit_requested==2 and not intro.active and not paused,"Native window-close also cancels and restores intro state")
	await close_story()
	audio._intro_played=true;intro=await fresh()
	expect(audio.is_speaking(&"narration.intro"),"Fresh story remains independent of app-once menu intro flag")
	await close_story()
	for setting in saved:state.set_setting(setting,saved[setting])
	audio.stop_dialogue();audio.voice.stream=null;queued=null;blocker=null;await create_timer(.3,true).timeout
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"scope":"final UI lifetimes; real third-argument/campaign transport requires JAM-5/JAM-4 integration"}));quit(0 if failures.is_empty() else 1)
