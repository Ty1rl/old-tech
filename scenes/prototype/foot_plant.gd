extends RefCounted

# Preserve ground contacts from authored clips. No simulation/history ownership.
var contacts: Dictionary = {}
var _legs: Array[Dictionary] = []
var _forward := Vector3.ZERO


func reset() -> void:
	contacts.clear()
	_forward = Vector3.ZERO


func apply(skeleton: Skeleton3D, strength: float = 1.0, max_hold: float = 0.7) -> void:
	if strength <= .001:
		contacts.clear()
		return
	var forward := skeleton.global_basis.z.normalized()
	var turn_dot := .985 if strength >= .999 else .94
	if not _forward.is_zero_approx() and _forward.dot(forward) < turn_dot:
		contacts.clear() # A sharp aim turn must not cross or twist planted legs.
	_forward = forward
	if _legs.is_empty():
		for foot in range(skeleton.get_bone_count()):
			var name := skeleton.get_bone_name(foot)
			if not (name.ends_with("foot.L") or name.ends_with("foot.R")): continue
			var shin := skeleton.get_bone_parent(foot)
			var thigh := skeleton.get_bone_parent(shin)
			_legs.append({"foot":foot, "shin":shin, "thigh":thigh,
				"height":skeleton.get_bone_global_rest(foot).origin.y})
	skeleton.force_update_all_bone_transforms()
	var soft := strength < .999
	for leg in _legs:
		var foot: int = leg.foot
		var local_foot := skeleton.get_bone_global_pose(foot)
		var lift_margin := .020 if soft else .025
		if local_foot.origin.y > float(leg.height) + lift_margin:
			contacts.erase(foot)
			continue
		var world_foot := skeleton.global_transform * local_foot.origin
		if not contacts.has(foot): contacts[foot] = world_foot
		var anchor: Vector3 = contacts[foot]
		var slip := world_foot.distance_to(anchor)
		# Teleports, rewind or a large shove must never leave a leg behind.
		if slip > 1.2 or (not soft and slip > max_hold):
			contacts.erase(foot)
			continue
		if soft and slip > max_hold:
			# Allow gentle ground slide instead of pinning and snapping mid-stride.
			anchor = world_foot + (anchor - world_foot).normalized() * max_hold
			contacts[foot] = anchor
		var raw_target := skeleton.global_transform.affine_inverse() * anchor
		# Retain heel/toe lift from the clip while holding its ground position.
		raw_target.y = local_foot.origin.y
		if soft:
			# Prevent lateral leg crossing/twisting during sideways strafes.
			raw_target.x = local_foot.origin.x + clampf(raw_target.x - local_foot.origin.x, -.055, .055)
			raw_target.z = local_foot.origin.z + clampf(raw_target.z - local_foot.origin.z, -max_hold, max_hold)
		var target := local_foot.origin.lerp(raw_target, clampf(strength, 0.0, 1.0))
		var hip := skeleton.get_bone_global_pose(leg.thigh).origin
		var knee := skeleton.get_bone_global_pose(leg.shin).origin
		var ankle := local_foot.origin
		var upper := hip.distance_to(knee)
		var lower := knee.distance_to(ankle)
		var reach := target - hip
		var max_ext := .945 if soft else .995
		if reach.length() >= (upper + lower) * max_ext:
			if not soft:
				contacts.erase(foot)
				continue
			reach = reach.normalized() * ((upper + lower) * max_ext)
			target = hip + reach
		var axis := reach.normalized()
		var bend := knee - hip
		bend -= axis * bend.dot(axis)
		if bend.length_squared() < .0001: bend = Vector3.FORWARD
		var along := (upper*upper + reach.length_squared() - lower*lower) / (2*maxf(reach.length(),.001))
		var joint := hip + axis*along + bend.normalized()*sqrt(maxf(0, upper*upper-along*along))
		point_bone(skeleton,leg.thigh,knee-hip,joint-hip)
		knee = skeleton.get_bone_global_pose(leg.shin).origin
		ankle = skeleton.get_bone_global_pose(foot).origin
		point_bone(skeleton,leg.shin,ankle-knee,target-knee)
		set_basis(skeleton,foot,local_foot.basis)


func point_bone(skeleton: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> void:
	if from.length_squared() < .00001 or to.length_squared() < .00001: return
	var basis := Basis(Quaternion(from.normalized(),to.normalized())) * skeleton.get_bone_global_pose(bone).basis
	set_basis(skeleton,bone,basis)


func set_basis(skeleton: Skeleton3D, bone: int, basis: Basis) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var rest := skeleton.get_bone_rest(bone).basis
	skeleton.set_bone_pose_rotation(bone,(rest.inverse() * parent_basis.inverse() * basis).get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()
