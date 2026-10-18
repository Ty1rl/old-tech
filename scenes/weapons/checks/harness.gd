extends Node3D
const WeaponScene = preload("res://scenes/weapons/weapons.tscn")
const CoverGeometry = preload("res://scenes/prototype/cover.gd")
class TestVisual extends Node3D:
	func muzzle_position(index: int) -> Vector3: return global_position + Vector3(.2 * (index - 2), 1.5, -.65)
	func set_combat_pose(_flash: float, _air: bool, _charge: float) -> void: pass
class TestPlayer extends Node3D:
	var visual: TestVisual
	var camera: Camera3D
	func _init() -> void:
		visual = TestVisual.new()
		add_child(visual)
		camera = Camera3D.new()
		add_child(camera)
var player: TestPlayer
var weapons: WeaponController
var equipment: WeaponEquipment
var cover := CoverGeometry.new()
func _ready() -> void:
	player = TestPlayer.new()
	add_child(player)
	equipment = WeaponEquipment.new()
	weapons = WeaponScene.instantiate()
	weapons.equipment = equipment
	weapons.cover = cover
	add_child(weapons)
