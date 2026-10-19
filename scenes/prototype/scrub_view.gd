class_name ScrubView
extends RefCounted

# A temporary display pose in the frozen inspection world. Call finish() before
# capturing gameplay state or resuming simulation. History payloads are never used
# as writable storage, and no gameplay step or facing setter runs here.
const DURATION := 0.14
const MAX_ENEMIES := 32
const MAX_PULSES := 8

var active := false
var _elapsed := 0.0
var _tracks: Array[Dictionary] = []
var _from: Dictionary = {}
var _target: Dictionary = {}
var _player: Node3D
var _weapons: WeaponController


func capture_pose(player: Node3D, director: Node3D, weapons: WeaponController) -> Dictionary:
	var pose := {"enemies": {}, "pulses": []}
	if is_instance_valid(player):
		pose["player"] = player.transform
		var model: Node3D = player.get("model")
		if is_instance_valid(model):
			pose["model"] = model.transform
	if is_instance_valid(director):
		var count := 0
		for enemy in director.get("enemies"):
			if count >= MAX_ENEMIES:
				break
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
				continue
			var entry := {"root": enemy.transform}
			var visual: Node3D = enemy.get("visual_root")
			if is_instance_valid(visual):
				entry["visual"] = visual.transform
			pose.enemies[int(enemy.combat_id())] = entry
			count += 1
	if is_instance_valid(weapons):
		pose["ring"] = weapons.ring.head
		pose["ring_visible"] = weapons.ring.flight_phase != "idle"
		for pulse in weapons.flash.pulses:
			if pose.pulses.size() >= MAX_PULSES:
				break
			pose.pulses.append(pulse["pos"])
	return pose


func begin(from_pose: Dictionary, player: Node3D, director: Node3D, weapons: WeaponController) -> void:
	finish()
	_from = from_pose.duplicate(true)
	_target = capture_pose(player, director, weapons)
	_player = player
	_weapons = weapons
	_elapsed = 0.0
	if is_instance_valid(player):
		_track(player, _from.get("player", player.transform))
		var model: Node3D = player.get("model")
		if is_instance_valid(model):
			_track(model, _from.get("model", model.transform))
	if is_instance_valid(director):
		var count := 0
		for enemy in director.get("enemies"):
			if count >= MAX_ENEMIES:
				break
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
				continue
			var old: Dictionary = _from.get("enemies", {}).get(int(enemy.combat_id()), {})
			_track(enemy, old.get("root", enemy.transform))
			var visual: Node3D = enemy.get("visual_root")
			if is_instance_valid(visual):
				_track(visual, old.get("visual", visual.transform))
			count += 1
	if is_instance_valid(weapons):
		_track(weapons, weapons.transform)
	active = true
	_apply(0.0)


func step(real_delta: float) -> void:
	if not active:
		return
	_elapsed += maxf(0.0, real_delta)
	if _elapsed >= DURATION:
		finish()
		return
	var t := _elapsed / DURATION
	_apply(t * t * (3.0 - 2.0 * t))


func finish() -> void:
	if active:
		_apply(1.0)
	for track in _tracks:
		var node: Variant = track.node
		if is_instance_valid(node):
			node.physics_interpolation_mode = track.mode
			node.reset_physics_interpolation()
	_tracks.clear()
	_from.clear()
	_target.clear()
	_player = null
	_weapons = null
	active = false


func _track(node: Node3D, from_transform: Transform3D) -> void:
	_tracks.append({"node": node, "from": from_transform, "target": node.transform,
		"mode": node.physics_interpolation_mode})
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.reset_physics_interpolation()


func _apply(weight: float) -> void:
	for track in _tracks:
		var node: Variant = track.node
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var target_transform: Transform3D = track.target
		# Assign the original value at the end to avoid interpolation roundoff.
		if weight >= 1.0:
			node.transform = target_transform
		else:
			var from_transform: Transform3D = track.from
			var rotation := from_transform.basis.orthonormalized().get_rotation_quaternion().slerp(
				target_transform.basis.orthonormalized().get_rotation_quaternion(), weight)
			# Size belongs to the restored state; only location and facing ease.
			node.transform = Transform3D(Basis(rotation) * Basis.from_scale(target_transform.basis.get_scale()),
				from_transform.origin.lerp(target_transform.origin, weight))
	if not is_instance_valid(_weapons):
		return
	var ring: Vector3 = _target.get("ring", Vector3.ZERO)
	if weight < 1.0 and _from.get("ring_visible", false) and _target.get("ring_visible", false):
		ring = (_from.get("ring", ring) as Vector3).lerp(ring, weight)
	_weapons.ring.head = ring
	var pulses: Array = _weapons.flash.pulses
	var old_pulses: Array = _from.get("pulses", [])
	var target_pulses: Array = _target.get("pulses", [])
	for index in range(mini(pulses.size(), target_pulses.size())):
		var target_position: Vector3 = target_pulses[index]
		pulses[index]["pos"] = target_position if weight >= 1.0 or index >= old_pulses.size() else (old_pulses[index] as Vector3).lerp(target_position, weight)
	var player: Node3D = _player if is_instance_valid(_player) else null
	_weapons.rebuild_visuals(player)
