extends SceneTree

const FootPlant = preload("res://scenes/prototype/foot_plant.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func run() -> void:
	# Bent rest leg, like the imported rigs. Translating the body while this
	# foot is grounded must leave the contact still, without moving the root.
	var skeleton := Skeleton3D.new()
	root.add_child(skeleton)
	for name in ["root", "thigh.L", "shin.L", "foot.L"]: skeleton.add_bone(name)
	skeleton.set_bone_rest(0, Transform3D.IDENTITY)
	for bone in range(1,4): skeleton.set_bone_parent(bone,bone-1)
	skeleton.set_bone_rest(1, Transform3D(Basis.IDENTITY,Vector3(0,1,0)))
	skeleton.set_bone_rest(2, Transform3D(Basis.IDENTITY,Vector3(0,-.45,.2)))
	skeleton.set_bone_rest(3, Transform3D(Basis.IDENTITY,Vector3(0,-.45,-.2)))
	skeleton.reset_bone_poses()
	var plant := FootPlant.new()
	plant.apply(skeleton)
	var contact := skeleton.global_transform * skeleton.get_bone_global_pose(3).origin
	var max_slip := 0.0
	for tick in range(5):
		skeleton.position.x += .02
		skeleton.reset_bone_poses()
		plant.apply(skeleton)
		var foot := skeleton.global_transform * skeleton.get_bone_global_pose(3).origin
		max_slip = maxf(max_slip,Vector2(foot.x-contact.x,foot.z-contact.z).length())
	expect(max_slip < .001, "Grounded foot holds world position as body translates; slip %.5f" % max_slip)
	expect(is_equal_approx(skeleton.position.x,.1), "Planting does not change gameplay root")
	skeleton.reset_bone_poses()
	skeleton.set_bone_pose_position(3,skeleton.get_bone_rest(3).origin+Vector3(0,.1,0))
	plant.apply(skeleton)
	expect(plant.contacts.is_empty(), "Lifted foot releases its contact")
	skeleton.reset_bone_poses()
	plant.apply(skeleton)
	skeleton.position += Vector3(10,0,0)
	plant.apply(skeleton)
	expect(plant.contacts.is_empty(), "Teleport drops old contact")
	skeleton.reset_bone_poses()
	plant.apply(skeleton)
	plant.reset()
	expect(plant.contacts.is_empty(), "Reset clears planted contacts")
	skeleton.position = Vector3.ZERO
	skeleton.reset_bone_poses()
	plant.apply(skeleton, 0.28, 0.24)
	var soft_origin := (skeleton.global_transform * skeleton.get_bone_global_pose(3).origin).x
	skeleton.position.x = 0.06
	skeleton.reset_bone_poses()
	plant.apply(skeleton, 0.28, 0.24)
	var soft_x := (skeleton.global_transform * skeleton.get_bone_global_pose(3).origin).x - soft_origin
	expect(soft_x > 0.01 and soft_x < 0.055, "Soft foot plant cushions stance without rigid pinning; delta %.4f" % soft_x)
	skeleton.position.x = 0.40
	skeleton.reset_bone_poses()
	plant.apply(skeleton, 0.28, 0.24)
	expect(not plant.contacts.is_empty(), "Soft foot plant glides anchor instead of dropping contact mid-stride")
	skeleton.queue_free()

	# Real imported GLTF rig (protagonist.glb has non-identity thigh.L/R rest_euler ~ +-3.03 rad).
	# Applying FootPlant must keep feet below knees and knees below hips, never flipping legs upward.
	var character: Node3D = load("res://assets/characters/protagonist/protagonist.glb").instantiate()
	root.add_child(character)
	var real_skel: Skeleton3D = character.find_children("*", "Skeleton3D", true, false)[0]
	var real_anim: AnimationPlayer = character.find_children("*", "AnimationPlayer", true, false)[0]
	var real_plant := FootPlant.new()
	var pelvis_idx := real_skel.find_bone("pelvis")
	var shin_l := real_skel.find_bone("shin.L")
	var shin_r := real_skel.find_bone("shin.R")
	var foot_l := real_skel.find_bone("foot.L")
	var foot_r := real_skel.find_bone("foot.R")
	var max_real_foot_y := 0.0
	var hierarchy_ok := true
	real_anim.play("Walk")
	for step_i in range(20):
		character.position.z -= 0.12
		real_skel.reset_bone_poses()
		real_anim.seek(float(step_i) * 0.05, true)
		real_anim.advance(0)
		real_plant.apply(real_skel, 0.35, 0.24)
		real_skel.force_update_all_bone_transforms()
		var fl := real_skel.get_bone_global_pose(foot_l).origin
		var fr := real_skel.get_bone_global_pose(foot_r).origin
		var kl := real_skel.get_bone_global_pose(shin_l).origin
		var kr := real_skel.get_bone_global_pose(shin_r).origin
		var hp := real_skel.get_bone_global_pose(pelvis_idx).origin
		max_real_foot_y = maxf(max_real_foot_y, maxf(fl.y, fr.y))
		if not (fl.y < kl.y and kl.y < hp.y and fr.y < kr.y and kr.y < hp.y):
			hierarchy_ok = false
	expect(hierarchy_ok and max_real_foot_y < 0.36,
		"Real GLTF skeleton with non-identity bone rests keeps feet grounded below knees/hips (max_foot_y %.3f)" % max_real_foot_y)
	character.queue_free()

	await process_frame
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
