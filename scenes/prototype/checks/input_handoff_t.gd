extends SceneTree
## Route real viewport events through both tutorial and gameplay input handlers.
var checks := 0
var failures: Array[String] = []
var arena: Node3D
var tutorial: Control

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func settle() -> void:
	for i in 4: await process_frame

func click(pressed: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point * Vector2(root.size) / root.get_visible_rect().size
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func stale_release_guards() -> void:
	# A GUI control may have consumed an old release before the arena saw it.
	arena.set("_suppress_next_lmb_release", true)
	tutorial.set("_suppress_release_after_dismiss", true)
	arena.weapons.require_fresh_press = true

func run() -> void:
	create_timer(25).timeout.connect(func(): quit(1))
	var state := root.get_node("GameState")
	var saved: Dictionary = state.preferences()
	state.set_setting("fullscreen", false)
	state.set_setting("sound", false)
	arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await settle()
	arena.set_physics_process(false)
	arena.director.clear()
	var layer := CanvasLayer.new()
	arena.add_child(layer)
	tutorial = load("res://scenes/ui/tutorial.tscn").instantiate()
	layer.add_child(tutorial)
	tutorial.setup(arena.player.camera)
	await settle()
	var point: Vector2 = arena.player.camera.unproject_position(Vector3(0, 0, -3))
	stale_release_guards()
	arena.weapons.select_tool(1)
	click(true, point)
	expect(arena.weapons.ring.drawing, "First fresh cutter press starts after tutorial handoff")
	expect(not arena.get("_suppress_next_lmb_release") and not tutorial.get("_suppress_release_after_dismiss"), "Fresh press clears both stale release guards")
	var end_point: Vector2 = arena.player.camera.unproject_position(Vector3(3, 0, -3))
	var motion := InputEventMouseMotion.new()
	motion.position = end_point * Vector2(root.size) / root.get_visible_rect().size
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	click(false, end_point)
	expect(not arena.weapons.ring.drawing and not arena.weapons.mouse_held, "First cutter release ends drawing")
	expect(arena.weapons.ring.flight_phase != "idle", "First drawn stroke launches on release")

	stale_release_guards()
	arena.weapons.select_tool(2)
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	root.push_input(space, true)
	expect(arena._is_slow_held(), "Slow time responds on first press after tutorial")
	click(true, point)
	expect(arena.weapons.flash.charging, "First yellow hold starts while Space is held")
	arena.weapons.step(.5, arena.player, Vector3(0, 0, -3), [], .05)
	expect(arena.weapons.flash.charge > .4, "First yellow hold accumulates charge during slow time")
	click(false, point)
	expect(not arena.weapons.flash.charging and arena.weapons.flash.pulses.size() == 1, "First yellow release fires instead of requiring another click")
	space.pressed = false
	root.push_input(space, true)
	expect(not arena._is_slow_held(), "Space release remains available to gameplay")

	# Preserve protection when the next event really is the old dismiss release.
	arena.weapons.cancel_input()
	stale_release_guards()
	var before: int = arena.weapons.flash.pulses.size()
	click(false, point)
	expect(arena.weapons.flash.pulses.size() == before and not arena.weapons.flash.charging, "Old skip release never fires")
	arena.weapons.flash.cooldown = 0
	click(true, point)
	click(false, point)
	expect(arena.weapons.flash.pulses.size() == before + 1, "Fresh click works after old dismiss release was swallowed")
	for key in saved: state.set_setting(key, saved[key])
	root.get_node("AudioManager").stop_dialogue()
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
