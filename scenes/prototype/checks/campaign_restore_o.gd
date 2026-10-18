extends SceneTree
## Regression coverage for recovery into practice, pickups and room-start fallback.
var arena: Node3D
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func run() -> void:
	var game := root.get_node("GameState")
	var prefs: Dictionary = game.preferences()
	game.set_setting("tutorial", true)
	arena = load("res://scenes/prototype/campaign.tscn").instantiate()
	root.add_child(arena); current_scene = arena
	await physics_frame
	arena.set_physics_process(false)
	arena.debug_start(2, 0)
	arena.tutorial.learned.erase(&"zigzag")
	arena._begin_wave()
	arena.tutorial.request_practice()
	arena._practice_age = .5
	var practice: Dictionary = arena.capture_state()
	arena._cut = true
	arena._kills[123] = true
	arena._practice_age = 9.0
	arena.museum.set_exit_open(true)
	arena.restore_campaign_state(practice)
	expect(arena.mode == &"practice" and arena.lesson == &"zigzag", "Restore actual unlearned practice")
	expect(not arena._cut and arena._kills.is_empty(), "Discard success from actions later than the snapshot")
	expect(is_equal_approx(arena._practice_age, .5), "Restore the practice clock with the world")
	expect(not arena.museum.exit_open, "Restoring practice closes a future room exit")
	var available: Array = arena.acquired.duplicate()
	arena.start_new_run(&"easy")
	var room_start: Dictionary = arena.capture_state()
	arena.debug_start(0, 2)
	arena.restore_campaign_state(room_start)
	expect(arena.mode == &"title" and arena.wave_index == -1, "Room-start fallback restores title and pre-wave scheduler")
	expect(arena.acquired == [2, 3], "Checkpoint fallback preserves acquired tools")
	arena._physics_process(2.1)
	expect(arena.mode == &"pressure", "Room-start fallback progresses without repeating learned lessons")
	arena.debug_start(2, 2)
	arena.director.clear()
	arena.wave_index = arena.waves.size() - 1
	arena._begin_wave()
	var exit_state: Dictionary = arena.capture_state()
	arena.debug_start(2, 1)
	arena.restore_campaign_state(exit_state)
	expect(arena.mode == &"exit" and arena.museum.exit_open, "Room-end snapshot restores its real exit")
	expect(arena.wave_index == arena.waves.size(), "Exit snapshot preserves the after-last-wave index")
	var before: int = arena.room_index
	arena.player.position = arena.room.exit_door.position
	arena._physics_process(.01)
	expect(arena.room_index == before + 1, "Restored open exit still advances to the next room")
	root.get_node("SceneManager").clear_popups()
	arena.feedback.reset_state(); arena.queue_free(); await process_frame
	await create_timer(.3).timeout
	for setting in prefs: game.set_setting(setting, prefs[setting])
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
