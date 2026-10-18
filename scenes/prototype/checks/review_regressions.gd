extends SceneTree
var checks:=0
var failures:Array[String]=[]
var arena:Node3D
func _initialize()->void:call_deferred("run")
func expect(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message)
func mouse(down:bool)->InputEventMouseButton:
	var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;return e
func run()->void:
	arena=load("res://scenes/prototype/arena.tscn").instantiate();root.add_child(arena);current_scene=arena
	await physics_frame;await physics_frame
	root.get_node("GameState").start_game();arena.set_physics_process(false)
	for kind:StringName in [&"loop",&"zigzag",&"final_boss"]:
		for scale in [1.0,.18]:
			for offset in range(3):
				arena.reset_arena();arena.director.clear();arena.cover.set_rectangles([])
				var enemy:Node3D=arena.director.spawn(kind,Vector3(0,0,-5))
				if kind==&"final_boss":enemy.phase=3
				enemy._open_pattern();enemy._build_visuals();enemy._update_visual_facing()
				var core:Vector3=enemy.core_world_position()
				arena.player.position=core-Vector3(sin(deg_to_rad(75)),0,cos(deg_to_rad(75)))*(7+offset*.08)
				arena.weapons.select_tool(2)
				arena.weapons.handle_event(mouse(true),arena.player,core)
				arena.weapons.step(1,arena.player,core,[],0)
				arena.weapons.handle_event(mouse(false),arena.player,core)
				for tick in range(100):arena.weapons.step(1.0/60,arena.player,core,arena.director.enemies,scale/60)
				expect(enemy.health<=0,"Off-axis charged finisher hits actual exposed "+String(kind)+" core at scale "+str(scale))
	for scale in [1.0,.18]:
		arena.reset_arena();arena.director.clear();arena.cover.set_rectangles([])
		var pair: Node3D = arena.director.spawn(&"pair",Vector3(0,0,-5))
		for sensor in range(2):
			var aim: Vector3 = pair.valve_world_position(sensor)
			arena.player.position=aim-Vector3(sin(deg_to_rad(75)),0,cos(deg_to_rad(75)))*7
			arena.weapons.select_tool(2)
			arena.weapons.handle_event(mouse(true),arena.player,aim)
			arena.weapons.handle_event(mouse(false),arena.player,aim)
			for tick in range(100):arena.weapons.step(1.0/60,arena.player,aim,arena.director.enemies,scale/60)
		expect(pair.health<=0,"Off-axis quick A/B shots select the active sensor at scale "+str(scale))
	arena.reset_arena();arena.director.clear()
	var boss:Node3D=arena.director.spawn(&"final_boss",Vector3(0,0,-5))
	var start:Vector3=boss.position
	boss.apply_control(Vector3.FORWARD,22,.85)
	expect(boss.stagger_timer<.9,"Boss cone stagger stays bounded")
	for tick in range(60):boss.step_enemy(1.0/60,null)
	expect(boss.position.distance_to(start)<.6,"Heavy boss no longer flies seven metres from one cone pulse")
	var visual:Node3D=boss.pattern_visual
	var material:Material=visual.valves[0].material_override
	for tick in range(60):boss._update_warden_visuals()
	expect(visual.valves[0].material_override==material,"Pattern sync reuses valve material")
	boss.restore_state(boss.capture_state())
	expect(boss.pattern_visual==visual,"Same-phase rewind reuses pattern visual tree")
	arena.feedback.reset_state();arena.queue_free();await process_frame
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
