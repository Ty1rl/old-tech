class_name EnemyNavigation
extends NavigationAgent3D
## A world-time-driven native route. CombatEnemy alone applies displacement.
@export var settings: EnemyNavigationSettings = preload("res://scenes/navigation/navigation_settings.tres")
var maps: ExhibitNavigation
var intent := Vector3.ZERO
var refreshes := 0
var advances := 0
var queries := 0
var _generation := -1
var _elapsed := 0.0
var _dirty := true
var _assigned_map := RID()
var _last_intent := Vector3.ZERO
var _safe_direction := Vector3.ZERO
var _safe_fraction := 0.0
var _avoidance_epoch := -1
var avoidance_updates := 0

func _ready() -> void:
	avoidance_enabled = false
	max_neighbors = settings.avoidance_max_neighbors
	neighbor_distance = settings.avoidance_neighbor_distance
	time_horizon_agents = settings.avoidance_horizon
	time_horizon_obstacles = .3
	velocity_computed.connect(_on_safe_velocity)
	path_desired_distance = settings.waypoint_distance
	target_desired_distance = settings.target_distance
	path_max_distance = settings.path_deviation
	path_metadata_flags = 0
	path_changed.connect(_on_path_changed)

func _on_path_changed() -> void: queries += 1

func reset_intent(restored_intent: Vector3) -> void:
	suspend_avoidance()
	intent = restored_intent
	_elapsed = 0
	_dirty = true
	_assigned_map = RID()
	_generation = -1
	set_navigation_map(RID()) # Discard the future route, not the restored actor pose.

func next_direction(world_delta: float, desired_intent: Vector3, clearance: float) -> Vector3:
	if world_delta <= 0 or maps == null: return Vector3.ZERO
	var map := maps.map_for(clearance)
	if not map.is_valid():
		suspend_avoidance()
		return Vector3.ZERO
	if map != _assigned_map or maps.generation != _generation:
		suspend_avoidance()
		set_navigation_map(map)
		_assigned_map = map
		_generation = maps.generation
		_dirty = true
	_elapsed += world_delta
	intent = desired_intent
	if _dirty or (_elapsed >= settings.repath_interval and intent.distance_to(_last_intent) >= settings.target_motion_threshold):
		var goal := NavigationServer3D.map_get_closest_point(map, intent)
		path_height_offset = goal.y - (get_parent() as Node3D).global_position.y
		target_position = goal
		_last_intent = intent
		_elapsed = 0
		_dirty = false
		refreshes += 1
	if is_navigation_finished(): return Vector3.ZERO
	var next := get_next_path_position()
	advances += 1
	var parent := get_parent() as Node3D
	var toward := Vector3(next.x - parent.global_position.x, 0, next.z - parent.global_position.z)
	return toward.normalized() if toward.length_squared() > .00001 else Vector3.ZERO

func floor_contains(point: Vector3, tolerance := .08) -> bool:
	if not _assigned_map.is_valid(): return false
	var closest := NavigationServer3D.map_get_closest_point(_assigned_map, point)
	return Vector2(closest.x, closest.z).distance_to(Vector2(point.x, point.z)) <= tolerance

func _on_safe_velocity(safe: Vector3) -> void:
	if not avoidance_enabled or Engine.get_physics_frames() <= _avoidance_epoch + 1: return
	avoidance_updates += 1
	_safe_direction = safe.normalized()
	_safe_fraction = clampf(safe.length() / maxf(.001, max_speed), 0, 1)

func idle() -> void:
	if avoidance_enabled: velocity = Vector3.ZERO

func suspend_avoidance() -> void:
	_avoidance_epoch = Engine.get_physics_frames()
	avoidance_enabled = false
	velocity = Vector3.ZERO
	set_velocity_forced(Vector3.ZERO)
	_safe_direction = Vector3.ZERO
	_safe_fraction = 0

func avoid_velocity(desired: Vector3, world_delta: float, clearance: float, crowded: bool) -> Vector3:
	if not crowded:
		suspend_avoidance()
		return desired
	if world_delta <= 0 or not _assigned_map.is_valid():
		suspend_avoidance()
		return Vector3.ZERO
	# RVO runs in real physics time. Feed real velocities, then consume only
	# its bounded direction/speed fraction using the actor's current world delta.
	# A slow transition can never reuse a future full-speed displacement.
	var scale := world_delta / maxf(.00001, get_physics_process_delta_time())
	radius = clearance
	max_speed = maxf(.001, desired.length() * scale)
	if not avoidance_enabled: _avoidance_epoch = Engine.get_physics_frames()
	avoidance_enabled = true
	velocity = desired * scale
	return _safe_direction * desired.length() * _safe_fraction
