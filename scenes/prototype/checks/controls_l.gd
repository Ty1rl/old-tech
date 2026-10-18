extends SceneTree
var checks := 0
var failures: Array[String] = []
var arena: Node3D
func _initialize() -> void: call_deferred("run")
func expect(value: bool, text: String) -> void:
	checks += 1
	if not value: failures.append(text)
func key(code: Key, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode=code; event.keycode=code;event.pressed=pressed
	root.push_input(event,true)
func run() -> void:
	arena=load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena); current_scene=arena
	await physics_frame;await physics_frame
	arena.set_physics_process(false)
	arena.director.clear()
	expect(arena.player.camera.projection==Camera3D.PROJECTION_PERSPECTIVE,"Gameplay uses perspective")
	var source := Vector3(2,0,-3)
	var screen: Vector2=arena.player.camera.unproject_position(source)
	expect(arena.floor_aim(screen).distance_to(source)<.01,"Perspective cursor ray maps to floor accurately")
	var distance:float=arena.player.camera.position.length()
	arena._set_zoom(18)
	expect(arena.player.camera.position.length()<distance,"Zoom moves perspective camera closer")
	arena.reset_arena();arena.director.clear()
	arena._physics_process(.01)
	expect(is_equal_approx(arena.player.camera.position.length(),distance),"Reset restores perspective camera distance")
	for i in range(30):
		arena.player.position.x=float(i)*.1
		arena.history.record(.05,arena.capture_state)
	key(KEY_SPACE)
	arena._physics_process(.01)
	expect(arena.player.world_scale<1,"Space starts slowing")
	for code in [KEY_2,KEY_3,KEY_1]:
		key(code)
		arena._physics_process(.01)
		expect(arena.player.world_scale<1 and not arena.history.inspecting,"Held Space survives switching among attack tools")
	var present:Vector3=arena.player.position
	key(KEY_4)
	expect(arena.history.inspecting,"Selecting clock while Space held starts review")
	arena._seek_inspection(.5)
	arena.scrub_view.step(1.0)
	expect(arena.player.position.distance_to(present)>.1,"Clock preview actually moves into history")
	key(KEY_2)
	expect(not arena.history.inspecting and arena.player.position.distance_to(present)<.01,"Switching away cancels uncommitted preview")
	arena._physics_process(.01)
	expect(arena.weapons.selected_tool==2 and arena.player.world_scale<1,"Switching out resumes held slow without new press")
	key(KEY_4);arena._seek_inspection(.5);key(KEY_SPACE,false)
	expect(not arena.history.inspecting and arena.player.position.distance_to(present)>.1,"Releasing Space commits chosen rewind")
	arena._physics_process(.01)
	expect(arena.player.world_scale==1,"Releasing Space resumes normal time")
	var tools:Array[int]=[2,3]
	arena.weapons.set_loadout(tools,2)
	key(KEY_SPACE)
	arena._physics_process(.01)
	expect(arena.player.world_scale==1,"Slow is unavailable before purple is collected")
	key(KEY_SPACE,false)
	key(KEY_1);expect(arena.weapons.selected_tool==2,"Uncollected tool rejects numeric selection")
	key(KEY_TAB);expect(arena.weapons.selected_tool==3,"Tab reaches collected tool")
	key(KEY_TAB);expect(arena.weapons.selected_tool==2,"Tab skips locked tools and wraps")
	arena.weapons.mouse_held=true
	key(KEY_3)
	expect(arena.weapons.require_fresh_press and not arena.weapons.cone_active,"Switching with mouse held cannot fire the new tool")
	key(KEY_SPACE)
	arena.player._step_slow(.01,true)
	arena._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(not arena._space_held and not arena.history.inspecting and root.get_node("GameState").state==root.get_node("GameState").State.PAUSED,"Focus loss clears held Space safely")
	root.get_node("GameState").start_game()
	arena.queue_free();await process_frame
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
