extends Node3D

# Art adapter only. Enemy owns health, part queries and the world-time tick.
const FootPlant = preload("res://scenes/prototype/foot_plant.gd")
const MODELS := {
	&"blue": preload("res://assets/enemies/conjoined.glb"),
	&"yellow": preload("res://assets/enemies/patient.glb"),
	&"orange": preload("res://assets/enemies/bellows_belly.glb"),
	&"front_guard": preload("res://assets/enemies/false_face/false_face.glb"),
	&"side_guard": preload("res://assets/enemies/borrowed_heart/borrowed_heart.glb"),
}
const PART_NAMES := {
	&"blue": ["BlueConnector", "", ""],
	&"yellow": ["", "YellowCore", ""],
	&"orange": ["", "", "OrangePlate"],
	&"front_guard": ["Cable_Blue", "Core_Yellow", "Shield_Orange"],
	&"side_guard": ["CutConduit", "CoreTarget", "HeatCover"],
}


static func warmup(parent: Node) -> void:
	if DisplayServer.get_name() == "headless": return
	# Render each skin/material once off-screen at startup, rather than
	# compiling all five on the first mixed-pack frame. No gameplay nodes.
	var viewport := SubViewport.new()
	viewport.name = "CreatureShaderWarmup"
	viewport.size = Vector2i(64, 64)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	parent.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var i := 0
	for packed: PackedScene in MODELS.values():
		var instance := packed.instantiate()
		stage.add_child(instance)
		instance.position.x = (i - 2) * 3.0
		for animation_player: AnimationPlayer in instance.find_children("*", "AnimationPlayer", true, false):
			animation_player.active = false
		i += 1
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 7, 12)
	camera.look_at(Vector3(0, 1, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 19
	camera.current = true
	stage.add_child(DirectionalLight3D.new())
	parent.get_tree().create_timer(1.0).timeout.connect(viewport.queue_free)

var foot_plant := FootPlant.new()
var skeleton: Skeleton3D
var kind: StringName
var model: Node3D
var animation: AnimationPlayer
var cable: Node3D
var core: Node3D
var plate: Node3D
var shield_rim: Node3D
var phase := 0.0
var height := 2.5
var _meshes: Array[MeshInstance3D] = []
var _flash: StandardMaterial3D


func build(p_kind: StringName) -> void:
	kind = p_kind
	model = MODELS[kind].instantiate()
	add_child(model)
	var names: Array = PART_NAMES[kind]
	if names[0] != "": cable = model.find_child(names[0], true, false)
	if names[1] != "": core = model.find_child(names[1], true, false)
	if names[2] != "": plate = model.find_child(names[2], true, false)
	if kind == &"front_guard": shield_rim = model.find_child("Shield_Rim", true, false)
	height = 2.75 if kind == &"side_guard" else 2.5
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	animation = model.find_children("*", "AnimationPlayer", true, false)[0]
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation.play("Idle")
	animation.advance(0)
	_flash = StandardMaterial3D.new()
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash.albedo_color = Color(1, 1, 1, .45)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh not in [cable, core, plate, shield_rim]: _meshes.append(mesh)
	set_process(false)
	set_physics_process(false)


func sync(cut: bool, exposed: bool, broken: bool, _heat_ratio: float) -> void:
	if cable: cable.visible = not cut
	if core: core.visible = exposed and not broken
	if plate: plate.visible = not exposed
	if shield_rim: shield_rim.visible = not exposed


func step_visual(world_delta: float, speed: float, staggered: bool, hit_flash: bool) -> void:
	if world_delta <= 0: return
	var clip := "Walk" if speed > .1 and not staggered else "Idle"
	if animation.current_animation != clip:
		animation.play(clip)
	# Match the short authored shuffles to travel; foot planting holds stance.
	var authored_speed := .35 if kind in [&"blue", &"yellow", &"orange"] else .8
	var rate := clampf(speed / authored_speed, .05, 6.5) if clip == "Walk" else 1.0
	phase += world_delta * rate
	animation.advance(world_delta * rate)
	if staggered: foot_plant.reset()
	else: foot_plant.apply(skeleton)
	for mesh in _meshes:
		mesh.material_overlay = _flash if hit_flash else null
