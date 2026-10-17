extends SceneTree

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func run() -> void:
	var packed := load("res://scenes/prototype/arena.tscn") as PackedScene
	var arena = packed.instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	var state = root.get_node("GameState")
	var scenes = root.get_node("SceneManager")
	expect(state.is_playing() and not paused, "Direct arena launch enters playing state")
	expect(arena.player.camera.current, "Prototype camera is current")
	expect(arena.player.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Top-down camera is orthographic")
	var origin: Vector3 = arena.player.position
	Input.action_press("move_right")
	for frame in range(8):
		await physics_frame
	Input.action_release("move_right")
	expect(arena.player.position.x > origin.x + 0.1, "WASD input moves the inherited player")
	var popup: Node = scenes.push_popup(&"PauseMenu")
	expect(popup != null and not paused, "Popup can open without pausing world simulation")
	scenes.close_popup(&"PauseMenu")
	await process_frame
	state.pause()
	expect(paused and scenes.has_popup(&"PauseMenu"), "Existing pause flow opens popup and pauses")
	state.resume()
	await process_frame
	expect(not paused and not scenes.has_popup(), "Existing resume clears pause popup")
	arena.player.take_damage(12.0)
	expect(arena.player.health < 100.0, "Player receives contact damage")
	arena.reset_arena()
	expect(arena.player.health == 100.0 and arena.player.velocity == Vector3.ZERO, "Reset restores player health and clears motion")
	expect(arena.player.world_scale == 1.0, "Reset restores normal world time")
	expect(Engine.time_scale == 1.0, "Prototype leaves engine clock unscaled")
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
