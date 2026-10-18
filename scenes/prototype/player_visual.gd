extends Node3D

# Cosmetic only: the arena advances animation in real time. No independent tick
# or rig data enters the bounded gameplay history.
const Character = preload("res://assets/characters/protagonist/protagonist.glb")
const TOOLS = [preload("res://assets/equipment/ring_caster.glb"),
	preload("res://assets/equipment/flash_camera.glb"),
	preload("res://assets/equipment/heat_bellows.glb"),
	preload("res://assets/equipment/time_device.glb")]
const TOOL_IDS: Array[StringName] = [&"ring", &"beam", &"cone", &"clock"]
const HOLDS = ["RingHold", "FlashHold", "ConeHold", "ClockHold"]
# Actual props have different handle spacing from the art-preview stand-ins.
# These grip positions keep both handles within reach of the exported rig.
const MOUNTS = [Vector3(.12, 1.32, -.10), Vector3(.21, 1.30, -.25),
	Vector3(0, 1.35, -.10), Vector3(.115, 1.30, -.25)]

var character: Node3D
var skeleton: Skeleton3D
var animation: AnimationPlayer
var held_tool: Node3D
var tool_attachments: Dictionary = {}
var tool_index := 1
var tool_id: StringName = &"ring"
var walk_phase := 0.0
var idle_phase := 0.0
var stride_blend := 0.0
var _holds: Array[Dictionary] = []
var _sockets: Dictionary = {}
var _prop_sockets: Dictionary = {}
var _bones: Dictionary = {}
var _equipped_index := 0
var _built := false


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	build()


func build() -> void:
	if _built: return
	_built = true
	name = "PlayerVisual"
	# The unchanged collider's bottom is at the player root. That root settles
	# onto the floor after reset; model itself is offset +.5 above it.
	position = Vector3(0, -.5, 0)
	character = Character.instantiate()
	add_child(character)
	skeleton = character.find_children("*", "Skeleton3D", true, false)[0]
	animation = character.find_children("*", "AnimationPlayer", true, false)[0]
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for side in ["L", "R"]:
		for part in ["upper_arm", "forearm", "hand"]:
			var id: String = part + "." + side
			_bones[id] = skeleton.find_bone(id)
		var socket: Node3D = character.find_child("Grip_" + side, true, false)
		_sockets[side] = socket.transform
	_cache_holds()
	held_tool = Node3D.new()
	held_tool.name = "HeldEquipment"
	add_child(held_tool)
	for index in range(TOOLS.size()):
		var prop: Node3D = TOOLS[index].instantiate()
		held_tool.add_child(prop)
		tool_attachments[TOOL_IDS[index]] = prop
		_prop_sockets[TOOL_IDS[index]] = {"L": prop.find_child("Grip_L", true, false),
			"R": prop.find_child("Grip_R", true, false)}
	set_tool_index(tool_index)
	reset_pose()


func _cache_holds() -> void:
	for clip in HOLDS:
		var pose := {}
		var source := animation.get_animation(clip)
		for track in range(source.get_track_count()):
			var path := source.track_get_path(track)
			if path.get_subname_count() != 1 or source.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			var bone := String(path.get_subname(0))
			if bone in _bones:
				pose[_bones[bone]] = source.track_get_key_value(track, 0)
		_holds.append(pose)


func set_tool_index(index: int) -> void:
	build()
	tool_index = clampi(index, 1, 4)
	if _equipped_index == tool_index: return
	_equipped_index = tool_index
	tool_id = TOOL_IDS[tool_index - 1]
	for id: StringName in tool_attachments:
		tool_attachments[id].visible = id == tool_id
	_fit_equipment()


func reset_pose() -> void:
	build()
	walk_phase = 0
	idle_phase = 0
	stride_blend = 0
	animation.play("Idle")
	animation.seek(0, true)
	animation.advance(0)
	_fit_equipment()


func step_visual(real_delta: float, planar_speed: float, max_speed: float = 6.0) -> void:
	build()
	if real_delta <= 0: return
	var dt := minf(real_delta, .25)
	var ratio := clampf(planar_speed / maxf(.001, max_speed), 0, 1)
	stride_blend = move_toward(stride_blend, ratio, dt * 8)
	var moving := stride_blend > .05
	var clip := "Walk" if moving else "Idle"
	if animation.current_animation != clip:
		animation.play(clip, .12)
	var rate := lerpf(.8, 2.2, stride_blend) if moving else 1.0
	animation.advance(dt * rate)
	if moving: walk_phase += dt * rate * TAU
	else: idle_phase += dt
	_fit_equipment()


func _fit_equipment() -> void:
	if held_tool == null: return
	# Preserve animated torso/legs, overlay the authored arm pose, then fit each
	# hand to its actual equipment grip using a bounded two-bone solve.
	for bone: int in _holds[tool_index - 1]:
		skeleton.set_bone_pose_rotation(bone, _holds[tool_index - 1][bone])
	skeleton.force_update_all_bone_transforms()
	var root_bone := skeleton.find_bone("root")
	var bob := skeleton.get_bone_pose_position(root_bone).y
	held_tool.position = MOUNTS[tool_index - 1] + Vector3(0, bob, 0)
	for side in ["R", "L"]:
		var socket: Node3D = _prop_sockets[tool_id][side]
		var target := skeleton.global_transform.affine_inverse() * socket.global_transform
		_solve_arm(side, target * (_sockets[side] as Transform3D).affine_inverse())


func _solve_arm(side: String, target: Transform3D) -> void:
	var upper: int = _bones["upper_arm." + side]
	var lower: int = _bones["forearm." + side]
	var hand: int = _bones["hand." + side]
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var elbow := skeleton.get_bone_global_pose(lower).origin
	var wrist := skeleton.get_bone_global_pose(hand).origin
	var a := shoulder.distance_to(elbow)
	var b := elbow.distance_to(wrist)
	var delta := target.origin - shoulder
	var distance := clampf(delta.length(), absf(a-b) + .001, a+b - .001)
	var axis := delta.normalized()
	var bend := elbow - shoulder
	bend -= axis * bend.dot(axis)
	if bend.length_squared() < .0001: bend = axis.cross(Vector3.FORWARD)
	if bend.length_squared() < .0001: bend = axis.cross(Vector3.UP)
	var along := (a*a + distance*distance - b*b) / (2*distance)
	var joint := shoulder + axis*along + bend.normalized()*sqrt(maxf(0, a*a - along*along))
	_point_bone(upper, elbow - shoulder, joint - shoulder)
	elbow = skeleton.get_bone_global_pose(lower).origin
	wrist = skeleton.get_bone_global_pose(hand).origin
	_point_bone(lower, wrist - elbow, shoulder + axis*distance - elbow)
	_set_bone_basis(hand, target.basis.orthonormalized())


func _point_bone(bone: int, from: Vector3, to: Vector3) -> void:
	if from.length_squared() < .0001 or to.length_squared() < .0001: return
	var turn := Quaternion(from.normalized(), to.normalized())
	_set_bone_basis(bone, Basis(turn) * skeleton.get_bone_global_pose(bone).basis)


func _set_bone_basis(bone: int, desired: Basis) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(bone, (basis.inverse() * desired).get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()


func grip_error(side: String) -> float:
	var bone: int = _bones["hand." + side]
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(bone) * (_sockets[side] as Transform3D)
	var grip: Node3D = _prop_sockets[tool_id][side]
	return hand.origin.distance_to(grip.global_position)
