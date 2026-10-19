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
	var turn_dot := .985 if strength >= .999 else .92
	if not _forward.is_zero_approx() and _forward.dot(forward) < turn_dot:
		if strength >= .999:
			contacts.clear() # A sharp aim turn must not cross or twist planted legs.
		else:
			# Softly pull anchors toward current foot positions during turns instead of popping.
			for foot_key: int in contacts.keys():
				var cur_w := skeleton.global_transform * skeleton.get_bone_global_pose(foot_key).origin
				contacts[foot_key] = (contacts[foot_key] as Vector3).lerp(cur_w, 0.55)
	_forward = forward
	if _legs.is_empty():
		for foot in range(skeleton.get_bone_count()):
			var name := skeleton.get_bone_name(foot)
			if not (name.ends_with("foot.L") or name.ends_with("foot.R")): continue
			var shin := skeleton.get_bone_parent(foot)
			var thigh := skeleton.get_bone_parent(shin)
			_legs.append({
				"foot": foot,
				"shin": shin,
				"thigh": thigh,
				"thigh_parent": skeleton.get_bone_parent(thigh),
				"height": skeleton.get_bone_global_rest(foot).origin.y,
			})
	var soft := strength < .999
	var skel_inv := skeleton.global_transform.affine_inverse()
	for leg in _legs:
		var foot: int = leg.foot
		var thigh: int = leg.thigh
		var shin: int = leg.shin
		var local_foot := skeleton.get_bone_global_pose(foot)
		var lift_margin := .018 if soft else .025
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
		var raw_target := skel_inv * anchor
		# Retain heel/toe lift from the clip while holding its ground position.
		raw_target.y = local_foot.origin.y
		if soft:
			# Prevent lateral leg crossing/twisting during sideways strafes.
			raw_target.x = local_foot.origin.x + clampf(raw_target.x - local_foot.origin.x, -.048, .048)
			raw_target.z = local_foot.origin.z + clampf(raw_target.z - local_foot.origin.z, -max_hold, max_hold)
		var target := local_foot.origin.lerp(raw_target, clampf(strength, 0.0, 1.0))
		var thigh_pose := skeleton.get_bone_global_pose(thigh)
		var shin_pose := skeleton.get_bone_global_pose(shin)
		var hip := thigh_pose.origin
		var knee := shin_pose.origin
		var ankle := local_foot.origin
		var upper := hip.distance_to(knee)
		var lower := knee.distance_to(ankle)
		var reach := target - hip
		var max_ext := .94 if soft else .995
		if reach.length() >= (upper + lower) * max_ext:
			if not soft:
				contacts.erase(foot)
				continue
			reach = reach.normalized() * ((upper + lower) * max_ext)
			target = hip + reach
		var reach_len := maxf(reach.length(), .001)
		var axis := reach / reach_len
		var bend := knee - hip
		bend -= axis * bend.dot(axis)
		if bend.length_squared() < .0001: bend = Vector3.FORWARD
		var along := (upper * upper + reach_len * reach_len - lower * lower) / (2.0 * reach_len)
		var joint := hip + axis * along + bend.normalized() * sqrt(maxf(0.0, upper * upper - along * along))

		# In Godot 4 Skeleton3D, bone_pose_rotation is the bone's local basis directly
		# (global_basis = parent_global_basis * local_basis); multiplying by rest.inverse()
		# inverted non-identity GLTF leg rests (~180 deg on thigh.L/R) and flipped the leg upward.
		var from_upper := knee - hip
		var to_upper := joint - hip
		var thigh_global_basis := thigh_pose.basis
		var turn_upper := Quaternion.IDENTITY
		if from_upper.length_squared() >= .00001 and to_upper.length_squared() >= .00001:
			turn_upper = Quaternion(from_upper.normalized(), to_upper.normalized())
			thigh_global_basis = Basis(turn_upper) * thigh_pose.basis
		var thigh_parent: int = leg.thigh_parent
		var thigh_parent_basis := skeleton.get_bone_global_pose(thigh_parent).basis if thigh_parent >= 0 else Basis.IDENTITY
		skeleton.set_bone_pose_rotation(thigh, (thigh_parent_basis.inverse() * thigh_global_basis).get_rotation_quaternion())

		var shin_mid_basis := Basis(turn_upper) * shin_pose.basis
		var ankle_mid := joint + Basis(turn_upper) * (ankle - knee)
		var from_lower := ankle_mid - joint
		var to_lower := target - joint
		var shin_global_basis := shin_mid_basis
		if from_lower.length_squared() >= .00001 and to_lower.length_squared() >= .00001:
			var turn_lower := Quaternion(from_lower.normalized(), to_lower.normalized())
			shin_global_basis = Basis(turn_lower) * shin_mid_basis
		skeleton.set_bone_pose_rotation(shin, (thigh_global_basis.inverse() * shin_global_basis).get_rotation_quaternion())
		skeleton.set_bone_pose_rotation(foot, (shin_global_basis.inverse() * local_foot.basis).get_rotation_quaternion())


func point_bone(skeleton: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> void:
	if from.length_squared() < .00001 or to.length_squared() < .00001: return
	var basis := Basis(Quaternion(from.normalized(),to.normalized())) * skeleton.get_bone_global_pose(bone).basis
	set_basis(skeleton,bone,basis)


func set_basis(skeleton: Skeleton3D, bone: int, basis: Basis) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * basis).get_rotation_quaternion())
