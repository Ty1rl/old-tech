extends Node3D
## Disposable check composition. Production gets its region from jam-2's room kit.
const Director = preload("res://scenes/prototype/enemies.gd")
const Cover = preload("res://scenes/prototype/cover.gd")
const Harness = preload("res://scenes/weapons/checks/harness.gd")
const WeaponScene = preload("res://scenes/weapons/weapons.tscn")
var weapons: WeaponController
var equipment: WeaponEquipment
const BLOCKS: Array[Rect2] = [Rect2(-2,-6,4,8), Rect2(4,0,4,6), Rect2(-10,6,8,2)]
var director: Node3D
var region: NavigationRegion3D
var cover := Cover.new()
var player: PlayerProbe
class PlayerProbe extends Node3D:
	var time_controller: TimeController
	var hits := 0
	var visual: Node3D
	var camera: Camera3D
	var can_act: bool:
		get: return not time_controller.emergency_active and not time_controller.exhausted
	func _init() -> void:
		visual = Harness.TestVisual.new()
		add_child(visual)
		camera = Camera3D.new()
		add_child(camera)
		time_controller = TimeController.new()
		time_controller.auto_advance = false
		time_controller.settings = time_controller.settings.duplicate()
		time_controller.settings.capacity = 100000
		add_child(time_controller)
	func take_damage(amount: float) -> void:
		hits += 1
		time_controller.apply_hit(amount)
func _ready() -> void:
	cover.set_rectangles(BLOCKS)
	_build_geometry()
	region = NavigationRegion3D.new()
	region.name = "CheckRegion"
	region.add_to_group(&"museum_navigation")
	var mesh := NavigationMesh.new()
	mesh.agent_radius = 0 # Authored walkable grid, not a previously eroded bake.
	mesh.cell_size = .2
	mesh.cell_height = .1
	var vertices := PackedVector3Array()
	for z in range(21):
		for x in range(21): vertices.append(Vector3(x * 2 - 20, 0, z * 2 - 20))
	mesh.vertices = vertices
	for z in range(20):
		for x in range(20):
			var center := Vector3(x * 2 - 19, 0, z * 2 - 19)
			if cover.intersects_circle(center): continue
			var first := z * 21 + x
			mesh.add_polygon(PackedInt32Array([first, first + 21, first + 22, first + 1]))
	region.navigation_mesh = mesh
	add_child(region)
	director = Director.new()
	director.cover = cover
	add_child(director)
	player = PlayerProbe.new()
	add_child(player)
	player.position = Vector3(0,0,12)
	player.time_controller.begin_attempt()
	equipment = WeaponEquipment.new()
	weapons = WeaponScene.instantiate()
	weapons.equipment = equipment
	weapons.cover = cover
	weapons.time_controller = player.time_controller
	add_child(weapons)
func ready_maps() -> bool:
	return director.navigation.ready_for(.65) and director.navigation.ready_for(3.6)

func _build_geometry() -> void:
	_box(Vector3(0,-.25,0),Vector3(40,.5,40),Color("29343d"))
	for rectangle in BLOCKS:
		_box(Vector3(rectangle.get_center().x,1.1,rectangle.get_center().y),Vector3(rectangle.size.x,2.2,rectangle.size.y),Color("8f806c"))
func _box(point: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = point
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var skin := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	skin.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	skin.material_override = material
	body.add_child(skin)
	add_child(body)
