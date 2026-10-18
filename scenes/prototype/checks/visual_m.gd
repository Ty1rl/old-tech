extends SceneTree
const Enemy = preload("res://scenes/prototype/enemy.gd")
const PatternEnemy = preload("res://scenes/prototype/pattern_enemy.gd")
const PatternVisual = preload("res://scenes/prototype/pattern_visual.gd")
const RoomEnvironment = preload("res://scenes/prototype/room_environment.gd")
const Rooms = preload("res://scenes/prototype/rooms.gd")
var checks := 0
var failures: Array[String] = []
var resources: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func run() -> void:
	var enemy := Enemy.new()
	root.add_child(enemy)
	for kind: StringName in [&"blue", &"side_guard"]:
		enemy.configure(kind, Vector3.ZERO, 1)
		var v: Node3D = enemy.part_visual
		var state: Dictionary = enemy.capture_state()
		expect(v.split_companion.size() >= (6 if kind == &"blue" else 2), "Complete companion mesh group found: " + String(kind))
		for mesh in v.split_companion: expect(mesh.is_visible_in_tree(), "Intact companion/couplings visible")
		enemy.cable_cut = true
		enemy._update_warden_visuals()
		for mesh in v.split_companion: expect(not mesh.visible, "Cut removes every other-half mesh including collars")
		expect(not v.cable.visible and not v.cable_marker.visible, "Cut leaves no blue remnants")
		var cut_state: Dictionary = enemy.capture_state()
		enemy.restore_state(state)
		for mesh in v.split_companion: expect(mesh.visible, "Rewind restores every companion mesh")
		enemy.restore_state(cut_state)
		for mesh in v.split_companion: expect(not mesh.visible, "Rewind to cut does not resurrect detached pieces")
		v.step_visual(.1, 2, false, false, &"commit")
		expect(not v.leg_cycling, "Committed attack holds legs without a running shuffle")
	for kind: StringName in [&"yellow", &"orange", &"front_guard", &"side_guard"]:
		enemy.configure(kind, Vector3.ZERO, 1)
		var v: Node3D = enemy.part_visual
		for facing in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
			enemy.facing = facing
			enemy.plate_broken = true
			enemy._update_warden_visuals()
			if v.core_marker:
				expect(v.core_marker.global_position.distance_to(enemy.core_world_position()) < .001, "Yellow marker stays exactly on current query anchor")
				expect(v.core_marker.material_override.no_depth_test, "Yellow readable from every facing")
			if v.plate: expect(not v.plate.visible, "Orange removed entirely")
			if v.shield_rim: expect(not v.shield_rim.visible, "Orange shield rim removed entirely")
	enemy.free()
	var a := PatternEnemy.new()
	var b := PatternEnemy.new()
	root.add_child(a); root.add_child(b)
	a.configure(&"loop_boss", Vector3.ZERO, 3)
	b.configure(&"loop_boss", Vector3(8, 0, 0), 4)
	var av: Node3D = a.pattern_visual
	var bv: Node3D = b.pattern_visual
	expect(av.feet[0].mesh == bv.feet[0].mesh, "Repeated pattern boxes share geometry")
	expect(av.core.mesh == bv.core.mesh and av.links[0].mesh == bv.links[0].mesh, "Repeated spheres and links share geometry")
	expect(av.core.material_override == bv.core.material_override and av.plates[0].material_override == bv.plates[0].material_override, "Repeated pattern parts share immutable materials")
	var initial := Vector3i(PatternVisual._boxes.size(), PatternVisual._balls.size(), PatternVisual._rods.size())
	var material_count: int = PatternVisual._materials.size()
	var nodes_before: int = av.get_child_count()
	for tick in range(600):
		av.sync(tick % 16, tick % 2 == 0, tick % 3 == 0, tick % 2, tick / 60.0, 0, &"windup", true)
		av.pose(tick / 60.0, 1, &"windup", .4)
	expect(Vector3i(PatternVisual._boxes.size(), PatternVisual._balls.size(), PatternVisual._rods.size()) == initial and material_count == PatternVisual._materials.size() and nodes_before == av.get_child_count(), "600 state/pose ticks allocate no new shared geometry/materials/nodes")
	av.sync(0, true, true, 0, 0, 0, &"approach", true)
	for plate in av.plates: expect(not plate.visible, "All pattern orange pieces including outriggers disappear")
	resources = {"shared_boxes": PatternVisual._boxes.size(), "shared_spheres": PatternVisual._balls.size(), "shared_rods": PatternVisual._rods.size(), "shared_materials": material_count}
	for kind: StringName in [&"loop", &"zigzag", &"pair", &"loop_boss", &"sequence_boss", &"final_boss"]:
		a.configure(kind, Vector3.ZERO, 3)
		for phase in range(a.phase_count()):
			a.debug_set_phase(phase)
			for facing in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
				a.facing = facing
				var v: Node3D = a.pattern_visual
				var target: Node3D = v.valves[a.pair_progress] if a.active_pattern() == &"pair" and not a.pattern_open else v.core
				expect(target.global_position.distance_to(a.core_world_position()) < .001, "Every phase/facing yellow visual matches current query")
				var points: Array = a.cable_world_points()
				for i in range(v.links.size()):
					var rod: MeshInstance3D = v.links[i]
					var start: Vector3 = rod.global_transform * (Vector3.DOWN * rod.mesh.height * .5)
					var end: Vector3 = rod.global_transform * (Vector3.UP * rod.mesh.height * .5)
					expect(start.distance_to(points[i * 2]) < .001 and end.distance_to(points[i * 2 + 1]) < .001, "Every phase/facing blue rod endpoints match query")
				v.sync(0, false, false, 0, 0, phase, &"approach", true)
				for plate in v.plates: expect(plate.visible, "Closed phase restores orange visibility")
	a.free(); b.free()
	var museum := RoomEnvironment.new()
	root.add_child(museum)
	for def in Rooms.definitions():
		museum.apply_room(def)
		expect(museum.get_cover_world_rectangles() == def.cover, "Room trim retains original solid cover footprints")
		expect(museum.cover_root.get_child_count() == def.cover.size(), "Every solid obstacle has an authored visual kit")
		var shared: Dictionary = {}
		for index in range(def.cover.size()):
			var kit: Node3D = museum.cover_root.get_child(index)
			var rect: Rect2 = def.cover[index]
			var scale_root: Node3D = kit.get_node("ScaleRoot")
			expect(kit.position.is_equal_approx(Vector3(rect.get_center().x, 0, rect.get_center().y)), "Authored kit centers on the solid footprint")
			expect(scale_root.scale.is_equal_approx(Vector3(rect.size.x, 1, rect.size.y)), "Authored kit scales to the solid footprint")
			var meshes: Array[Node] = kit.find_children("*", "MeshInstance3D", true, false)
			expect(not meshes.is_empty(), "Authored cover contains visible meshes")
			for mesh: MeshInstance3D in meshes:
				var material := mesh.get_active_material(0)
				var key := kit.scene_file_path + ":" + String(kit.get_path_to(mesh))
				if shared.has(key): expect(material == shared[key], "Repeated kit meshes reuse authored materials")
				else: shared[key] = material

	museum.free()
	await process_frame
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures, "resources": resources}))
	quit(0 if failures.is_empty() else 1)
