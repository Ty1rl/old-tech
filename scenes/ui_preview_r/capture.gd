extends SceneTree
const OUT := "/home/mattlongname/game-jams/state/old-tech-jam-7/exports/round-r"
var pictures: Array[String] = []
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func settle(count: int = 12) -> void:
	for i in range(count): await process_frame
func expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message)
func snap(name: String) -> void:
	await settle();await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(OUT+"/"+name+".png")==OK,"Save "+name)
	pictures.append(name);print("Saved ",name)
func run() -> void:
	create_timer(35,true).timeout.connect(func():push_error("UI R capture watchdog");quit(1))
	var state=root.get_node("GameState");var scenes=root.get_node("SceneManager");var audio=root.get_node("AudioManager")
	var saved: Dictionary=state.preferences()
	state.set_setting("sound",true);state.set_setting("volume",.8);state.set_setting("voice_volume",.9);state.set_setting("fullscreen",false);state.set_setting("skip_tutorials",false)
	var fixture:=FileAccess.open(OUT+"/audio_contract_fixture.gd",FileAccess.WRITE)
	fixture.store_string(FileAccess.get_file_as_string("res://scenes/prototype/checks/ui_r_audio_contract.gd.txt"));fixture.close()
	audio.set_script(load(OUT+"/audio_contract_fixture.gd"));audio.install()
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main);current_scene=main;state.open_menu();await settle()
	for view_size in [Vector2i(1280,800),Vector2i(640,360)]:
		root.size=view_size;await settle()
		var suffix:="normal" if view_size.x==1280 else "compact"
		await snap("menu-"+suffix)
		var start=scenes.push_popup(&"NewGame");await settle()
		start.skip_tutorials.grab_focus();await settle()
		expect(root.get_visible_rect().encloses(start.skip_tutorials.get_global_rect()),"Skip tutorials visible when focused "+suffix)
		await snap("options-"+suffix)
		start.hard.button_pressed=true;start.skip_tutorials.button_pressed=true
		start.start_button.grab_focus();await settle()
		expect(root.get_visible_rect().encloses(start.panel.get_global_rect()),"Difficulty panel fits "+suffix)
		expect(start.scroll.get_global_rect().encloses(start.start_button.get_global_rect()),"Prominent Start visible in scroll "+suffix)
		await snap("start-"+suffix)
		start.start_button.pressed.emit();await settle()
		var intro=start.intro
		expect(audio.is_speaking(&"narration.intro"),"Actual narration playing in "+suffix)
		for button:Button in intro.find_children("*","Button",true,false):
			expect(root.get_visible_rect().encloses(button.get_global_rect()),button.text+" inside "+suffix)
		await snap("intro-"+suffix)
		intro._on_pause();await snap("intro-paused-"+suffix)
		intro._on_settings();await settle()
		expect(scenes.get_popup(&"")==scenes.get_popup(&"Settings"),"Settings is top native popup "+suffix)
		await snap("intro-settings-"+suffix)
		scenes.close_popup(&"Settings");await settle()
		intro._on_menu();await settle()
	for setting in saved:state.set_setting(setting,saved[setting])
	audio.set_music_context(&"intro");audio.stop_dialogue();audio.voice.stream=null
	await create_timer(.3,true).timeout
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","views":pictures.size(),"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
