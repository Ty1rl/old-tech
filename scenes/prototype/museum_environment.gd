extends Node3D

# jam-4 owns museum_environment.gd/.tscn.
# Visual-only museum wrapper built from the teammate's assets in res://assets/modelWallsFloors/.
# Existing arena floor and cover physics remain authoritative; no StaticBody3D or CollisionShape3D nodes are added.
const Cover = preload("res://scenes/prototype/cover.gd")

const FLOOR_SCENE := preload("res://assets/modelWallsFloors/floor.glb")
const LEFT_WALL_DOUBLE_SCENE := preload("res://assets/modelWallsFloors/leftWallDouble.glb")
const LEFT_WALL_SINGLE_SCENE := preload("res://assets/modelWallsFloors/leftWallSingle.glb")
const RIGHT_WALL_DOUBLE_SCENE := preload("res://assets/modelWallsFloors/rightWallDouble.glb")
const RIGHT_WALL_SINGLE_SCENE := preload("res://assets/modelWallsFloors/rightWallSingle.glb")
const UNI_COLUMN_SCENE := preload("res://assets/modelWallsFloors/uniColumn.glb")

const ARENA_HALF_SIZE := 20.0
const FLOOR_TILES_PER_AXIS := 8
const FLOOR_TOP_Y := 0.003
const FLOOR_SCALE_Y := 0.04

const WALL_PANELS_PER_SIDE := 10
const WALL_SCALE_X := 0.20
const WALL_SCALE_Y := 0.18
const WALL_OVERLAP := 1.04
const SOUTH_CURB_SCALE_Y := 0.034
const PERIMETER_OFFSET := 20.26

var floor_root: Node3D
var walls_root: Node3D
var columns_root: Node3D
var cover_root: Node3D

var _built := false
var _shared_meshes: Dictionary = {}
var _shared_aabbs: Dictionary = {}
var _floor_shader_material: ShaderMaterial
var _wall_materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	if not _built:
		build()


func build(include_cover_decorations: bool = true) -> Node3D:
	_clear_built_children()
	_ensure_shared_meshes()

	floor_root = Node3D.new()
	floor_root.name = "FloorTiles"
	add_child(floor_root)

	walls_root = Node3D.new()
	walls_root.name = "PerimeterWalls"
	add_child(walls_root)

	columns_root = Node3D.new()
	columns_root.name = "PerimeterColumns"
	add_child(columns_root)

	cover_root = Node3D.new()
	cover_root.name = "CoverDecorations"
	add_child(cover_root)

	_build_floor_grid()
	_build_perimeter_walls_and_columns()
	if include_cover_decorations:
		_build_cover_decorations()

	_built = true
	return self


func apply_to_arena(arena: Node3D, hide_placeholder_meshes: bool = true) -> void:
	if not _built:
		build()
	if get_parent() != arena and is_instance_valid(arena):
		arena.add_child(self)
	if hide_placeholder_meshes and is_instance_valid(arena):
		for child in arena.get_children():
			if child is StaticBody3D:
				for sub in child.get_children():
					if sub is MeshInstance3D:
						sub.visible = false


func get_cover_world_rectangles() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if cover_root == null:
		return rects
	for child in cover_root.get_children():
		if child is MeshInstance3D and child.mesh != null:
			var aabb: AABB = child.transform * child.mesh.get_aabb()
			rects.append(Rect2(aabb.position.x, aabb.position.z, aabb.size.x, aabb.size.z))
	return rects


func _clear_built_children() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	floor_root = null
	walls_root = null
	columns_root = null
	cover_root = null
	_built = false


func _ensure_shared_meshes() -> void:
	if not _shared_meshes.is_empty():
		return
	var catalog := {
		"floor": {
			"scene": FLOOR_SCENE,
			"invert": true,
			"tint": Color(0.54, 0.52, 0.49),
			"roughness": 0.94,
		},
		"leftWallDouble": {
			"scene": LEFT_WALL_DOUBLE_SCENE,
			"invert": true,
			"tint": Color(1.18, 1.12, 1.05),
			"roughness": 0.78,
		},
		"leftWallSingle": {
			"scene": LEFT_WALL_SINGLE_SCENE,
			"invert": false,
			"tint": Color(1.18, 1.12, 1.05),
			"roughness": 0.78,
		},
		"rightWallDouble": {
			"scene": RIGHT_WALL_DOUBLE_SCENE,
			"invert": true,
			"tint": Color(1.18, 1.12, 1.05),
			"roughness": 0.78,
		},
		"rightWallSingle": {
			"scene": RIGHT_WALL_SINGLE_SCENE,
			"invert": true,
			"tint": Color(1.18, 1.12, 1.05),
			"roughness": 0.78,
		},
		"uniColumn": {
			"scene": UNI_COLUMN_SCENE,
			"invert": false,
			"tint": Color(1.22, 1.14, 1.06),
			"roughness": 0.74,
		},
	}
	for key in catalog.keys():
		var entry: Dictionary = catalog[key]
		var packed: PackedScene = entry["scene"]
		var inst := packed.instantiate()
		var mesh_inst: MeshInstance3D = null
		for child in inst.get_children():
			if child is MeshInstance3D:
				mesh_inst = child
				break
		if mesh_inst != null and mesh_inst.mesh != null:
			var fixed_mesh := _prepare_mesh(
				mesh_inst.mesh,
				bool(entry["invert"]),
				entry["tint"] as Color,
				float(entry["roughness"]),
				key == "floor"
			)
			_shared_meshes[key] = fixed_mesh
			_shared_aabbs[key] = fixed_mesh.get_aabb()
		inst.free()


func _prepare_mesh(src_mesh: Mesh, flip_inside_out: bool, tint: Color, roughness_val: float, flatten_up_normals: bool = false) -> ArrayMesh:
	var out_mesh := ArrayMesh.new()
	for s in range(src_mesh.get_surface_count()):
		var arrays := src_mesh.surface_get_arrays(s)
		if flip_inside_out:
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in range(norms.size()):
				norms[i] = -norms[i]
			arrays[Mesh.ARRAY_NORMAL] = norms
			var idxs: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var tri_count := idxs.size() / 3
			for t in range(tri_count):
				var base := t * 3
				var tmp := idxs[base + 1]
				idxs[base + 1] = idxs[base + 2]
				idxs[base + 2] = tmp
			arrays[Mesh.ARRAY_INDEX] = idxs
		if flatten_up_normals:
			var norms_flat: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in range(norms_flat.size()):
				norms_flat[i] = Vector3.UP
			arrays[Mesh.ARRAY_NORMAL] = norms_flat
		out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var src_mat := src_mesh.surface_get_material(s)
		if src_mat != null:
			var mat := src_mat.duplicate() as StandardMaterial3D
			if mat != null:
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				mat.albedo_color = tint
				mat.roughness = roughness_val
				if flatten_up_normals:
					# Quiet stone grain; the teammate's original tile texture remains
					# available in the imported scene, outside this combat wrapper.
					var shader := Shader.new()
					shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D floor_texture : source_color;
uniform vec3 base_color = vec3(0.20, 0.22, 0.23);
void fragment() {
	float grain = fract(sin(dot(UV * 4096.0, vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = base_color + (grain - 0.5) * 0.012;
	ROUGHNESS = 0.94;
}
"""
					var floor_material := ShaderMaterial.new()
					floor_material.shader = shader
					floor_material.set_shader_parameter("floor_texture", mat.albedo_texture)
					floor_material.set_shader_parameter("base_color", Vector3(0.20, 0.22, 0.23))
					_floor_shader_material = floor_material
					out_mesh.surface_set_material(s, floor_material)
				else:
					_wall_materials.append(mat)
					out_mesh.surface_set_material(s, mat)
			else:
				out_mesh.surface_set_material(s, src_mat)
	return out_mesh


func _spawn_mesh_piece(key: String, parent: Node3D, node_name: String, pos: Vector3, scale_vec: Vector3, rot_y_deg: float = 0.0) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = _shared_meshes.get(key)
	inst.position = pos
	inst.scale = scale_vec
	inst.rotation_degrees = Vector3(0.0, rot_y_deg, 0.0)
	parent.add_child(inst)
	return inst


func _build_floor_grid() -> void:
	var aabb: AABB = _shared_aabbs.get("floor", AABB(Vector3(-12.5, -0.188, -12.791), Vector3(25.0, 0.376, 25.582)))
	var tile_span := (ARENA_HALF_SIZE * 2.0) / float(FLOOR_TILES_PER_AXIS)
	var scale_x := (tile_span * 1.003) / maxf(0.001, aabb.size.x)
	var scale_z := (tile_span * 1.003) / maxf(0.001, aabb.size.z)
	var top_local_y := aabb.position.y + aabb.size.y
	var center_y := FLOOR_TOP_Y - top_local_y * FLOOR_SCALE_Y
	var tile_scale := Vector3(scale_x, FLOOR_SCALE_Y, scale_z)

	var idx := 0
	for row in range(FLOOR_TILES_PER_AXIS):
		var z := -ARENA_HALF_SIZE + (float(row) + 0.5) * tile_span
		for col in range(FLOOR_TILES_PER_AXIS):
			idx += 1
			var x := -ARENA_HALF_SIZE + (float(col) + 0.5) * tile_span
			_spawn_mesh_piece(
				"floor",
				floor_root,
				"FloorTile_%02d" % idx,
				Vector3(x, center_y, z),
				tile_scale,
				0.0
			)


func _build_perimeter_walls_and_columns() -> void:
	var wall_cycle: Array[String] = [
		"leftWallDouble",
		"leftWallSingle",
		"rightWallDouble",
		"rightWallSingle",
	]
	var panel_span := (ARENA_HALF_SIZE * 2.0) / float(WALL_PANELS_PER_SIDE)

	# North (z = -PERIMETER_OFFSET, facing +Z -> rot_y = +90),
	# West (x = -PERIMETER_OFFSET, facing +X -> rot_y = 180),
	# East (x = +PERIMETER_OFFSET, facing -X -> rot_y = 0)
	for i in range(WALL_PANELS_PER_SIDE):
		var offset_along := -ARENA_HALF_SIZE + (float(i) + 0.5) * panel_span

		var north_key: String = wall_cycle[i % wall_cycle.size()]
		var north_aabb: AABB = _shared_aabbs[north_key]
		var north_scale_z := (panel_span * WALL_OVERLAP) / maxf(0.001, north_aabb.size.z)
		var north_y := -north_aabb.position.y * WALL_SCALE_Y
		_spawn_mesh_piece(
			north_key,
			walls_root,
			"NorthWall_%02d" % (i + 1),
			Vector3(offset_along, north_y, -PERIMETER_OFFSET),
			Vector3(WALL_SCALE_X, WALL_SCALE_Y, north_scale_z),
			90.0
		)

		var west_key: String = wall_cycle[(i + 1) % wall_cycle.size()]
		var west_aabb: AABB = _shared_aabbs[west_key]
		var west_scale_z := (panel_span * WALL_OVERLAP) / maxf(0.001, west_aabb.size.z)
		var west_y := -west_aabb.position.y * WALL_SCALE_Y
		_spawn_mesh_piece(
			west_key,
			walls_root,
			"WestWall_%02d" % (i + 1),
			Vector3(-PERIMETER_OFFSET, west_y, offset_along),
			Vector3(WALL_SCALE_X, WALL_SCALE_Y, west_scale_z),
			180.0
		)

		var east_key: String = wall_cycle[(i + 2) % wall_cycle.size()]
		var east_aabb: AABB = _shared_aabbs[east_key]
		var east_scale_z := (panel_span * WALL_OVERLAP) / maxf(0.001, east_aabb.size.z)
		var east_y := -east_aabb.position.y * WALL_SCALE_Y
		_spawn_mesh_piece(
			east_key,
			walls_root,
			"EastWall_%02d" % (i + 1),
			Vector3(PERIMETER_OFFSET, east_y, offset_along),
			Vector3(WALL_SCALE_X, WALL_SCALE_Y, east_scale_z),
			0.0
		)

		# Low gallery threshold curb along South edge (z = +PERIMETER_OFFSET) so camera sightline is never occluded
		var south_key: String = wall_cycle[(i + 3) % wall_cycle.size()]
		var south_aabb: AABB = _shared_aabbs[south_key]
		var south_scale_z := (panel_span * WALL_OVERLAP) / maxf(0.001, south_aabb.size.z)
		var south_y := -south_aabb.position.y * SOUTH_CURB_SCALE_Y
		_spawn_mesh_piece(
			south_key,
			walls_root,
			"SouthCurb_%02d" % (i + 1),
			Vector3(offset_along, south_y, PERIMETER_OFFSET),
			Vector3(WALL_SCALE_X, SOUTH_CURB_SCALE_Y, south_scale_z),
			-90.0
		)

	# Perimeter pilasters/columns at every 4m bay joint along North, West, and East, plus South corner plinths
	var col_aabb: AABB = _shared_aabbs["uniColumn"]
	var col_scale := Vector3(0.24, WALL_SCALE_Y * 1.03, 0.24)
	var col_y := -col_aabb.position.y * col_scale.y
	var col_idx := 0

	for b in range(WALL_PANELS_PER_SIDE + 1):
		var bx := -ARENA_HALF_SIZE + float(b) * panel_span
		if absf(bx) >= ARENA_HALF_SIZE - 0.01:
			bx = signf(bx) * 20.28
		col_idx += 1
		_spawn_mesh_piece(
			"uniColumn",
			columns_root,
			"NorthColumn_%02d" % col_idx,
			Vector3(bx, col_y, -20.28),
			col_scale,
			0.0
		)

	for b in range(1, WALL_PANELS_PER_SIDE):
		var bz := -ARENA_HALF_SIZE + float(b) * panel_span
		col_idx += 1
		_spawn_mesh_piece(
			"uniColumn",
			columns_root,
			"WestColumn_%02d" % col_idx,
			Vector3(-20.28, col_y, bz),
			col_scale,
			0.0
		)
		col_idx += 1
		_spawn_mesh_piece(
			"uniColumn",
			columns_root,
			"EastColumn_%02d" % col_idx,
			Vector3(20.28, col_y, bz),
			col_scale,
			0.0
		)

	var south_col_scale := Vector3(0.24, SOUTH_CURB_SCALE_Y * 1.4, 0.24)
	var south_col_y := -col_aabb.position.y * south_col_scale.y
	for sx in [-20.28, 20.28]:
		col_idx += 1
		_spawn_mesh_piece(
			"uniColumn",
			columns_root,
			"SouthPlinth_%02d" % col_idx,
			Vector3(sx, south_col_y, 20.28),
			south_col_scale,
			0.0
		)


func _build_cover_decorations() -> void:
	var col_aabb: AABB = _shared_aabbs["uniColumn"]
	var wall_aabb: AABB = _shared_aabbs["leftWallSingle"]
	var cover_height := 2.22
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.30, 0.33, 0.34)
	cap_mat.roughness = 0.65

	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.39, 0.37, 0.30)
	trim_mat.roughness = 0.45
	trim_mat.metallic = 0.25

	var idx := 0
	for rect: Rect2 in Cover.RECTANGLES:
		idx += 1
		var target_w := rect.size.x + 0.03
		var target_d := rect.size.y + 0.03
		var scale_x := target_w / maxf(0.001, col_aabb.size.x)
		var scale_y := cover_height / maxf(0.001, col_aabb.size.y)
		var scale_z := target_d / maxf(0.001, col_aabb.size.z)
		var center_y := -col_aabb.position.y * scale_y
		var center := rect.get_center()
		var pillar := _spawn_mesh_piece(
			"uniColumn",
			cover_root,
			"CoverPillar_%02d" % idx,
			Vector3(center.x, center_y, center.y),
			Vector3(scale_x, scale_y, scale_z),
			0.0
		)

		# Add carved wall-panel wainscoting along the East/West faces of the pedestal
		var side_panel_key := "leftWallSingle" if (idx % 2 == 1) else "rightWallSingle"
		var side_mesh: ArrayMesh = _shared_meshes.get(side_panel_key)
		for side_sign in [-1.0, 1.0]:
			var wainscot := MeshInstance3D.new()
			wainscot.name = "Wainscot_%s" % ("W" if side_sign < 0.0 else "E")
			wainscot.mesh = side_mesh
			wainscot.position = Vector3(side_sign * (col_aabb.size.x * 0.48), 0.0, 0.0)
			wainscot.scale = Vector3(
				0.08 / maxf(0.001, scale_x),
				(cover_height * 0.92 / maxf(0.001, wall_aabb.size.y)) / maxf(0.001, scale_y),
				(target_d * 0.92 / maxf(0.001, wall_aabb.size.z)) / maxf(0.001, scale_z)
			)
			wainscot.rotation_degrees = Vector3(0.0, 0.0 if side_sign < 0.0 else 180.0, 0.0)
			pillar.add_child(wainscot)

		# Add museum stone display plinth cap and brass rim on top so the 2x3m obstacle footprint reads crisply from ortho -55°
		var local_top_y := col_aabb.position.y + col_aabb.size.y
		var cap := MeshInstance3D.new()
		cap.name = "PlinthCap"
		var cap_box := BoxMesh.new()
		cap_box.size = Vector3(col_aabb.size.x * 0.96, col_aabb.size.y * 0.055, col_aabb.size.z * 0.96)
		cap.mesh = cap_box
		cap.material_override = cap_mat
		cap.position = Vector3(0.0, local_top_y - cap_box.size.y * 0.4, 0.0)
		pillar.add_child(cap)

		var rim := MeshInstance3D.new()
		rim.name = "BrassRim"
		var rim_box := BoxMesh.new()
		rim_box.size = Vector3(col_aabb.size.x * 1.01, col_aabb.size.y * 0.025, col_aabb.size.z * 1.01)
		rim.mesh = rim_box
		rim.material_override = trim_mat
		rim.position = Vector3(0.0, local_top_y - cap_box.size.y * 0.85, 0.0)
		pillar.add_child(rim)
