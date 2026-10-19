class_name WeaponComponent
extends Node3D
## Common contact/result semantics; each concrete weapon owns its action and simulation.
signal resolved_hit(tool: StringName, result: Dictionary, context: Dictionary, enemy_id: int)
signal combat_event(kind: StringName, point: Vector3, strength: float)
signal feedback_changed(text: String)
const CoverGeometry = preload("res://scenes/prototype/cover.gd")
var equipment: WeaponEquipment
var cover: CoverGeometry
var last_feedback := "Ready":
	set(value):
		if last_feedback == value: return
		last_feedback = value
		feedback_changed.emit(value)

func bind(gear: WeaponEquipment, geometry: CoverGeometry) -> void:
	equipment = gear
	cover = geometry

func _can_use_tool(tool: StringName, amount: float = 0.000001) -> bool:
	return equipment != null and equipment.can_use(tool, amount)

func _spend_tool(tool: StringName, amount: float) -> float:
	return equipment.spend(tool, amount) if equipment != null else 0.0

func _enemy_combat_id(enemy: Node3D) -> int:
	return int(enemy.combat_id())


func _attack_enemy(enemy: Node3D, tool: StringName, amount: float, contact: Vector3, context: Dictionary) -> Dictionary:
	var result: Dictionary = enemy.receive_attack(tool, amount, contact, context)
	var cue := StringName(result.get("cue", &""))
	if not cue.is_empty():
		combat_event.emit(cue, contact, 1.0)
	elif float(result.get("dealt", 0.0)) > 0.0:
		combat_event.emit(&"hit", contact, clampf(float(result.dealt) / 80.0, 0.15, 1.2))
	resolved_hit.emit(tool,result,context,_enemy_combat_id(enemy))
	return result

func _record_hit_feedback(tool_label: String, res: Dictionary) -> void:
	var dealt := float(res.get("dealt", 0.0))
	var armored := bool(res.get("armored", false))
	var killed := bool(res.get("killed", false))
	var tags := ""
	if armored:
		tags += " ARMORED"
	if killed:
		tags += " KILLED"
	last_feedback = "%s hit %.1f dmg%s" % [tool_label, dealt, tags]

func _is_live_enemy(enemy: Variant) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	if float(enemy.health) <= 0.0:
		return false
	return true

func _aim_dir_xz(origin_world: Vector3, aim_world: Vector3) -> Vector2:
	var d := Vector2(aim_world.x - origin_world.x, aim_world.z - origin_world.z)
	if d.length_squared() > 1e-6:
		return d.normalized()
	return Vector2(0.0, -1.0)

func _swept_circle_entry_t(a: Vector2, b: Vector2, center: Vector2, radius: float) -> float:
	var f := a - center
	var r_sq := radius * radius
	if f.length_squared() <= r_sq:
		return 0.0
	var d := b - a
	var a_coef := d.length_squared()
	if a_coef <= 1e-10:
		return -1.0
	var b_coef := 2.0 * f.dot(d)
	var c_coef := f.length_squared() - r_sq
	var disc := b_coef * b_coef - 4.0 * a_coef * c_coef
	if disc < 0.0:
		return -1.0
	var root := sqrt(disc)
	var t1 := (-b_coef - root) / (2.0 * a_coef)
	var t2 := (-b_coef + root) / (2.0 * a_coef)
	if t1 >= 0.0 and t1 <= 1.0:
		return t1
	if t1 < 0.0 and t2 >= 0.0:
		return 0.0
	return -1.0
