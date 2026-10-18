extends SceneTree

# Offline equipment asset review and verification script.
# Uses the real arena and its unchanged gameplay camera (ortho 22, pos (0,20,14), pitch -55 deg)
# to verify GLB import, normals, backface culling, Grip_R/Grip_L/Emitter socket contract,
# and held readability at actual gameplay scale plus close-up Godot material views.
const OUT := "/home/mattlongname/frankenstein/.daedalus-dev-state/game-jams/state/old-tech-jam-3/exports/equipment-art/"
const PROPS := [
	{"id": "ring_caster", "label": "1. Ring Caster", "tool_idx": 1, "offset": Vector3(-3.3, 0.0, 0.0)},
	{"id": "flash_camera", "label": "2. Flash Camera", "tool_idx": 2, "offset": Vector3(-1.1, 0.0, 0.0)},
	{"id": "heat_bellows", "label": "3. Heat Bellows", "tool_idx": 3, "offset": Vector3(1.1, 0.0, 0.0)},
	{"id": "time_device", "label": "4. Time Device", "tool_idx": 4, "offset": Vector3(3.3, 0.0, 0.0)},
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


func inspect_prop(prop_id: String, root_node: Node3D) -> Dictionary:
	var mesh_count := 0
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

	expect(mesh_count >= 10, prop_id + ": expected multiple named mesh parts")
	expect(tri_count >= 1200 and tri_count <= 12000, prop_id + ": triangle count out of expected range: " + str(tri_count))
	expect(normals_ok, prop_id + ": invalid or missing vertex normals")
	expect(culling_ok, prop_id + ": all materials must use backface culling")

	var grip_r := root_node.find_child("Grip_R", true, false) as Node3D
	var grip_l := root_node.find_child("Grip_L", true, false) as Node3D
	var emitter := root_node.find_child("Emitter", true, false) as Node3D
	expect(grip_r != null, prop_id + ": missing Grip_R empty")
	expect(grip_l != null, prop_id + ": missing Grip_L empty")
	expect(emitter != null, prop_id + ": missing Emitter empty")

	var sockets := {}
	if grip_r != null:
		expect(grip_r.position.length() < 0.001, prop_id + ": Grip_R must sit at object origin (0,0,0)")
		expect(grip_r.transform.basis.is_equal_approx(Basis.IDENTITY), prop_id + ": Grip_R local rotation must be identity")
		sockets["Grip_R"] = {
			"position": [snappedf(grip_r.position.x, 0.0001), snappedf(grip_r.position.y, 0.0001), snappedf(grip_r.position.z, 0.0001)],
			"rotation_deg": [snappedf(grip_r.rotation_degrees.x, 0.01), snappedf(grip_r.rotation_degrees.y, 0.01), snappedf(grip_r.rotation_degrees.z, 0.01)],
		}
	if grip_l != null:
		expect(grip_l.transform.basis.is_equal_approx(Basis.IDENTITY), prop_id + ": Grip_L local rotation must be identity")
		sockets["Grip_L"] = {
			"position": [snappedf(grip_l.position.x, 0.0001), snappedf(grip_l.position.y, 0.0001), snappedf(grip_l.position.z, 0.0001)],
			"rotation_deg": [snappedf(grip_l.rotation_degrees.x, 0.01), snappedf(grip_l.rotation_degrees.y, 0.01), snappedf(grip_l.rotation_degrees.z, 0.01)],
		}
	if emitter != null:
		expect(emitter.position.z < -0.05, prop_id + ": Emitter must point forward along -Z in Godot")
		sockets["Emitter"] = {
			"position": [snappedf(emitter.position.x, 0.0001), snappedf(emitter.position.y, 0.0001), snappedf(emitter.position.z, 0.0001)],
			"rotation_deg": [snappedf(emitter.rotation_degrees.x, 0.01), snappedf(emitter.rotation_degrees.y, 0.01), snappedf(emitter.rotation_degrees.z, 0.01)],
		}

	return {
		"asset": "res://assets/equipment/" + prop_id + ".glb",
		"mesh_objects": mesh_count,
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
	var err := root.get_texture().get_image().save_png(OUT + filename)
	expect(err == OK, "Could not save " + filename)


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
		prop_reports[prop_id] = inspect_prop(prop_id, standalone)
		standalone.position = item["offset"] + Vector3(0.0, 1.05, 1.35)
		standalone.rotation.y = deg_to_rad(148.0)
		standalone_props.append(standalone)

		# Also place a player figure holding the new GLB prop at Grip_R to show held silhouette at ortho 22
		var holder := Node3D.new()
		holder.position = item["offset"] + Vector3(0.0, 0.5, -1.25)
		holder.rotation.y = deg_to_rad(152.0)
		display_root.add_child(holder)

		var pvis: Node3D = PlayerVisualScript.new()
		holder.add_child(pvis)
		pvis.build()
		pvis.set_tool_index(int(item["tool_idx"]))
		if pvis.held_tool != null:
			for child in pvis.held_tool.get_children():
				child.visible = false
			var held_instance := packed.instantiate() as Node3D
			pvis.held_tool.add_child(held_instance)
			# Align right hand grip to holder's right hand position
			held_instance.position = Vector3(0.06, -0.02, 0.08)
		held_figures.append(holder)

	var layer := CanvasLayer.new()
	layer.layer = 100
	var label := Label.new()
	label.text = (
		"JAM-3 EQUIPMENT MODELS  •  Actual gameplay camera: orthographic 22 m, pos (0, 20, 14), pitch −55° (1280×800)\n"
		+ "Top row: Held on player figures  |  Bottom row: Standalone props  (1: Ring Caster, 2: Flash Camera, 3: Heat Bellows, 4: Time Device)"
	)
	label.position = Vector2(24, root.get_visible_rect().size.y - 68)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_font_size_override("font_size", 15)
	layer.add_child(label)
	arena.add_child(layer)

	await save_image("gameplay-scale.png")

	# Hide held figures for close-up two-angle Godot inspection of the 4 props
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
		"JAM-3 EQUIPMENT / GODOT DETAIL (ANGLE 1: FRONT THREE-QUARTER)\n"
		+ "Left to Right: ring_caster.glb  •  flash_camera.glb  •  heat_bellows.glb  •  time_device.glb"
	)
	await save_image("godot-detail-front.png")

	for i in range(standalone_props.size()):
		standalone_props[i].rotation = Vector3(0.0, deg_to_rad(-35.0), 0.0)
	label.text = (
		"JAM-3 EQUIPMENT / GODOT DETAIL (ANGLE 2: REAR / GRIP THREE-QUARTER)\n"
		+ "Showing Grip_R / Grip_L handles, cassette mechanisms, bellows linkage, and metronome/hourglass"
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
	var file := FileAccess.open(OUT + "godot-verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
