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
	await process_frame
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
