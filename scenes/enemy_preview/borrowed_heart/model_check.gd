extends RefCounted

var checks := 0
var failures: Array[String] = []

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)

func run(subject: Node3D) -> Dictionary:
	for part in ["Body", "Companion", "ConduitCouplings", "CoreTarget", "CutConduit", "HeatCover"]:
		var mesh: MeshInstance3D = subject.find_child(part, true, false)
		expect(mesh != null, "Missing visual part " + part)
		if mesh:
			expect(mesh.skin != null, "Missing skin on " + part)
			expect(mesh.mesh.get_surface_count() > 0, "Empty part " + part)
	var sockets := {
		"CoreSocket": Vector3(0, 1.75, 0),
		"ConduitStart": Vector3(0.15, 0.85, 0),
		"ConduitEnd": Vector3(1.15, 0.85, 0),
		"CompanionSocket": Vector3(1.57, 0.55, 0.08),
		"CoverSocket": Vector3(0, 1.75, -0.25),
	}
	for name in sockets:
		var socket: Node3D = subject.find_child(name, true, false)
		expect(socket != null, "Missing socket " + name)
		if socket:
			expect(socket.global_position.distance_to(sockets[name]) < 0.005, "Socket coordinate " + name + " = " + str(socket.global_position))
	var skeleton: Skeleton3D = subject.find_child("Skeleton3D", true, false)
	expect(skeleton != null, "Imported skeleton")
	if skeleton:
		expect(skeleton.get_bone_count() == 22, "22 expected bones")
	var anim: AnimationPlayer = subject.find_child("AnimationPlayer", true, false)
	expect(anim != null, "Imported AnimationPlayer")
	if anim:
		for clip in ["Idle", "Walk", "Flinch"]:
			expect(anim.has_animation(clip), "Imported clip " + clip)
			if anim.has_animation(clip):
				expect(anim.get_animation(clip).length > 0.4, "Valid duration " + clip)
		for clip in ["Idle", "Walk"]:
			expect(anim.get_animation(clip).loop_mode == Animation.LOOP_LINEAR, "Loop flag " + clip)
		if skeleton:
			anim.active = true
			anim.play("Walk")
			anim.seek(0.0, true)
			var thigh := skeleton.find_bone("thigh.L")
			var crawler := skeleton.find_bone("crawl.LF")
			expect(thigh >= 0 and crawler >= 0, "Main and crawler limb bones")
			if thigh >= 0 and crawler >= 0:
				var first := skeleton.get_bone_pose_rotation(thigh)
				var little := skeleton.get_bone_pose_rotation(crawler)
				anim.seek(0.25, true)
				expect(first.angle_to(skeleton.get_bone_pose_rotation(thigh)) > 0.1, "Walk moves humanoid thigh")
				expect(little.angle_to(skeleton.get_bone_pose_rotation(crawler)) > 0.1, "Walk moves crawler limb")
			anim.stop()
			anim.active = false
			skeleton.reset_bone_poses()
			skeleton.force_update_all_bone_transforms()
	var body: MeshInstance3D = subject.find_child("Body", true, false)
	var body_bounds := body.global_transform * body.bake_mesh_from_current_skeleton_pose().get_aabb()
	expect(body_bounds.position.y >= 0.0 and body_bounds.position.y < 0.06, "Grounded feet in rest pose")
	expect(body_bounds.end.y > 2.5 and body_bounds.end.y < 2.7, "Expected humanoid height")
	expect(first_surface(subject, ["Body", "CoreTarget", "HeatCover"]) == "HeatCover", "Closed chest hides yellow core")
	expect(first_surface(subject, ["Body", "CoreTarget"]) == "CoreTarget", "Exposed yellow core is visible in front of torso")
	return {"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}

# Ray through the authored target uses the actual skinned triangles, without
# adding physics or changing the runtime part hit tests.
func first_surface(subject: Node3D, names: Array) -> String:
	var start := Vector3(0, 1.75, -2)
	var end := Vector3(0, 1.75, 1)
	var distance := INF
	var nearest := ""
	for name in names:
		var instance: MeshInstance3D = subject.find_child(name, true, false)
		var mesh := instance.bake_mesh_from_current_skeleton_pose()
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0, indices.size(), 3):
				var hit = Geometry3D.segment_intersects_triangle(start, end,
					instance.global_transform * vertices[indices[i]],
					instance.global_transform * vertices[indices[i + 1]],
					instance.global_transform * vertices[indices[i + 2]])
				if hit != null and start.distance_to(hit) < distance:
					distance = start.distance_to(hit)
					nearest = name
	return nearest
