extends SceneTree
## Real GameState/config + authored controls; no SceneManager transport stub.
## Cross-seat start_play third-argument verification requires JAM-5's delivery.
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message)
func settle(count: int = 8) -> void:
	for i in range(count):await process_frame
func run() -> void:
	create_timer(15,true).timeout.connect(func():push_error("Round R preference watchdog");quit(1))
	var state=root.get_node("GameState");var scenes=root.get_node("SceneManager");var audio=root.get_node("AudioManager")
	var saved: Dictionary=state.preferences()
	state.set_setting("sound",true);state.set_setting("volume",.8);state.set_setting("voice_volume",.9)
	state.set_setting("fullscreen",false)
	var config:=ConfigFile.new();config.load(state.SETTINGS_PATH)
	if config.has_section_key("settings","skip_tutorials"):config.erase_section_key("settings","skip_tutorials")
	expect(config.save(state.SETTINGS_PATH)==OK,"Can create genuine pre-flag preference file in isolated seat userdata")
	state._preferences.skip_tutorials=true;state.reload_preferences()
	expect(not state.preferences().skip_tutorials,"Older saves default Skip tutorials off")
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main);current_scene=main;state.open_menu();await settle()
	var popup=scenes.push_popup(&"NewGame");await settle()
	expect(not popup.skip_tutorials.button_pressed and popup.selected_difficulty()==&"easy","Authored checkbox defaults off independently of Easy")
	popup.skip_tutorials.button_pressed=true;await settle()
	expect(state.preferences().skip_tutorials,"Native checkbox toggled signal updates actual preference mechanism")
	config.load(state.SETTINGS_PATH)
	expect(config.get_value("settings","skip_tutorials",false)==true,"Preference writes real existing settings file")
	popup.hard.button_pressed=true;await settle()
	expect(popup.skip_tutorials.button_pressed and popup.selected_difficulty()==&"hard","Changing difficulty retains independent checkbox")
	var tutorial_before:bool=state.preferences().tutorial
	state.set_setting("tutorial",not tutorial_before);await settle()
	expect(popup.skip_tutorials.button_pressed and state.preferences().skip_tutorials,"Existing tutorial hint preference is separate from Skip tutorials")
	scenes.close_popup(&"NewGame");await settle()
	state._preferences.skip_tutorials=false;state.reload_preferences()
	expect(state.preferences().skip_tutorials,"Reload reads the saved checkbox value rather than stale memory")
	popup=scenes.push_popup(&"NewGame");await settle()
	expect(popup.skip_tutorials.button_pressed and popup.selected_difficulty()==&"easy","Reopened New Game restores skip flag while difficulty resets to Easy")
	popup.hard.button_pressed=true;popup.start_button.pressed.emit();await settle()
	var intro=popup.intro
	expect(intro.active and intro._difficulty==&"hard" and intro._skip_tutorials,"Start snapshots Hard and skip flag into authored intro")
	expect(audio.is_speaking(&"narration.intro") and current_scene==main,"Skip tutorials leaves story narration active before Campaign construction")
	state.set_setting("skip_tutorials",false)
	expect(intro._skip_tutorials,"In-flight run keeps the Start selection even if saved preference later changes")
	intro._on_menu();await settle()
	expect(scenes.get_popup(&"NewGame")==null and not audio.is_speaking(&"narration.intro"),"Cancelling skip-enabled story cleans up without starting a run")
	popup=scenes.push_popup(&"NewGame");await settle()
	expect(not popup.skip_tutorials.button_pressed,"Unchecking persists independently for the next New Game")
	scenes.close_popup(&"NewGame");await settle()
	for setting in saved:state.set_setting(setting,saved[setting])
	audio.stop_dialogue();audio.set_music_context(&"intro");audio.voice.stream=null;await create_timer(.25,true).timeout
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"scope":"real preference/controls; JAM-5 third-argument transport requires integration, never stubbed"}));quit(0 if failures.is_empty() else 1)
