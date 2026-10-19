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
		var easy_res = load("res://scenes/prototype/settings/difficulty_easy.tres")
		var hard_res = load("res://scenes/prototype/settings/difficulty_hard.tres")
		expect(easy_res is CampaignDifficulty and hard_res is CampaignDifficulty, "Easy and Hard CampaignDifficulty resources load cleanly")
		root.get_node("GameState").set_setting("tutorial", true)
		root.get_node("SceneManager").params = {}
		arena = load("res://scenes/prototype/campaign.tscn").instantiate()
		root.add_child(arena);current_scene=arena
		await physics_frame
		await physics_frame
		root.get_node("GameState").start_game()
		arena.set_physics_process(false)
		expect(arena.room_index==0 and arena.mode==&"title","Fresh run enters first gallery")
		expect(not arena.time_controller.slow_unlocked and not arena.time_controller.rewind_unlocked,"Fresh run starts with slow and rewind capabilities locked")
		expect(arena.history is ReplayHistory and arena.history.window_seconds==18.0 and arena.history.max_snapshots==240,"Campaign keeps bounded eighteen-second ReplayHistory")
		expect(arena.history.has_checkpoint,"Fresh room seeds safe fallback checkpoint")
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
			expect(is_equal_approx(arena.time_controller.meter,arena.time_controller.capacity) and arena.time_controller.charges_remaining==3 and arena.history.snapshot_count==0 and arena.history.has_checkpoint,"Room retry starts fresh attempt and clears old-room rolling history while seeding checkpoint")
		var loop_wave := 0
		var definitions: Array = arena.Rooms.definitions()
		for wi in range(definitions[1].waves.size()):
			if definitions[1].waves[wi].lesson==&"loop": loop_wave=wi
		arena.debug_start(1,loop_wave)
		expect(arena.time_controller.slow_unlocked and arena.time_controller.rewind_unlocked,"Later checkpoint unlocks slow and rewind capabilities")
		arena.tutorial.learned.erase(&"loop")
		arena.director.clear();arena.wave_index=loop_wave-1;arena._begin_wave()
		expect(arena.lesson==&"loop" and arena.specimens.size()==1,"First loop pattern lesson is solo")
		expect(arena.specimens[0].has_method("lesson_state"),"Campaign factory creates real pattern enemy")
		var saved:Dictionary=arena.capture_state()
		arena.director.clear()
		arena.restore_campaign_state(saved)
		expect(arena.director.enemies[0].has_method("lesson_state"),"Rewind reconstructs real pattern class")
		expect(arena.specimens.size()==1 and arena.specimens[0].contact_damage==0,"Rebuilt practice specimen remains harmless and highlighted")
		for tick in range(260):arena.history.record(.05,arena.capture_state)
		expect(arena.history.snapshot_count>=150 and arena.history.snapshot_count<=240 and arena.history.age_of(0)>11.8,"Longer rewind retains history within fixed count cap")
		var state: Node = root.get_node("GameState")
		var prior_tutorial: bool = state.preferences().tutorial
		state.set_setting("tutorial",false)
		arena._physics_process(.001)
		expect(arena.mode==&"pressure" and not arena.tutorial.blocking,"Disabling teaching releases the active practice gate")
		state.set_setting("tutorial",prior_tutorial)
		arena.tutorial.reset_run();arena._slow_unlocked=true;arena._rewind_unlocked=true;arena._apply_time_capabilities()
		arena.mode=&"pressure";arena.director.clear();arena._seed_room_checkpoint()
		arena.time_controller.begin_attempt()
		arena.history.record(.05,arena.capture_state)
		arena.time_controller.apply_hit(100.0)
		expect(arena.is_emergency_active() and arena.time_controller.charges_remaining==2,"Depleting hit spends one emergency charge and opens emergency rewind")
		arena.emergency_rewind.step_selection(1)
		arena.emergency_rewind.confirm()
		expect(not arena.is_emergency_active() and arena.time_controller.meter>=arena.time_controller.settings.recovery_floor and arena.room_index==1,"Emergency rewind restores world state and recovery floor in the current room")
		arena.feedback.reset_state();arena.queue_free()
		await process_frame
		await create_timer(0.3).timeout
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
