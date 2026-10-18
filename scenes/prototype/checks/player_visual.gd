extends SceneTree

const ToolStyle = preload("res://scenes/prototype/tool_style.gd")
const ScrubView = preload("res://scenes/prototype/scrub_view.gd")

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func release_moves() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		Input.action_release(action)


func collect_meshes(node: Node, out: Array[MeshInstance3D], materials: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh != null:
		out.append(node)
		var mat: Material = node.material_override if node.material_override != null else node.mesh.surface_get_material(0)
		if mat != null:
			materials[mat.get_instance_id()] = mat
	for child in node.get_children():
		collect_meshes(child, out, materials)


func run() -> void:
	release_moves()

	# 1. Original scenes/player.tscn remains untouched when instantiated standalone
	var base_player := (load("res://scenes/player.tscn") as PackedScene).instantiate()
	var base_mesh := base_player.get_node("MeshInstance3D") as MeshInstance3D
	var base_arrow := base_mesh.get_node("MeshInstance3D2") as MeshInstance3D
	expect(base_mesh.mesh is CylinderMesh and base_arrow.visible and base_arrow.mesh is PrismMesh,
		"Original scenes/player.tscn keeps its cylinder and arrow meshes untouched")
	base_player.free()

	# 2. Prototype arena player replaces visible cylinder/arrow with articulated humanoid under player.model
	var arena: Node3D = (load("res://scenes/prototype/arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	arena.set_process(false)

	var player: CharacterBody3D = arena.player
	var model: Node3D = player.model
	var arrow := model.get_node_or_null("MeshInstance3D2") as Node3D
	var collision := player.get_node("CollisionShape3D") as CollisionShape3D
	expect(model == player.get_node("MeshInstance3D") and model.visible,
		"Existing player.model root node is preserved and visible")
	expect(model is MeshInstance3D and (model as MeshInstance3D).mesh == null and arrow != null and not arrow.visible,
		"Original cylinder mesh and red prism arrow are hidden in the prototype")
	expect(collision.shape is CylinderShape3D and is_equal_approx((collision.shape as CylinderShape3D).height, 1.0)
		and player.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and is_equal_approx(player.camera.size, 30.0),
		"Player collision shape and orthographic camera setup remain unchanged")

	var visual: Node3D = player.visual
	expect(is_instance_valid(visual) and visual.get_parent() == model,
		"PlayerVisual is attached under player.model")
	expect(not visual.is_processing() and not visual.is_physics_processing(),
		"PlayerVisual runs no independent _process or _physics_process loops")

	# 3. Articulated parts, chunky top-down proportions, and restrained mesh/material counts
	expect(is_instance_valid(visual.head) and is_instance_valid(visual.visor)
		and is_instance_valid(visual.torso) and is_instance_valid(visual.shoulders)
		and is_instance_valid(visual.left_shoulder) and is_instance_valid(visual.right_shoulder)
		and is_instance_valid(visual.backpack) and visual.boots.size() == 2
		and is_instance_valid(visual.left_boot) and is_instance_valid(visual.right_boot)
		and is_instance_valid(visual.held_tool),
		"Articulated humanoid exposes head, torso, shoulders, boots, backpack, and held tool")

	var meshes: Array[MeshInstance3D] = []
	var materials: Dictionary = {}
	collect_meshes(visual, meshes, materials)
	expect(meshes.size() >= 12 and meshes.size() <= 32 and materials.size() <= 6,
		"Geometry and material counts stay restrained (%d meshes, %d materials)" % [meshes.size(), materials.size()])

	player.reset_state()
	var head_y: float = visual.head.global_position.y
	var torso_y: float = visual.torso.global_position.y
	var boot_y: float = visual.left_boot.global_position.y
	expect(head_y > torso_y + 0.35 and torso_y > boot_y + 0.45,
		"Vertical proportions stack boots, torso, and head clearly")
	expect(visual.right_shoulder.position.x - visual.left_shoulder.position.x >= 0.60,
		"Shoulders have wide, top-down readable chunky proportions")
	expect(visual.backpack.position.z > 0.15 and visual.held_tool.position.z < -0.30 and visual.visor.position.z < -0.10,
		"Backpack sits on +Z back while visor and held tool project toward -Z forward")

	# Facing rotation carries held tool and backpack with player.model
	player.step(1.0 / 60.0, player.global_position + Vector3(10.0, 0.0, 0.0))
	var tool_dir: Vector3 = visual.held_tool.global_position - player.global_position
	var pack_dir: Vector3 = visual.backpack.global_position - player.global_position
	expect(tool_dir.x > 0.25 and pack_dir.x < -0.15,
		"Aiming +X rotates held tool forward (+X) and backpack behind (-X) with player.model")

	# 4. Equipped tool palette (ToolStyle) without recoloring the body into 4 bright colors
	player.reset_state()
	expect(player.visual_tool == 1 and visual.tool_id == &"ring"
		and visual.tool_material.albedo_color.is_equal_approx(ToolStyle.RING),
		"Default equipped appearance is ring with ToolStyle.RING color")
	var base_coat: Color = visual.coat_material.albedo_color
	var base_trim: Color = visual.trim_material.albedo_color
	var base_head: Color = visual.head_material.albedo_color
	var expected_tools := {
		1: {"id": &"ring", "color": ToolStyle.RING},
		2: {"id": &"beam", "color": ToolStyle.BEAM},
		3: {"id": &"cone", "color": ToolStyle.CONE},
		4: {"id": &"clock", "color": ToolStyle.CLOCK},
	}
	for idx: int in [1, 2, 3, 4]:
		player.set_visual_tool(idx)
		var info: Dictionary = expected_tools[idx]
		var expected_id: StringName = info["id"]
		var expected_color: Color = info["color"]
		expect(player.visual_tool == idx and visual.tool_id == expected_id
			and visual.tool_material.albedo_color.is_equal_approx(expected_color),
			"set_visual_tool(%d) applies %s palette color" % [idx, String(expected_id)])
		for attachment_id: StringName in visual.tool_attachments:
			var att: Node3D = visual.tool_attachments[attachment_id]
			expect(att.visible == (attachment_id == expected_id),
				"Only %s held tool attachment is visible when tool %d is selected" % [String(expected_id), idx])
		expect(visual.coat_material.albedo_color.is_equal_approx(base_coat)
			and visual.trim_material.albedo_color.is_equal_approx(base_trim)
			and visual.head_material.albedo_color.is_equal_approx(base_head),
			"Body materials remain neutral when switching to tool %d" % idx)

	player.set_visual_tool(0)
	expect(player.visual_tool == 1 and visual.tool_id == &"ring", "Out-of-range low tool index clamps to 1 (ring)")
	player.set_visual_tool(9)
	expect(player.visual_tool == 4 and visual.tool_id == &"clock", "Out-of-range high tool index clamps to 4 (clock)")
	player.reset_state()
	expect(player.visual_tool == 1 and visual.tool_id == &"ring", "reset_state restores default ring appearance")

	# 5. Walk and idle animation driven only by player.step real delta
	var idle_before: float = visual.idle_phase
	var walk_before: float = visual.walk_phase
	await process_frame
	await physics_frame
	expect(is_equal_approx(visual.idle_phase, idle_before) and is_equal_approx(visual.walk_phase, walk_before),
		"Animation does not advance across engine frames without player.step (frozen inspection safe)")

	player.step(0.0, Vector3(0, 0, -10))
	player.step(-0.2, Vector3(0, 0, -10))
	expect(is_equal_approx(visual.idle_phase, idle_before) and is_equal_approx(visual.walk_phase, walk_before),
		"Zero or negative delta does not advance walk or idle phase")

	for i in range(6):
		player.step(0.05, Vector3(0, 0, -10))
	expect(visual.idle_phase > idle_before and is_equal_approx(visual.stride_blend, 0.0),
		"Stationary player.step advances idle motion while keeping stride_blend at zero")

	Input.action_press("move_right")
	for i in range(8):
		await physics_frame
		player.step(1.0 / 30.0, Vector3(0, 0, -10), true)
	release_moves()
	expect(visual.walk_phase > 0.5 and visual.stride_blend > 0.5,
		"Moving player.step advances walk_phase and stride_blend using real delta even during slow-time")
	expect(absf(visual.left_leg_pivot.rotation.x) > 0.05
		and is_equal_approx(visual.left_leg_pivot.rotation.x, -visual.right_leg_pivot.rotation.x),
		"Walking swings left and right legs in opposite phase")
	expect(visual.body_pivot.position.y > 0.52 and model.position.is_equal_approx(Vector3(0, 0.5, 0)),
		"Body bobbing animates child pivot without perturbing player.model root transform")

	# 6. Snapshot and ScrubView pose contract remain exact
	var snap: Dictionary = player.capture_state()
	expect(snap.keys().size() == 4 and snap.has("position") and snap.has("velocity")
		and snap.has("health") and snap.has("facing"),
		"Player snapshot schema remains exact without cosmetic limb state")
	var expected_pos: Vector3 = snap["position"]
	var expected_facing: Basis = snap["facing"]
	var scrub := ScrubView.new()
	var pose_a: Dictionary = scrub.capture_pose(player, arena.director, arena.weapons)
	player.position += Vector3(4.0, 0.0, -2.0)
	player.model.basis = Basis(Vector3.UP, PI * 0.5)
	var pose_b: Dictionary = scrub.capture_pose(player, arena.director, arena.weapons)
	var walk_at_scrub: float = visual.walk_phase
	scrub.begin(pose_a, player, arena.director, arena.weapons)
	scrub.step(ScrubView.DURATION * 0.5)
	expect(is_equal_approx(visual.walk_phase, walk_at_scrub),
		"ScrubView interpolation does not advance player walk animation")
	scrub.finish()
	expect(scrub.capture_pose(player, arena.director, arena.weapons) == pose_b,
		"ScrubView finish restores exact player and model transforms")

	player.restore_state(snap)
	expect(player.position.is_equal_approx(expected_pos) and player.model.basis.is_equal_approx(expected_facing)
		and player.model.position.is_equal_approx(Vector3(0, 0.5, 0)),
		"restore_state restores exact root position and model facing")

	arena.queue_free()
	await process_frame
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
