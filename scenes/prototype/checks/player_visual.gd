extends SceneTree

const ScrubView = preload("res://scenes/prototype/scrub_view.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func bone_pose(visual: Node3D, bone: String) -> Transform3D:
	return visual.skeleton.get_bone_global_pose(visual.skeleton.find_bone(bone))

func run() -> void:
	var original: Node3D = load("res://scenes/player.tscn").instantiate()
	expect(original.get_node("MeshInstance3D").mesh is CylinderMesh
		and original.get_node("MeshInstance3D/MeshInstance3D2").visible, "Original partner player scene is unchanged")
	original.free()
	var arena: Node3D = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	root.get_node("GameState").resume()
	arena.set_physics_process(false)
	var player: Node3D = arena.player
	var visual: Node3D = player.visual
	var collider: CollisionShape3D = player.get_node("CollisionShape3D")
	expect(collider.shape is CylinderShape3D and is_equal_approx(collider.shape.height, 1), "Imported art preserves gameplay collider")
	expect(player.model.mesh == null and not player.model.get_node("MeshInstance3D2").visible, "Prototype hides old primitive body and facing arrow")
	expect(visual.get_parent() == player.model and visual.skeleton.get_bone_count() == 20, "Skinned protagonist follows existing facing root")
	expect(not visual.is_processing() and not visual.is_physics_processing()
		and visual.animation.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,
		"Cosmetic animation has no independent engine clock")
	expect(absf(visual.global_position.y-player.global_position.y) < .01 and visual.scale.is_equal_approx(Vector3.ONE * 1.3), "Feet align with collider bottom and model retains readability scale")
	for clip in ["Idle", "Walk", "RingHold", "FlashHold", "ConeHold", "ClockHold"]:
		expect(visual.animation.has_animation(clip), "Imported clip exists: " + clip)
	for index in range(1,5):
		player.set_visual_tool(index)
		expect(visual.tool_index == index and visual.tool_id == visual.TOOL_IDS[index-1], "Tool selection is reflected in imported art")
		for id: StringName in visual.tool_attachments:
			expect(visual.tool_attachments[id].visible == (id == visual.tool_id), "Only equipped prop is visible")
		for tick in range(12):
			visual.step_visual(.05, 6 if tick > 3 else 0)
			expect(visual.grip_error("L") < .025 and visual.grip_error("R") < .025,
				"Both hands stay on real handles through idle/walk: tool %d tick %d errors %f/%f" % [index,tick,visual.grip_error("L"),visual.grip_error("R")])
		var emitter: Node3D = visual.tool_attachments[visual.tool_id].find_child("Emitter", true, false)
		expect(emitter.global_position.z < player.global_position.z, "Equipped emitter points in player facing direction")
	player.set_visual_tool(0)
	expect(visual.tool_index == 1, "Low selection clamps to ring")
	player.set_visual_tool(9)
	expect(visual.tool_index == 4, "High selection clamps to clock")
	player.reset_state()
	expect(visual.tool_index == 1 and is_equal_approx(visual.walk_phase,0), "Reset restores ring and initial pose")
	var before := bone_pose(visual,"shin.L")
	var phase: float = visual.walk_phase
	await process_frame
	await physics_frame
	expect(bone_pose(visual,"shin.L").is_equal_approx(before) and visual.walk_phase == phase, "Engine frames alone never animate frozen player")
	visual.step_visual(0,6)
	visual.step_visual(-.1,6)
	expect(bone_pose(visual,"shin.L").is_equal_approx(before), "Zero/negative real time never animates")
	for tick in range(5): visual.step_visual(.05,6)
	expect(not bone_pose(visual,"shin.L").is_equal_approx(before) and visual.walk_phase > phase, "Real-time step drives skinned leg movement")
	expect(visual.grip_error("L") < .025 and player.model.position.is_equal_approx(Vector3(0,.5,0)), "Animated limbs never move gameplay root")
	var knee: Transform3D = bone_pose(visual,"shin.R")
	player.step(.01, player.global_position + Vector3(10,0,0), false)
	player.step(.05, player.global_position + Vector3(10,0,0), true)
	expect(visual.held_tool.global_position.x > player.global_position.x, "Facing +X carries real equipment forward")
	expect(player.world_scale < 1 and visual.animation.current_animation in ["Idle","Walk"], "World slow leaves real-time art animation enabled")

	var snap: Dictionary = player.capture_state()
	expect(snap.size() == 4 and snap.has("position") and snap.has("velocity") and snap.has("health") and snap.has("facing"), "History schema still excludes rig/mesh/animation state")
	var scrub := ScrubView.new()
	var from: Dictionary = scrub.capture_pose(player,arena.director,arena.weapons)
	player.position += Vector3(4,0,-2)
	player.model.basis = Basis(Vector3.UP,PI)
	var target: Dictionary = scrub.capture_pose(player,arena.director,arena.weapons)
	phase = visual.walk_phase
	knee = bone_pose(visual,"shin.R")
	scrub.begin(from,player,arena.director,arena.weapons)
	scrub.step(ScrubView.DURATION*.5)
	expect(is_equal_approx(visual.walk_phase,phase) and bone_pose(visual,"shin.R").is_equal_approx(knee), "Scrub interpolation freezes animation and fitted hands")
	scrub.finish()
	expect(scrub.capture_pose(player,arena.director,arena.weapons) == target, "Scrub finish preserves exact facing/root transforms")
	player.restore_state(snap)
	expect(player.position.is_equal_approx(snap.position) and player.model.basis.is_equal_approx(snap.facing), "Snapshot restores original facing and position")
	expect(visual.grip_error("L") < .025 and visual.grip_error("R") < .025, "Sockets remain aligned after root restoration")
	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	await create_timer(.1).timeout
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
