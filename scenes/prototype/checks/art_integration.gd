extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func descendants(node: Node, type: String) -> int:
	return node.find_children("*", type, true, false).size()

func run() -> void:
	var arena: Node3D = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	root.get_node("GameState").resume()
	arena.set_physics_process(false)
	arena.director.clear()
	expect(descendants(arena.museum, "CollisionShape3D") == 0, "Museum art adds no conflicting physics")
	expect(descendants(arena, "StaticBody3D") == 3, "Floor and two existing cover colliders remain authoritative")
	expect(arena.museum.floor_root.get_child_count() == 64, "Teammate floor tiles are integrated")
	for kind: StringName in [&"blue", &"yellow", &"orange", &"front_guard", &"side_guard"]:
		var enemy: Node3D = arena.director.spawn(kind, Vector3(0, 0, -5))
		var visual: Node3D = enemy.part_visual
		expect(visual.model != null and descendants(visual, "Skeleton3D") == 1, String(kind) + " uses authored skinned model")
		expect(visual.animation.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL, "Enemy animation has no independent clock")
		var before: float = visual.phase
		enemy.step_enemy(0, arena.player)
		await process_frame
		expect(visual.phase == before, "Frozen world and engine frames cannot advance enemy art")
		enemy.step_enemy(.1, arena.player)
		expect(visual.phase > before, "World tick advances enemy art")
		if visual.cable:
			expect(visual.cable.visible, "Intact cable visible")
			enemy.cable_cut = true
			enemy._update_warden_visuals()
			expect(not visual.cable.visible, "Cut removes authored blue cable")
			enemy.cable_cut = false
			enemy._update_warden_visuals()
		if visual.core:
			expect(visual.core.visible == (kind == &"yellow"), "Closed guards hide yellow lens")
		if visual.plate and visual.core:
			var saved: Dictionary = enemy.capture_state()
			enemy.plate_broken = true
			enemy._update_warden_visuals()
			expect(not visual.plate.visible and visual.core.visible, "Heat reveals lens and removes whole cover")
			enemy.core_broken = true
			enemy._update_warden_visuals()
			expect(not visual.core.visible, "Broken lens disappears")
			enemy.restore_state(saved)
			expect(visual.plate.visible and not visual.core.visible, "Rewind restores closed authored parts")
			enemy.cable_cut = true
			enemy._update_warden_visuals()
			expect(not visual.plate.visible and not visual.cable.visible and visual.core.visible, "Cut route reveals same lens")
			if visual.shield_rim: expect(not visual.shield_rim.visible, "False Face rim disappears with shield")
		arena.director.clear()
	var player: Node3D = arena.player
	for tick in range(6): player.visual.step_visual(.05, 6, 6, Vector3.FORWARD)
	expect(player.visual.animation.current_animation == "Run", "Full speed uses new Run clip")
	player.visual.step_visual(.05, 3, 6, Vector3.BACK)
	expect(player.visual.animation.current_animation == "BackWalk", "Backing away uses new authored backward clip")
	expect(player.visual.grip_error("L") < .025 and player.visual.grip_error("R") < .025, "New gait keeps hands on equipment")
	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	await create_timer(.1).timeout
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
