extends SceneTree
const Director = preload("res://scenes/prototype/enemies.gd")
const Weapons = preload("res://scenes/prototype/weapons.gd")
const Cover = preload("res://scenes/prototype/cover.gd")
const Rooms = preload("res://scenes/prototype/rooms.gd")
var checks := 0
var failures: Array[String] = []
class Player extends Node3D:
	var health := 10000.0
	var visual: Node3D
	func take_damage(amount: float) -> void: health -= amount
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func mouse(down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	return e
func run() -> void:
	var cover := Cover.new()
	var director := Director.new()
	director.cover = cover
	root.add_child(director)
	var player := Player.new()
	root.add_child(player)
	player.position = Vector3(0, 0, 5)
	for def in Rooms.definitions():
		cover.set_rectangles(def.cover)
		for kind: StringName in [&"loop", &"zigzag", &"loop_boss", &"final_boss"]:
			director.clear()
			var enemies: Array = director.spawn_formation(&"curve", [kind], player, 0)
			expect(enemies.size() == 1, "Pattern arrives in " + String(def.id))
			if enemies.is_empty(): continue
			var enemy: Node3D = enemies[0]
			if kind == &"final_boss": enemy.debug_set_phase(2)
			enemy.move_speed = 0
			enemy.contact_damage = 0
			var path: Array[Vector3] = []
			if kind == &"zigzag":
				var points: Array = enemy.cable_world_points()
				for i in range(points.size() / 2): path.append((points[i * 2] + points[i * 2 + 1]) * .5)
			else:
				var toward := Vector2(player.position.x - enemy.position.x, player.position.z - enemy.position.z).angle()
				for i in range(33): path.append(enemy.position + Vector3(cos(toward + i * TAU / 32), 0, sin(toward + i * TAU / 32)) * 1.9)
			var weapons := preload("res://scenes/weapons/weapons.tscn").instantiate()
			weapons.cover = cover
			root.add_child(weapons)
			weapons.select_tool(1)
			weapons.handle_event(mouse(true), player, path[0])
			for point in path:
				var move := InputEventMouseMotion.new()
				move.button_mask = MOUSE_BUTTON_MASK_LEFT
				weapons.handle_event(move, player, point)
			expect(not weapons.ring.preview_blocked, "Actual raw stroke does not hit cover: " + String(def.id) + "/" + String(kind))
			weapons.handle_event(mouse(false), player, path[-1])
			for frame in range(150):
				weapons.step(1.0 / 60, player, path[-1], enemies, 1.0 / 60)
				enemy.step_enemy(1.0 / 60, null)
			expect(enemy.pattern_open, "Actual outbound + complete cutter launch opens " + String(kind) + " in " + String(def.id))
			weapons.free()
	director.clear()
	director.free()
	player.free()
	await process_frame
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
