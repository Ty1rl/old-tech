extends SceneTree
const QUOTE := "An ancient device has turned exhibits into monsters. Survive with cobbled-together old tech and time borrowed from your future self."
var checks:=0
var failures:Array[String]=[]
var scenes:Node
var state:Node
var audio:Node
func _initialize() -> void:call_deferred("run")
func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);print("FAIL: ",message)
func settle(count:int=8)->void:
	for i in range(count):await process_frame
func transition_done()->void:
	await settle()
	while scenes.is_transitioning():await process_frame
	await settle()
func key(code:Key)->void:
	var e:=InputEventKey.new();e.physical_keycode=code;e.keycode=code;e.pressed=true;root.push_input(e)
	e=InputEventKey.new();e.physical_keycode=code;e.keycode=code;root.push_input(e)
func pointer(where:Vector2,down:bool)->void:
	var native:=where*Vector2(root.size)/root.get_visible_rect().size
	var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.position=native;e.global_position=native;e.pressed=down
	Input.parse_input_event(e);Input.flush_buffered_events()
func open_story(skip_all:bool=false)->Node:
	var popup=scenes.push_popup(&"NewGame");await settle()
	popup.hard.button_pressed=true;popup.skip_tutorials.button_pressed=skip_all;popup.start_button.pressed.emit();await settle()
	return popup.intro
func run()->void:
	create_timer(48,true).timeout.connect(func():push_error("Round S UI watchdog");quit(1))
	scenes=root.get_node("SceneManager");state=root.get_node("GameState");audio=root.get_node("AudioManager")
	var saved:Dictionary=state.preferences();var old_gate:bool=scenes.developer_tools
	state.set_setting("fullscreen",false);state.set_setting("sound",true);state.set_setting("voice_volume",.9);state.set_setting("tutorial",false)
	scenes.developer_tools=false
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main);current_scene=main;state.open_menu();await settle()
	expect(main.find_children("DeveloperButton","",true,false).is_empty(),"Main menu has no developer entry even before opt-in")
	var settings=scenes.push_popup(&"Settings");await settle()
	expect(not settings.developer_button.visible and settings.get_node_or_null("%Eyebrow")==null and settings.get_node_or_null("%Subtitle")==null,"Release Settings has no developer entry or redundant headers")
	settings._on_developer();await settle();expect(not scenes.has_popup(&"Developer"),"Hidden Settings developer callback is gated")
	scenes.close_popup(&"Settings");await settle()
	var pause=scenes.push_popup(&"PauseMenu");await settle()
	expect(pause.find_children("DeveloperButton","",true,false).is_empty(),"Pause has no separate developer entry")
	scenes.close_popup(&"PauseMenu");await settle()
	scenes.developer_tools=true;settings=scenes.push_popup(&"Settings");await settle()
	expect(settings.developer_button.visible,"Opt-in shows Developer options under Settings")
	settings.developer_button.pressed.emit();await settle();var developer=scenes.get_popup(&"Developer")
	expect(developer!=null and scenes.get_popup(&"")==developer,"Settings opens same native Developer popup")
	expect(developer.room_picker.item_count>0 and developer.encounter_picker.item_count>0 and developer.get_node("%SandboxButton").visible,"Developer contains encounter/boss/sandbox controls")
	developer.get_node("%BackButton").pressed.emit();await settle()
	expect(scenes.get_popup(&"")==settings and root.gui_get_focus_owner()==settings.developer_button,"Developer Back restores Settings focus")
	scenes.close_popup(&"Settings");await settle();scenes.developer_tools=false
	# Real supplied Round S recording, injected only into a duplicate library.
	var original:DialogueLibrary=audio.library;var supplied:DialogueLibrary=original.duplicate()
	supplied.clips=original.clips.duplicate()
	var recording:=AudioStreamMP3.load_from_file("/home/mattlongname/game-jams/projects/old-tech/new_audio/intro.mp3")
	supplied.clips[&"narration.intro"]=[recording];audio.library=supplied
	var intro=await open_story(true)
	expect(intro.quote.text==QUOTE,"Quote matches Matt's confirmed new recording transcript exactly")
	expect(intro.find_children("*","Button",true,false).size()==1 and intro.skip.text=="Skip" and intro.skip.focus_mode==Control.FOCUS_NONE,"Intro has only one click-only Skip and no keyboard focus")
	expect(intro.skip.pressed.get_connections().is_empty(),"Native keyboard/joypad Button pressed has no Skip connection")
	expect(intro.get_node_or_null("%Status")==null and intro.get_node_or_null("%Pause")==null,"No narration/status/action clutter")
	for code in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_SPACE,KEY_ENTER,KEY_TAB]:key(code)
	await settle()
	expect(intro.active and audio.is_speaking(&"narration.intro"),"WASD/Space/Enter/Tab do not skip narration")
	expect(root.gui_get_focus_owner()==null,"Intro never takes keyboard focus for Skip")
	Input.action_press("move_left")
	# Await REAL supplied speech; movement being held must not become a second confirm.
	while audio.is_speaking(&"narration.intro"):await create_timer(.1,true).timeout
	await transition_done()
	expect(current_scene!=null and current_scene.scene_file_path=="res://scenes/prototype/campaign.tscn","Natural speech completion automatically starts real campaign despite held movement")
	expect(scenes.params.difficulty==&"hard" and scenes.params.skip_tutorials,"Automatic transition preserves Hard and saved skip-all selection")
	Input.action_release("move_left")
	current_scene.set_physics_process(false)
	scenes.return_main();await transition_done()
	intro=await open_story()
	var point:Vector2=intro.skip.get_global_rect().get_center()
	pointer(point,true);await settle()
	expect(not audio.is_speaking(&"narration.intro") and intro.phase==intro.Phase.READY and intro.active,"Actual mouse click skips speech exactly once and waits for held attack release")
	pointer(point,false);await transition_done()
	expect(current_scene.scene_file_path=="res://scenes/prototype/campaign.tscn" and scenes.params.difficulty==&"hard" and not scenes.params.skip_tutorials,"Releasing click automatically starts selected taught run")
	current_scene.set_physics_process(false);scenes.return_main();await transition_done()
	intro=await open_story();scenes.close_popup(&"NewGame");await settle()
	expect(not audio.is_speaking(&"narration.intro") and not paused and current_scene.process_mode!=Node.PROCESS_MODE_DISABLED,"External cancellation restores speech, pause and underlying scene")
	for view in [Vector2i(1280,800),Vector2i(640,360)]:
		root.size=view;await settle()
		for name in [&"Settings",&"NewGame",&"PauseMenu",&"RunResult"]:
			var popup=scenes.push_popup(name);await settle()
			expect(root.get_visible_rect().encloses(popup.panel.get_global_rect()),String(name)+" panel fits "+str(view))
			for label:Label in popup.find_children("*","Label",true,false):
				expect(label.get_theme_font("font") in [load("res://assets/fonts/inter_regular.tres"),load("res://assets/fonts/inter_semibold.tres"),load("res://assets/fonts/BarlowCondensed-Black.ttf")],"Shared menu regular font: "+String(name)+"/"+String(label.name))
			scenes.close_popup(name);await settle()
	for setting in saved:state.set_setting(setting,saved[setting])
	scenes.developer_tools=old_gate;audio.stop_dialogue();audio.library=original;audio.set_music_context(&"intro");audio.voice.stream=null
	await create_timer(.3,true).timeout
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
