extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)

func run() -> void:
	var ceiling := float(CombatFlow.Tuning.ARENA_HALF_SIZE) - CombatFlow.BOTTOM_SPAWN_MARGIN
	for difficulty in [&"easy", &"hard"]:
		for room: Dictionary in load("res://scenes/prototype/rooms.gd").definitions(difficulty):
			var cover: RefCounted = load("res://scenes/prototype/cover.gd").new(room.cover)
			for position in [Vector3.ZERO, Vector3(0, 0, 12), Vector3(0, 0, -14)]:
				for seed in range(8):
					var flow := CombatFlow.new()
					var slots := flow.layout(&"mixed", [&"blue", &"yellow", &"orange", &"ranged"], position, cover, seed, [])
					expect(slots.size() == 4, "Entrance exclusion preserves ordinary reinforcement capacity")
					for slot: Dictionary in slots:
						expect(slot.position.z + slot.radius <= ceiling, "Whole enemy stays clear of the near wall and bottom doorway")
						expect(CombatFlow.safe(slot.position, slot.radius, position, cover), "Arrival still respects cover and player clearance")
	var scenes := root.get_node("SceneManager")
	scenes.params = {"difficulty": &"easy", "skip_tutorials": false}
	var arena: Node3D = load("res://scenes/prototype/campaign.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	root.get_node("AudioManager").set_music_context(&"intro")
	arena.set_physics_process(false)
	arena.set_process(false)
	for index in range(arena.waves.size()):
		if arena.waves[index].get("lesson") == &"slow": arena.wave_index = index
	arena.mode = &"practice"
	arena.lesson = &"slow"
	arena._practice_stage = &"stationary"
	arena._stationary_quota = 2
	arena._moving_quota = 2
	arena.acquired.assign([2, 3])
	arena.tutorial.learned.erase(&"slow")
	arena.tutorial.blocking = false
	arena._spawn_practice()
	expect(arena.director.enemies.size() == 1 and arena.specimens.size() == 1, "Slow-time practice starts with one live target")
	var target: Node3D = arena.specimens[0]
	var old_id: int = target.rewind_id
	var point: Vector3 = target.core_world_position()
	target.receive_attack(&"beam", 100.0, point, {"segment_start": point - Vector3(0, 0, 3), "segment_end": point + Vector3(0, 0, 3), "radius": .35, "charge": 0.0})
	arena._slow_used = true
	arena._physics_process(.01)
	expect(arena._stationary_done == 1 and arena.specimens.is_empty() and arena.director.enemies.is_empty(), "Successful shot leaves an unmistakable empty gap, not an immediate replacement")
	arena._physics_process(.2)
	expect(arena.specimens.is_empty(), "Target remains absent during the visible pause")
	var saved: Dictionary = arena._capture_practice()
	expect(float(saved.spawn_delay) > .2, "Pending arrival delay is included in rewind/checkpoint state")
	arena._physics_process(.3)
	expect(arena.specimens.size() == 1 and arena.director.enemies.size() == 1, "Exactly one next target appears after the gap")
	expect(arena.specimens[0].rewind_id != old_id, "Next repetition is a distinct target")
	arena.director.clear()
	arena.specimens.clear()
	arena._restore_practice(saved)
	arena._physics_process(.1)
	expect(arena.specimens.is_empty(), "Restoring a pending arrival does not create a target early")
	arena._physics_process(.3)
	expect(arena.specimens.size() == 1 and arena.director.enemies.size() == 1, "Restored pending arrival spawns exactly once")
	arena._queue_practice_spawn()
	arena.tutorial.learned[&"slow"] = true
	arena._physics_process(.01)
	expect(arena.mode != &"practice" and arena._practice_spawn_delay == 0.0, "Already learned lessons skip immediately even when a restored target was pending")
	arena.feedback.reset_state()
	root.get_node("AudioManager").set_music_context(&"intro")
	arena.queue_free()
	await process_frame
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	if failures.is_empty(): root.get_node("AudioManager").request_quit()
	else: quit(1)
