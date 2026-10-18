extends SceneTree
var checks := 0
var failures: Array[String] = []
var arena: Node3D
func _initialize() -> void: call_deferred("run")
func expect(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message)
func run() -> void:
	var script = load("res://scenes/prototype/campaign.gd")
	if script == null or not script.can_instantiate():
		expect(false,"Campaign compiles")
	else:
		arena = load("res://scenes/prototype/campaign.tscn").instantiate()
		root.add_child(arena);current_scene=arena
		await physics_frame
		await physics_frame
		root.get_node("GameState").start_game()
		arena.set_physics_process(false)
		expect(arena.room_index==0 and arena.mode==&"title","Fresh run enters first gallery")
		expect(arena.history.window_seconds==12 and arena.history.snapshot_limit==240,"Campaign keeps bounded twelve-second history")
		arena._physics_process(2.1)
		expect(arena.mode==&"pickup" and arena.museum.pickup_tool==2,"First gallery offers the yellow camera")
		arena.player.position=arena.museum.pickup_position+Vector3.UP*.55
		arena._physics_process(.001)
		expect(arena.tutorial.blocking and arena.lesson==&"shot","First shot mechanic freezes for explanation")
		var p:Vector3=arena.player.position
		Input.action_press("move_right")
		arena._physics_process(.1)
		Input.action_release("move_right")
		expect(arena.player.position==p,"Explanation freezes world movement")
		arena.tutorial.request_practice()
		expect(not arena.tutorial.blocking,"Practice resumes after demonstration")
		for index in range(4):
			arena.enter_room(index)
			expect(arena.cover.rectangles==arena.museum.active_cover_rectangles,"Room cover and movement/shot clipping agree")
			var collider_rects: Array = arena.museum.get_collider_world_rectangles(arena)
			var matching: bool = collider_rects.size()==arena.cover.rectangles.size()
			for i in range(mini(collider_rects.size(),arena.cover.rectangles.size())):
				matching = matching and collider_rects[i].is_equal_approx(arena.cover.rectangles[i])
			expect(matching,"Room collider footprints agree")
			arena.retry_room()
			expect(arena.player.health==100 and arena.history.snapshot_count==0,"Room retry heals and clears old-room history")
		var loop_wave := 0
		var definitions: Array = arena.Rooms.definitions()
		for wi in range(definitions[1].waves.size()):
			if definitions[1].waves[wi].lesson==&"loop": loop_wave=wi
		arena.debug_start(1,loop_wave)
		arena.tutorial.learned.erase(&"loop")
		arena.director.clear();arena.wave_index=loop_wave-1;arena._begin_wave()
		expect(arena.lesson==&"loop" and arena.specimens.size()==1,"First loop pattern lesson is solo")
		expect(arena.specimens[0].has_method("lesson_state"),"Campaign factory creates real pattern enemy")
		var saved:Dictionary=arena.capture_state()
		arena.director.clear()
		arena._restore_world(saved,arena.equipment.capacity(&"clock"))
		expect(arena.director.enemies[0].has_method("lesson_state"),"Rewind reconstructs real pattern class")
		expect(arena.specimens.size()==1 and arena.specimens[0].contact_damage==0,"Rebuilt practice specimen remains harmless and highlighted")
		for tick in range(260):arena.history.record(.05,arena.capture_state)
		expect(arena.history.snapshot_count==240 and arena.history.available_seconds>11.8,"Longer rewind retains twelve seconds with fixed count cap")
		var state: Node = root.get_node("GameState")
		var prior_tutorial: bool = state.preferences().tutorial
		state.set_setting("tutorial",false)
		arena._physics_process(.001)
		expect(arena.mode==&"pressure" and not arena.tutorial.blocking,"Disabling teaching releases the active practice gate")
		state.set_setting("tutorial",prior_tutorial)
		arena.tutorial.reset_run();arena.mode=&"pressure";arena.director.clear();arena.history.clear()
		arena.player.health=100;arena.history.record(.05,arena.capture_state)
		arena.player.take_damage(100);arena.history.record(.05,arena.capture_state)
		arena._physics_process(.01)
		expect(arena.weapons.selected_tool==4 and arena.player.health==0,"Lethal injury equips rewind instead of immediately locking out play")
		arena._begin_inspection();arena._seek_inspection(.05);arena._finish_inspection(true)
		expect(arena.player.health==100 and arena.room_index==1,"Lethal rewind restores health in the current room")
		var recovery=load("res://scenes/prototype/health_recovery.gd").new()
		recovery.damaged(20)
		expect(recovery.step(4,80,100)==80,"Fresh wound waits before healing")
		expect(recovery.step(2,80,100)==92,"Recent damage regenerates after quiet wait")
		recovery.damaged(5)
		expect(recovery.recoverable==5 and recovery.quiet==0,"Another wound restarts recovery without refilling old wounds")
		expect(recovery.step(99,0,100)==0,"Regeneration never revives a dead player")
		arena.feedback.reset_state();arena.queue_free()
		await process_frame
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
