extends SceneTree
## Real campaign/controllers and supplied MP3s, with exact speech/exit race staging.
var checks:=0
var failures: Array[String]=[]
var handoffs:=0
var cancels:=0
var completed:=0
var exit_active: Array[bool]=[]
var terminals: Array[Dictionary]=[]
var manager: Node
var audio: Node
var watched_scene: Node
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, text: String) -> void:
	checks+=1
	if not ok: failures.append(text)
func done() -> void:
	while manager.is_transitioning(): await process_frame
func terminal(event: StringName, interrupted: bool) -> void:
	terminals.append({"event":event,"interrupted":interrupted,"inside_tree":is_instance_valid(watched_scene) and watched_scene.is_inside_tree(),"handoffs":handoffs})
func campaign() -> Node:
	expect(manager.start_play(false,&"easy",false),"Real campaign start accepted")
	await done()
	current_scene.set_physics_process(false)
	watched_scene=current_scene
	return current_scene
func arm(arena: Node) -> Node:
	arena._cancel_active_teaching_controllers()
	audio.stop_dialogue()
	arena.tutorial.reset_run()
	var loadout: Array[int]=[2]
	arena.acquired.assign(loadout);arena.weapons.set_loadout(loadout,2)
	var targets: Array[Vector3]=[arena.player.position+Vector3(0,1,-4)]
	arena.tutorial.show_lesson(&"shot","Flash","",targets)
	expect(arena.lesson_demo.begin(arena,&"shot",arena.tutorial),"Actual yellow demo begins")
	arena.mode=&"demo";arena.lesson=&"shot"
	var demo=arena.lesson_demo
	demo.ready_for_practice.connect(func(_id): handoffs+=1)
	demo.demo_cancelled.connect(func(_id): cancels+=1)
	demo.demo_completed.connect(func(_id,_summary): completed+=1)
	arena.tree_exiting.connect(func(): exit_active.append(demo.active))
	demo._pass_completed=true
	expect(audio.say(&"tutorial.shot",3),"Supplied instruction speech accepted")
	expect(audio.instruction_busy() and demo.active,"Demo awaits real speech")
	return demo
func run() -> void:
	create_timer(45,true).timeout.connect(func(): print(JSON.stringify({"status":"failed","checks":checks,"failures":failures+["lifecycle watchdog"]}));quit(1))
	manager=root.get_node("SceneManager");manager.fade_duration=.01
	audio=root.get_node("AudioManager")
	var state=root.get_node("GameState")
	var prefs: Dictionary=state.preferences()
	state.set_setting("sound",true);state.set_setting("voice_volume",.9)
	audio.speech_finished.connect(terminal)
	# Completed visual pass, unfinished speech, repair popup, then real scene exit.
	var arena=await campaign()
	var demo=arm(arena)
	var repair=manager.push_popup(&"Repair",{"arena":arena,"equipment":arena.equipment,"time_controller":arena.time_controller,"available_tools":[2],"allow_full_preview":true})
	expect(repair!=null,"Actual repair popup coexists with outgoing scope")
	terminals.clear()
	manager.go_to(&"Main",{},false)
	expect(arena.tutorial.process_mode==Node.PROCESS_MODE_DISABLED and demo.process_mode==Node.PROCESS_MODE_DISABLED,"ALWAYS teaching nodes freeze during transition")
	await done()
	expect(handoffs==0 and completed==0 and cancels==1,"Leaving cancels once without practice or completion")
	expect(exit_active==[false],"Demo already inactive before tree_exiting")
	expect(not terminals.is_empty(),"Global speech lifetime observers retain cancellation")
	for item in terminals: expect(item.interrupted and item.inside_tree,"Speech interruption precedes outgoing detachment")
	expect(not manager.has_popup() and current_scene.scene_file_path=="res://scenes/main.tscn","Destination owns scene and old popup is cleared")
	# Cancellation/failure must keep the old demo and restore exact listeners/modes.
	arena=await campaign();demo=arm(arena)
	var before_handoffs:=handoffs
	var before_cancels:=cancels
	manager.go_to(&"Main")
	expect(manager.cancel_transition(),"Pending navigation cancels")
	audio.stop_dialogue()
	expect(handoffs==before_handoffs and demo.active,"Interrupted speech cannot grant practice during cancelled loading")
	await done()
	expect(current_scene==arena and demo.active and cancels==before_cancels,"Cancel preserves original teaching session")
	expect(arena.tutorial.process_mode==Node.PROCESS_MODE_ALWAYS and demo.process_mode==Node.PROCESS_MODE_ALWAYS,"Cancel restores explicit ALWAYS modes")
	var restored:=0
	for connection in audio.get_signal_connection_list(&"speech_finished"):
		if connection.callable.get_object()==demo: restored+=1
	expect(restored==1,"Cancel restores exactly one demo speech receiver")
	expect(audio.say(&"tutorial.shot",3),"Restored demo accepts supplied speech again")
	manager._change(&"BadResource","res://scenes/navigation/navigation_settings.tres",{},false)
	await done()
	expect(current_scene==arena and demo.active and cancels==before_cancels,"Failed destination preserves active demo")
	expect(manager.last_transition_profile.status=="failed","Actual wrong-type resource follows failure path")
	manager._loading_cancel.pressed.emit()
	expect(audio.instruction_busy(),"Failed destination leaves original speech available")
	# Drive the actual AudioStreamPlayer completion signal to verify restored
	# natural completion; interruption is deliberately not used as a positive case.
	audio.voice.stop();audio.voice.finished.emit()
	expect(handoffs==before_handoffs+1 and completed==1,"Natural completion still hands off exactly once after restore")
	manager.go_to(&"Main",{},false);await done()
	# Campaign's independent await-speech receiver must also remain quiescent.
	arena=await campaign()
	arena.mode=&"practice";arena._practice_stage=&"await_speech"
	expect(audio.say(&"tutorial.shot",3),"Campaign await-speech stage uses real speech")
	manager.go_to(&"Main")
	audio.stop_dialogue()
	expect(arena._practice_stage==&"await_speech","Transition interruption cannot create stationary practice")
	await done()
	# Specialized forced-rewind cancellation must not fire completion.
	arena=await campaign()
	var forced=arena.rewind_lesson
	var forced_completions: Array[int]=[0]
	forced.completed.connect(func(): forced_completions[0]+=1)
	expect(forced.begin(arena),"Real forced-rewind lesson begins")
	var forced_exit: Array[bool]=[]
	arena.tree_exiting.connect(func(): forced_exit.append(forced.active))
	manager.go_to(&"Main",{},false);await done()
	expect(forced_completions[0]==0 and forced_exit==[false],"Forced rewind cancels while attached without completion")
	audio.stop_dialogue();audio.set_music_context(&"intro")
	current_scene.queue_free();await process_frame
	for setting in prefs: state.set_setting(setting,prefs[setting])
	state.open_menu()
	await create_timer(.4).timeout
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
