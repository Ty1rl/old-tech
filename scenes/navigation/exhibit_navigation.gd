class_name ExhibitNavigation
extends Node
## Native clearance maps derived ONLY from the active authored room region.
## No world tick, substitute room or hand-written pathfinder lives here.
const CoverGeometry = preload("res://scenes/prototype/cover.gd")
var cover: CoverGeometry
var _published_frame: Array[int] = []
var _probes: Array[Vector3] = []
var _confirmed: Array[bool] = []

@export var settings: EnemyNavigationSettings = preload("res://scenes/navigation/navigation_settings.tres")
var source_region: NavigationRegion3D
var generation := 0
var build_times_usec: Array[int] = []
var polygon_counts: Array[int] = []
var _baked_meshes: Array[NavigationMesh] = []
var _mesh: NavigationMesh
var _transform := Transform3D.IDENTITY
var _maps: Array[RID] = []
var _regions: Array[RID] = []
var _ready_maps: Array[bool] = []
var _refresh := false
var _pending_builds := 0

func _create_maps() -> void:
	for bucket in settings.clearance_buckets.slice(0, 4):
		var map := NavigationServer3D.map_create()
		NavigationServer3D.map_set_cell_size(map, settings.cell_size)
		NavigationServer3D.map_set_cell_height(map, .1)
		NavigationServer3D.map_set_active(map, true)
		_maps.append(map)
		var region := NavigationServer3D.region_create()
		_regions.append(region)
		_ready_maps.append(false)
		_published_frame.append(0)
		_probes.append(Vector3.ZERO)
		_confirmed.append(false)
		polygon_counts.append(0)
		_baked_meshes.append(null)

func _free_maps() -> void:
	for region in _regions: NavigationServer3D.free_rid(region)
	for map in _maps: NavigationServer3D.free_rid(map)
	_regions.clear()
	_maps.clear()
	_ready_maps.clear()
	_published_frame.clear()
	_probes.clear()
	_confirmed.clear()
	polygon_counts.clear()
	_baked_meshes.clear()

func _exit_tree() -> void:
	generation += 1
	_free_maps()

func _source_changed() -> void: _refresh = true

func sync_region() -> void:
	var active: NavigationRegion3D
	for node in get_tree().get_nodes_in_group(&"museum_navigation"):
		if node is NavigationRegion3D and node.enabled and node.is_inside_tree() and node.get_world_3d() == get_viewport().find_world_3d():
			active = node
			break
	if active != source_region or _refresh or (active != null and (active.navigation_mesh != _mesh or active.global_transform != _transform)):
		bind_region(active)

func bind_region(region: NavigationRegion3D) -> void:
	if is_instance_valid(source_region) and source_region.navigation_mesh_changed.is_connected(_source_changed):
		source_region.navigation_mesh_changed.disconnect(_source_changed)
	source_region = region
	if region != null: region.navigation_mesh_changed.connect(_source_changed)
	_mesh = region.navigation_mesh if region != null else null
	_transform = region.global_transform if region != null else Transform3D.IDENTITY
	_refresh = false
	generation += 1
	_ready_maps.fill(false)
	_confirmed.fill(false)
	if _pending_builds > 0:
		_refresh = true
		return
	# Fresh native regions/maps also handle an identical mesh being re-enabled;
	# no stale native topology or target projection survives a room change.
	_free_maps()
	if _mesh == null or _mesh.get_polygon_count() == 0: return
	_create_maps()
	var vertices := _mesh.get_vertices()
	var faces := PackedVector3Array()
	for i in range(_mesh.get_polygon_count()):
		var polygon := _mesh.get_polygon(i)
		for j in range(1, polygon.size() - 1):
			var a := _transform * vertices[polygon[0]]
			var b := _transform * vertices[polygon[j]]
			var c := _transform * vertices[polygon[j + 1]]
			# NavigationMesh polygons may use either order; add_faces requires Godot
			# clockwise front faces (the cross product points down on an XZ floor).
			if (b - a).cross(c - a).y > 0:
				faces.append_array(PackedVector3Array([a, c, b]))
			else: faces.append_array(PackedVector3Array([a, b, c]))
	for i in range(_maps.size()):
		var data := NavigationMeshSourceGeometryData3D.new()
		data.add_faces(faces, Transform3D.IDENTITY)
		# Match the existing conservative swept-circle/AABB mover exactly at
		# exhibit corners. Recast erosion alone has rounded clearance corners.
		if cover != null:
			for rectangle: Rect2 in cover.rectangles:
				var bounds := rectangle.grow(settings.clearance_buckets[i] + settings.clearance_padding)
				var points := PackedVector3Array([Vector3(bounds.position.x,0,bounds.position.y),Vector3(bounds.end.x,0,bounds.position.y),Vector3(bounds.end.x,0,bounds.end.y),Vector3(bounds.position.x,0,bounds.end.y)])
				data.add_projected_obstruction(points, _transform.origin.y - 1, 5, true)
		var mesh := NavigationMesh.new()
		mesh.cell_size = settings.cell_size
		mesh.cell_height = .1
		# The source is already eroded by its authored bake radius. Shrink only
		# the remaining clearance; padding covers rasterization at exhibit edges.
		var additional := maxf(.05, settings.clearance_buckets[i] - _mesh.agent_radius + settings.clearance_padding)
		mesh.agent_radius = ceilf(additional / settings.cell_size) * settings.cell_size
		mesh.agent_height = 1.5
		mesh.agent_max_climb = .2
		mesh.edge_max_error = .25
		mesh.region_min_size = 0
		var started := Time.get_ticks_usec()
		_pending_builds += 1
		NavigationServer3D.bake_from_source_geometry_data_async(mesh, data, _baked.bind(i, generation, mesh, started))

func _baked(index: int, revision: int, mesh: NavigationMesh, started: int) -> void:
	_pending_builds -= 1
	if revision != generation or not is_inside_tree(): return
	_baked_meshes[index] = mesh
	polygon_counts[index] = mesh.get_polygon_count()
	NavigationServer3D.region_set_navigation_mesh(_regions[index], mesh)
	# Attach only AFTER geometry exists; an async empty-region build must not
	# race publication of its first real mesh.
	NavigationServer3D.region_set_map(_regions[index], _maps[index])
	_published_frame[index] = Engine.get_physics_frames()
	if mesh.get_polygon_count() > 0: _probes[index] = mesh.get_vertices()[mesh.get_polygon(0)[0]]
	_ready_maps[index] = mesh.get_polygon_count() > 0
	build_times_usec.append(Time.get_ticks_usec() - started)
	if build_times_usec.size() > 16: build_times_usec.pop_front()

func map_for(clearance: float) -> RID:
	for i in range(_maps.size()):
		if clearance <= settings.clearance_buckets[i] + .001:
			if not _ready_maps[i] or Engine.get_physics_frames() < _published_frame[i] + 2: return RID()
			if NavigationServer3D.map_get_iteration_id(_maps[i]) == 0: return RID()
			if not _confirmed[i]:
				# An identical rebake need not increment the native map iteration.
				# Wait for synchronization and verify geometry, not an iteration bump.
				# Verify an actual baked vertex before caching any target projection.
				if NavigationServer3D.map_get_closest_point(_maps[i], _probes[i]).distance_to(_probes[i]) > .01: return RID()
				_confirmed[i] = true
			return _maps[i]
	return RID() # An unsupported size must never silently use too-small clearance.

func ready_for(clearance: float) -> bool: return map_for(clearance).is_valid()

func contains_floor(point: Vector3) -> bool:
	# RVO may use the clearance mesh's spare margin while passing a peer. The
	# authored floor and the actor's full swept collision still bound that step.
	if not is_instance_valid(source_region) or not source_region.enabled: return false
	var map := source_region.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0: return false
	var closest := NavigationServer3D.map_get_closest_point(map, point)
	return Vector2(closest.x,closest.z).distance_to(Vector2(point.x,point.z)) <= .08
