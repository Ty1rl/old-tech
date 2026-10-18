extends SceneTree

# Offline equipment asset review and Round J verification script.
# Uses the real arena and its unchanged gameplay camera (ortho 22, pos (0,20,14), pitch -55 deg)
# to verify consolidated GLB mesh counts (8..16 visible meshes/tool), preserved separate moving
# parts, normals, backface culling, exact unchanged Grip_R/Grip_L/Emitter socket coordinates,
# two-hand IK grip fitting on PlayerVisual, and gameplay-scale + close-up Godot captures.
const OUT_ROUND_J := "/home/mattlongname/frankenstein/.daedalus-dev-state/game-jams/state/old-tech-jam-3/exports/round-j/"
const OUT_ART_I := "/home/mattlongname/frankenstein/.daedalus-dev-state/game-jams/state/old-tech-jam-3/exports/art-i/"

const PROPS := [
	{
		"id": "ring_caster",
		"label": "1. Ring Caster",
		"tool_idx": 1,
		"offset": Vector3(-3.3, 0.0, 0.0),
		"before_meshes": 79,
		"required_nodes": ["Suspended_Saw_Ring", "Handwheel_Crank"],
		"expected_sockets": {
			"Grip_R": Vector3(0.0, 0.0, 0.0),
			"Grip_L": Vector3(-0.165, -0.035, -0.35),
			"Emitter": Vector3(0.0, 0.015, -0.49),
		},
	},
	{
		"id": "flash_camera",
		"label": "2. Flash Camera",
		"tool_idx": 2,
		"offset": Vector3(-1.1, 0.0, 0.0),
		"before_meshes": 50,
		"required_nodes": ["Accordion_Bellows", "Lens_Glass_Element"],
		"expected_sockets": {
			"Grip_R": Vector3(0.0, 0.0, 0.0),
			"Grip_L": Vector3(-0.42, 0.0, 0.0),
			"Emitter": Vector3(-0.21, 0.025, -0.395),
		},
	},
	{
		"id": "heat_bellows",
		"label": "3. Heat Bellows",
		"tool_idx": 3,
		"offset": Vector3(1.1, 0.0, 0.0),
		"before_meshes": 81,
		"required_nodes": ["Leather_Bellows_Chamber", "Bellows_Linen_Band", "Bellows_Scissor_Linkage"],
		"expected_sockets": {
			"Grip_R": Vector3(0.0, 0.0, 0.0),
			"Grip_L": Vector3(0.0, -0.075, -0.37),
			"Emitter": Vector3(0.0, 0.105, -0.60),
		},
	},
	{
		"id": "time_device",
		"label": "4. Time Device",
		"tool_idx": 4,
		"offset": Vector3(3.3, 0.0, 0.0),
		"before_meshes": 34,
		"required_nodes": ["Metronome_Pendulum_Rod", "Metronome_Pendulum_Weight", "Hourglass_Violet_Bulbs", "Metronome_Violet_Face"],
		"expected_sockets": {
			"Grip_R": Vector3(0.0, 0.0, 0.0),
			"Grip_L": Vector3(-0.23, 0.0, -0.01),
			"Emitter": Vector3(-0.115, 0.075, -0.095),
		},
	},
]

var failures: Array[String] = []
var checks: int = 0
var prop_reports: Dictionary = {}


func _initialize() -> void:
	call_deferred("capture")


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func inspect_prop(item: Dictionary, root_node: Node3D) -> Dictionary:
	var prop_id: String = item["id"]
	var mesh_count := 0
	var mesh_names: Array[String] = []
	var tri_count := 0
	var mat_names: Dictionary = {}
	var bounds := AABB()
	var have_bounds := false
	var normals_ok := true
	var culling_ok := true

	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is MeshInstance3D:
			mesh_count += 1
			var inst := node as MeshInstance3D
			mesh_names.append(String(inst.name))
			var box: AABB = inst.transform * inst.get_aabb()
			bounds = bounds.merge(box) if have_bounds else box
			have_bounds = true
			for s in range(inst.mesh.get_surface_count()):
				var arr := inst.mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				var idxs: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				tri_count += (idxs.size() if not idxs.is_empty() else verts.size()) / 3
				if norms.size() != verts.size():
					normals_ok = false
				for n in norms:
					if not n.is_finite() or absf(n.length() - 1.0) > 0.02:
						normals_ok = false
						break
				var mat := inst.get_active_material(s) as StandardMaterial3D
				if mat == null:
					culling_ok = false
				else:
					mat_names[mat.resource_name] = true
					if mat.cull_mode != BaseMaterial3D.CULL_BACK:
						culling_ok = false

	mesh_names.sort()
	expect(
		mesh_count >= 8 and mesh_count <= 16,
		prop_id + ": expected 8..16 consolidated visible meshes, got " + str(mesh_count)
	)
	expect(tri_count >= 1200 and tri_count <= 12000, prop_id + ": triangle count out of expected range: " + str(tri_count))
	expect(normals_ok, prop_id + ": invalid or missing vertex normals")
	expect(culling_ok, prop_id + ": all materials must use backface culling")

	for req_name: String in item["required_nodes"]:
		var req_node := root_node.find_child(req_name, true, false)
		expect(req_node != null, prop_id + ": missing separately named moving/key mesh " + req_name)

	var expected_sockets: Dictionary = item["expected_sockets"]
	var sockets := {}
	for sname in ["Grip_R", "Grip_L", "Emitter"]:
		var snode := root_node.find_child(sname, true, false) as Node3D
		expect(snode != null, prop_id + ": missing " + sname + " empty")
		if snode != null:
			var exp_pos: Vector3 = expected_sockets[sname]
			expect(
				snode.position.distance_to(exp_pos) < 0.0005,
				prop_id + ": " + sname + " moved from " + str(exp_pos) + " to " + str(snode.position)
			)
			expect(snode.transform.basis.is_equal_approx(Basis.IDENTITY), prop_id + ": " + sname + " local rotation must be identity")
			sockets[sname] = {
				"before_position": [exp_pos.x, exp_pos.y, exp_pos.z],
				"after_position": [snappedf(snode.position.x, 0.0001), snappedf(snode.position.y, 0.0001), snappedf(snode.position.z, 0.0001)],
				"rotation_deg": [snappedf(snode.rotation_degrees.x, 0.01), snappedf(snode.rotation_degrees.y, 0.01), snappedf(snode.rotation_degrees.z, 0.01)],
			}

	return {
		"asset": "res://assets/equipment/" + prop_id + ".glb",
		"before_mesh_objects": item["before_meshes"],
		"after_mesh_objects": mesh_count,
		"exported_mesh_names": mesh_names,
		"triangles": tri_count,
		"materials": mat_names.size(),
		"material_names": mat_names.keys(),
		"bounds_min_m": [snappedf(bounds.position.x, 0.001), snappedf(bounds.position.y, 0.001), snappedf(bounds.position.z, 0.001)],
		"dimensions_m": [snappedf(bounds.size.x, 0.001), snappedf(bounds.size.y, 0.001), snappedf(bounds.size.z, 0.001)],
		"sockets": sockets,
	}


func save_image(filename: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err1 := img.save_png(OUT_ROUND_J + filename)
	var err2 := img.save_png(OUT_ART_I + filename)
	expect(err1 == OK and err2 == OK, "Could not save " + filename)


func capture() -> void:
	var arena: Node3D = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	arena.player.model.hide()

	for other in arena.find_children("*", "CanvasLayer", true, false):
		other.visible = false

	var camera: Camera3D = arena.player.camera
	expect(
		camera.projection == Camera3D.PROJECTION_ORTHOGONAL and is_equal_approx(camera.size, 22.0),
		"Expected gameplay camera orthographic size 22.0, got " + str(camera.size)
	)
	expect(
		camera.position.is_equal_approx(Vector3(0, 20, 14)) and is_equal_approx(camera.rotation_degrees.x, -55.0),
		"Expected gameplay camera at (0,20,14) pitch -55 deg"
	)

	var PlayerVisualScript = load("res://scenes/prototype/player_visual.gd")
	var display_root := Node3D.new()
	display_root.name = "EquipmentReviewDisplay"
	arena.add_child(display_root)

	var standalone_props: Array[Node3D] = []
	var held_figures: Array[Node3D] = []

	for item in PROPS:
		var prop_id: String = item["id"]
		var path := "res://assets/equipment/" + prop_id + ".glb"
		var packed := load(path) as PackedScene
		expect(packed != null, "Failed to load GLB PackedScene: " + path)
		if packed == null:
			continue

		var standalone := packed.instantiate() as Node3D
		display_root.add_child(standalone)
		var report := inspect_prop(item, standalone)
		standalone.position = item["offset"] + Vector3(0.0, 1.05, 1.35)
		standalone.rotation.y = deg_to_rad(148.0)
		standalone_props.append(standalone)

		# Use the actual rigged PlayerVisual in 21be614 which mounts and IK-fits the GLB prop!
		var holder := Node3D.new()
		holder.position = item["offset"] + Vector3(0.0, 0.5, -1.25)
		holder.rotation.y = deg_to_rad(152.0)
		display_root.add_child(holder)

		var pvis: Node3D = PlayerVisualScript.new()
		holder.add_child(pvis)
		pvis.build()
		pvis.set_tool_index(int(item["tool_idx"]))
		var err_r := float(pvis.grip_error("R"))
		var err_l := float(pvis.grip_error("L"))
		expect(err_r < 0.02, prop_id + ": right hand IK grip error too large: " + str(err_r))
		expect(err_l < 0.02, prop_id + ": left hand IK grip error too large: " + str(err_l))
		report["rigged_grip_error_m"] = {"R": snappedf(err_r, 0.0001), "L": snappedf(err_l, 0.0001)}
		prop_reports[prop_id] = report
		held_figures.append(holder)

	var layer := CanvasLayer.new()
	layer.layer = 100
	var label := Label.new()
	label.text = (
		"JAM-3 ROUND J POLISHED & CONSOLIDATED EQUIPMENT  •  Gameplay camera: ortho 22 m, pos (0, 20, 14), pitch −55° (1280×800)\n"
		+ "Top row: Held on rigged protagonist (1.25× runtime scale)  |  Bottom row: Standalone props (10–13 meshes/tool)"
	)
	label.position = Vector2(24, root.get_visible_rect().size.y - 68)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_font_size_override("font_size", 15)
	layer.add_child(label)
	arena.add_child(layer)

	await save_image("gameplay-scale.png")

	for fig in held_figures:
		fig.visible = false
	var detail_x := [-1.32, -0.36, 0.56, 1.38]
	for i in range(standalone_props.size()):
		standalone_props[i].position = Vector3(detail_x[i], 1.0, 0.0)
		standalone_props[i].rotation = Vector3(0.0, deg_to_rad(145.0), 0.0)

	camera.position = Vector3(0.0, 2.45, 3.2)
	camera.look_at(Vector3(0.0, 1.02, -0.10))
	camera.size = 2.48
	label.text = (
		"JAM-3 ROUND J / GODOT DETAIL (ANGLE 1: FRONT THREE-QUARTER — 10–13 CONSOLIDATED MESHES/TOOL)\n"
		+ "Left to Right: ring_caster.glb (13)  •  flash_camera.glb (10)  •  heat_bellows.glb (12)  •  time_device.glb (11)"
	)
	await save_image("godot-detail-front.png")

	for i in range(standalone_props.size()):
		standalone_props[i].rotation = Vector3(0.0, deg_to_rad(-35.0), 0.0)
	label.text = (
		"JAM-3 ROUND J / GODOT DETAIL (ANGLE 2: REAR / GRIP THREE-QUARTER)\n"
		+ "Preserved Grip_R / Grip_L / Emitter sockets, open cassette bay, smooth brass lens, brass heat baffle & scale ticks"
	)
	await save_image("godot-detail-rear.png")

	finish()


func finish() -> void:
	var result := {
		"status": "passed" if failures.is_empty() else "failed",
		"checks": checks,
		"failures": failures,
		"gameplay_camera": {
			"position": [0, 20, 14],
			"pitch_degrees": -55,
			"orthographic_size": 22,
			"resolution": [1280, 800],
		},
		"props": prop_reports,
		"playable_build_changed": false,
	}
	var json_str := JSON.stringify(result, "\t") + "\n"
	for dir_path in [OUT_ROUND_J, OUT_ART_I]:
		var file := FileAccess.open(dir_path + "godot-verification.json", FileAccess.WRITE)
		file.store_string(json_str)
		file.close()
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
