extends SceneTree
var checks := 0
var failures: Array[String] = []
var arena: Node3D
func _initialize() -> void: call_deferred("run")
func expect(value: bool,message: String) -> void:
	checks+=1
	if not value: failures.append(message)
func mouse(down: bool) -> InputEventMouseButton:
	var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;return e
func space(down: bool) -> void:
	var e:=InputEventKey.new();e.physical_keycode=KEY_SPACE;e.pressed=down;arena._input(e)
func shot(enemy: Node3D, charge: float=1.0) -> void:
	var point:Vector3=enemy.core_world_position()
	enemy.receive_attack(&"beam",100,point,{"segment_start":point-Vector3(0,0,5),"segment_end":point+Vector3(0,0,5),"radius":.35,"charge":charge})
func cut(enemy: Node3D) -> void:
	var points:Array=enemy.cable_world_points()
	var pairs:bool=enemy.has_method("lesson_state")
	var step:int=2 if pairs else 1
	for i in range(0,points.size()-1,step):
		var middle:Vector3=(points[i]+points[i+1])*.5
		var direction:Vector3=(points[i+1]-points[i]).normalized().cross(Vector3.UP)
		enemy.receive_attack(&"ring",36,middle,{"segment_start":middle-direction*.7,"segment_end":middle+direction*.7,"radius":.1,"already_hit":i>0})
func pattern(enemy: Node3D) -> void:
	if enemy.active_pattern()==&"pair":
		for i in range(2):
			var p:Vector3=enemy.valve_world_position(i)
			enemy.receive_attack(&"beam",30,p,{"segment_start":p-Vector3(0,0,1),"segment_end":p+Vector3(0,0,1),"radius":.1,"charge":0})
	elif enemy.active_pattern() in [&"loop",&"zigzag"]:cut(enemy)
	if enemy.health>0:shot(enemy)
func practice() -> void:
	var lesson:StringName=arena.lesson
	if arena.tutorial.blocking:arena.tutorial.request_practice()
	if lesson==&"move":arena.player.position+=Vector3(3,0,0)
	elif lesson==&"repair":
		var session:int=arena.equipment.begin_repair(&"beam")
		arena.equipment.complete_step(&"beam",session)
		arena.equipment.end_repair(session)
	elif lesson==&"rewind":
		for tick in range(40):arena._physics_process(.05)
		expect(arena.player.health==80,"Rewind lesson creates a safe recoverable injury")
		arena.weapons.select_tool(4);arena._begin_inspection();arena._seek_inspection(1.0);arena._finish_inspection(true)
		expect(arena.player.health==100,"Rewind actually restores pre-injury health")
	elif lesson==&"charge":
		arena.weapons.select_tool(2)
		var aim:Vector3=arena.specimens[0].position
		arena.weapons.handle_event(mouse(true),arena.player,aim)
		arena.weapons.step(1,arena.player,aim,arena.director.enemies,0)
		arena.weapons.handle_event(mouse(false),arena.player,aim)
		arena.weapons.step(.7,arena.player,aim,arena.director.enemies,.7)
		expect(arena._charged_kills.size()>=2 and arena._pierced,"Real charged traveling pulse pierces yellow practice line")
	else:
		if lesson==&"slow":space(false);space(true);arena._physics_process(.01)
		for enemy in arena.specimens:
			if not is_instance_valid(enemy):continue
			if lesson in [&"cut",&"slow"]:cut(enemy)
			elif lesson==&"heat":
				for tick in range(80):enemy.receive_attack(&"cone",.3,enemy.position,{"dt":1.0/60})
			elif lesson==&"opening":cut(enemy);shot(enemy)
			elif enemy.has_method("active_pattern"):
				for phase in range(4):
					if enemy.health>0:pattern(enemy)
			else:shot(enemy,0)
	arena._physics_process(.001)
	space(false)
	expect(arena.tutorial.is_learned(lesson),"Actual practice gate completed: "+String(lesson))
func run() -> void:
	var state=root.get_node("GameState")
	var old:bool=state.preferences().tutorial
	state.set_setting("tutorial",true)
	arena=load("res://scenes/prototype/campaign.tscn").instantiate();root.add_child(arena);current_scene=arena
	await physics_frame;await physics_frame
	state.start_game();arena.set_physics_process(false)
	var visited:Dictionary={}
	for step in range(600):
		visited[arena.room_index]=true
		if arena.mode==&"won":break
		if arena.mode in [&"title",&"ceremony"]:arena._physics_process(3.0)
		elif arena.mode==&"pickup":
			arena.player.position=arena.museum.pickup_position+Vector3.UP*.55
			arena._physics_process(.001)
		elif arena.mode==&"practice":practice()
		elif arena.mode==&"pressure":
			for enemy in arena.director.enemies:enemy.hit(99999,enemy.position)
			arena._physics_process(9.0)
		elif arena.mode==&"recovery":arena._physics_process(7)
		elif arena.mode==&"exit":arena.player.position=arena.room.exit_door.position;arena._physics_process(.001)
		await process_frame
		if not failures.is_empty():break
	expect(visited.size()==4,"Run reaches all four museum rooms")
	expect(arena.mode==&"won","Taught progression reaches final boss win")
	root.get_node("SceneManager").clear_popups();state.start_game();state.set_setting("tutorial",old)
	arena.feedback.reset_state();arena.queue_free();await process_frame
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
