extends SceneTree
const OUT := "/home/mattlongname/game-jams/state/old-tech-jam-7/exports/round-s"
var pictures:Array[String]=[]
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func settle(count:int=12)->void:
	for i in range(count):await process_frame
func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)
func snap(name:String)->void:
	await settle();await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(OUT+"/"+name+".png")==OK,"Save "+name)
	pictures.append(name)
func run()->void:
	create_timer(40,true).timeout.connect(func():push_error("Round S capture watchdog");quit(1))
	var state=root.get_node("GameState");var scenes=root.get_node("SceneManager");var audio=root.get_node("AudioManager")
	var saved:Dictionary=state.preferences();var gate:bool=scenes.developer_tools
	state.set_setting("fullscreen",false);state.set_setting("sound",true);state.set_setting("voice_volume",.9)
	var library:DialogueLibrary=audio.library.duplicate();library.clips=audio.library.clips.duplicate()
	library.clips[&"narration.intro"]=[AudioStreamMP3.load_from_file("/home/mattlongname/game-jams/projects/old-tech/new_audio/intro.mp3")];audio.library=library
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main);current_scene=main;state.open_menu();await settle()
	for resolution in [Vector2i(1280,800),Vector2i(640,360)]:
		root.size=resolution;await settle()
		var suffix:="normal" if resolution.x>640 else "compact"
		scenes.developer_tools=false;await snap("main-"+suffix)
		var settings=scenes.push_popup(&"Settings");await settle()
		expect(not settings.developer_button.visible,"Developer hidden in release "+suffix)
		await snap("settings-"+suffix)
		scenes.close_popup(&"Settings");await settle()
		scenes.developer_tools=true;settings=scenes.push_popup(&"Settings");await settle()
		settings.developer_button.grab_focus();await settle();await snap("settings-developer-"+suffix)
		settings.developer_button.pressed.emit();await settle()
		var dev=scenes.get_popup(&"Developer")
		expect(root.get_visible_rect().encloses(dev.panel.get_global_rect()),"Developer panel fits "+suffix)
		await snap("developer-"+suffix)
		scenes.close_popup(&"Developer");scenes.close_popup(&"Settings");await settle()
		var new_game=scenes.push_popup(&"NewGame");await settle();new_game.start_button.grab_focus();await snap("new-game-"+suffix)
		new_game.start_button.pressed.emit();await settle()
		var intro=new_game.intro
		expect(audio.is_speaking(&"narration.intro"),"Supplied new intro plays "+suffix)
		expect(root.get_visible_rect().encloses(intro.skip.get_global_rect()),"Click Skip fits "+suffix)
		expect(root.get_visible_rect().encloses(intro.quote.get_global_rect()),"Exact quote fully fits "+suffix)
		await snap("intro-"+suffix)
		scenes.close_popup(&"NewGame");await settle()
	for setting in saved:state.set_setting(setting,saved[setting])
	scenes.developer_tools=gate;audio.stop_dialogue();audio.set_music_context(&"intro");audio.voice.stream=null;await create_timer(.3,true).timeout
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"views":pictures.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
