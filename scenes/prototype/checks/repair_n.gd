extends SceneTree

const Gestures = preload("res://scenes/prototype/repair_gestures.gd")
const RepairScene = preload("res://scenes/prototype/repair.tscn")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func _weapons_attacking(weapons: Node) -> bool:
	if "ring" in weapons and weapons.get("ring") != null and bool(weapons.get("ring").get("drawing")):
		return true
	if "flash" in weapons and weapons.get("flash") != null and bool(weapons.get("flash").get("charging")):
		return true
	if "bellows" in weapons and weapons.get("bellows") != null and bool(weapons.get("bellows").get("active")):
		return true
	if "ring_drawing" in weapons and bool(weapons.get("ring_drawing")):
		return true
	if "beam_charging" in weapons and bool(weapons.get("beam_charging")):
		return true
	if "cone_active" in weapons and bool(weapons.get("cone_active")):
		return true
	return false


func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: " + description)


func frames(count: int = 2) -> void:
	for _i in range(count):
		await process_frame


func key(code: Key, pressed: bool = true, shift: bool = false, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.shift_pressed = shift
	event.echo = echo
	root.push_input(event, true)


func gui_pos(panel: Control, board_point: Vector2) -> Vector2:
	var local: Vector2 = panel._board_offset() + board_point * panel._board_scale()
	return panel.board.get_global_transform_with_canvas() * local


func mouse_button(panel: Control, board_point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = gui_pos(panel, board_point)
	event.global_position = event.position
	root.push_input(event, true)


func mouse_motion(panel: Control, board_point: Vector2, held: bool = true) -> void:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	event.position = gui_pos(panel, board_point)
	event.global_position = event.position
	root.push_input(event, true)


func raw_mouse_button(button_index: MouseButton, pressed: bool, pos: Vector2 = Vector2(640, 400)) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if (button_index == MOUSE_BUTTON_LEFT and pressed) else 0
	event.position = pos
	event.global_position = pos
	root.push_input(event, true)


func stroke_points(panel: Control, points: Array[Vector2]) -> void:
	if points.is_empty():
		return
	mouse_button(panel, points[0], true)
	for pt in points.slice(1):
		mouse_motion(panel, pt, true)
	mouse_button(panel, points[-1], false)


func click_connect_pair(panel: Control, pair_index: int) -> void:
	var pair: Dictionary = panel.active_op["pairs"][pair_index]
	mouse_button(panel, pair["a"], true)
	mouse_button(panel, pair["a"], false)
	mouse_button(panel, pair["b"], true)
	mouse_button(panel, pair["b"], false)


func complete_active_operation(panel: Control) -> void:
	if panel.active_kind == &"connect":
		var pairs: Array = panel.active_op.get("pairs", [])
		for pair_idx in range(pairs.size()):
			if not (pair_idx in panel.connected_pairs):
				click_connect_pair(panel, pair_idx)
				if panel == null or not is_instance_valid(panel) or panel.is_queued_for_deletion():
					return
	else:
		stroke_points(panel, panel.route)


class MockRepairConditionView extends Control:
	var bound_equipment: WeaponEquipment = null
	var bound_tool: StringName = &""
	var bind_calls: int = 0

	func bind_equipment(next_equipment: WeaponEquipment, next_tool: StringName) -> void:
		bound_equipment = next_equipment
		bound_tool = next_tool
		bind_calls += 1

	func segment_count() -> int:
		return bound_equipment.repair_steps if bound_equipment != null else 4

	func filled_segments() -> int:
		if bound_equipment == null:
			return 0
		return segment_count() if bound_equipment.is_full(bound_tool) else bound_equipment.stage(bound_tool)


func run() -> void:
	root.size = Vector2i(1280, 800)

	# 1. Editable Repair Scene Hierarchy, RepairToolSpec 3D Part Alignment, Public API & ConditionSlot Check
	var standalone_repair: WeaponRepair = RepairScene.instantiate() as WeaponRepair
	standalone_repair._allow_full_preview = true
	var mock_cond := MockRepairConditionView.new()
	standalone_repair.get_node("Panel/Margin/Column/Board/ConditionSlot").add_child(mock_cond)
	var test_gear := WeaponEquipment.new()
	test_gear.spend(&"ring", test_gear.capacity(&"ring"))
	test_gear.spend(&"beam", test_gear.capacity(&"beam") * 0.62) # partial wear within stage 1
	test_gear.spend(&"cone", test_gear.capacity(&"cone"))
	var emitted_stages: Array[String] = []
	standalone_repair.stage_changed.connect(func(t: StringName, s: int):
		emitted_stages.append("%s:%d" % [String(t), s]))
	root.add_child(standalone_repair)
	standalone_repair.setup({"equipment": test_gear, "tool": &"ring", "allow_full_preview": true})
	await frames()
	expect(standalone_repair.get_node_or_null("Panel/Margin/Column/HeaderRow/Heading") != null
		and standalone_repair.get_node_or_null("Panel/Margin/Column/Board/ToolBackdropViewport/SubViewport/PreviewCamera") != null
		and standalone_repair.get_node_or_null("Panel/Margin/Column/Board/GestureOverlay") != null
		and standalone_repair.get_node_or_null("Panel/Margin/Column/Board/ConditionSlot") != null
		and standalone_repair.get_node_or_null("Panel/Margin/Column/Feedback") != null,
		"repair.tscn authors static named UI hierarchy including ConditionSlot bound via @onready")
	expect(Gestures.TOOL_ORDER == [&"ring", &"beam", &"cone"] and not Gestures.TOOL_SPECS.has("clock"),
		"Three weapons only (ring, beam, cone); clock removed from repair_gestures.gd")
	expect(standalone_repair.has_active_session(&"ring") and not standalone_repair.has_active_session(&"beam"),
		"WeaponRepair.has_active_session reports active repair session for selected damaged tool")
	standalone_repair.show_message("Custom teaching prompt")
	expect(standalone_repair.feedback.text == "Custom teaching prompt",
		"WeaponRepair.show_message updates feedback label cleanly")
	standalone_repair.show_stage_hint("Hint: Spin the cassette reel")
	expect(standalone_repair._stage_hint_active and standalone_repair.instructions.text == "Hint: Spin the cassette reel",
		"WeaponRepair.show_stage_hint activates non-blocking stage demonstration overlay")
	standalone_repair.clear_stage_hint()
	expect(not standalone_repair._stage_hint_active,
		"WeaponRepair.clear_stage_hint restores standard stage prompt")
	expect(mock_cond.bind_calls > 0 and mock_cond.bound_tool == &"ring" and mock_cond.segment_count() == 4 and mock_cond.filled_segments() == 0,
		"ConditionSlot binds RepairConditionView to active equipment and tool with 4 segments")

	# Verify all 3 weapons resolve named 3D model parts, project inside the 520x260 board,
	# and order stages, trace contacts (1->4), and connect pairs (a->b) strictly left-to-right.
	for t_id in Gestures.TOOL_ORDER:
		standalone_repair.switch_tool(t_id)
		await frames(1)
		var all_resolved := standalone_repair.projected_operations.size() == 3
		var stage_xs: Array[float] = []
		var traces_ltr := true
		var connects_ltr := true
		for op in standalone_repair.projected_operations:
			if not bool(op.get("part_resolved", false)):
				all_resolved = false
			var kind := StringName(op.get("kind", &"spin"))
			if kind == &"spin":
				stage_xs.append(Vector2(op["center"]).x)
			elif kind == &"connect":
				var pairs: Array = op.get("pairs", [])
				var sum_x := 0.0
				for p in pairs:
					var ax := Vector2(p["a"]).x
					var bx := Vector2(p["b"]).x
					if not (ax < bx):
						connects_ltr = false
					sum_x += (ax + bx) * 0.5
				stage_xs.append(sum_x / maxf(1.0, float(pairs.size())))
			elif kind == &"trace":
				var pts: Array = op.get("points", [])
				var sum_x := 0.0
				for pi in range(pts.size()):
					sum_x += Vector2(pts[pi]).x
					if pi > 0 and not (Vector2(pts[pi - 1]).x < Vector2(pts[pi]).x):
						traces_ltr = false
				stage_xs.append(sum_x / maxf(1.0, float(pts.size())))
		expect(all_resolved, "%s resolves all 3 named 3D GLB part nodes and projects coordinates via PreviewCamera" % String(t_id))
		expect(stage_xs.size() == 3 and stage_xs[0] < stage_xs[1] and stage_xs[1] < stage_xs[2],
			"%s orders repair stages strictly left-to-right (%s)" % [String(t_id), str(stage_xs)])
		expect(traces_ltr and connects_ltr,
			"%s orders trace contacts (1->4) and connect pairs (a->b) strictly left-to-right" % String(t_id))

		# Verify per-instance translucent model materials without mutating shared GLB Mesh resources
		var holder: Node3D = standalone_repair.model_instances.get(String(t_id))
		var mesh_nodes := holder.find_children("*", "MeshInstance3D", true, false)
		var all_translucent := not mesh_nodes.is_empty()
		for mn in mesh_nodes:
			var mi := mn as MeshInstance3D
			var mat := mi.get_active_material(0) as BaseMaterial3D
			if mat == null or mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS or mat.albedo_color.a >= 0.95 or mat.emission_enabled:
				all_translucent = false
		var fresh_glb: Node3D = standalone_repair.ToolModels[String(t_id)].instantiate()
		var fresh_meshes := fresh_glb.find_children("*", "MeshInstance3D", true, false)
		var shared_untouched := not fresh_meshes.is_empty()
		for fmn in fresh_meshes:
			var fmi := fmn as MeshInstance3D
			var fmat := fmi.get_active_material(0) as BaseMaterial3D
			if fmat != null and (fmat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or not is_equal_approx(fmat.albedo_color.a, 1.0)):
				shared_untouched = false
		fresh_glb.free()
		expect(all_translucent and shared_untouched,
			"%s applies per-instance depth-prepass translucency without mutating shared GLB materials" % String(t_id))

	# Verify neutral ToolStyle.REPAIR_GUIDE color, get_model_region(), frozen gesture targets while dragging, and finite stage-hint demo
	expect(standalone_repair.GUIDE == standalone_repair.ToolStyle.REPAIR_GUIDE
		and standalone_repair.get_model_region().size.x > 200.0,
		"WeaponRepair uses neutral ToolStyle.REPAIR_GUIDE and exposes get_model_region()")
	standalone_repair.switch_tool(&"ring")
	await frames(1)
	var frozen_before: Vector2 = standalone_repair.projected_operations[0]["center"]
	standalone_repair.dragging = true
	var ring_holder: Node3D = standalone_repair.model_instances.get("ring")
	ring_holder.position += Vector3(0.4, 0.2, 0.0)
	standalone_repair._rebuild_routes_for_tool(&"ring")
	var frozen_during: Vector2 = standalone_repair.projected_operations[0]["center"]
	standalone_repair.dragging = false
	standalone_repair._refresh()
	expect(frozen_before.is_equal_approx(frozen_during) and is_equal_approx(standalone_repair._switch_transition_alpha, 1.0),
		"Active repair gesture freezes projected targets and snaps switch transition so targets never drift mid-gesture")
	standalone_repair.show_stage_hint("Finite hint check")
	for _tick in range(15):
		standalone_repair._process(0.25)
	expect(standalone_repair._stage_hint_passes >= standalone_repair.STAGE_HINT_MAX_PASSES and not standalone_repair.is_processing(),
		"Stage hint demonstration runs a finite number of passes and stops processing automatically")
	standalone_repair.clear_stage_hint()

	var cone_holder: Node3D = standalone_repair.model_instances.get("cone")
	expect(cone_holder != null
		and cone_holder.find_child("Intake_Fan_Rotor", true, false) != null
		and cone_holder.find_child("Open_Fan_Cover", true, false) != null
		and cone_holder.find_child("Open_Front_Grille", true, false) != null,
		"Heat Bellows (cone) attaches open rear fan cover, intake fan rotor, and open front heating-coil grille")
	expect(emitted_stages.size() >= 3,
		"WeaponRepair.stage_changed signal emits on tool setup and tool switching")
	standalone_repair.queue_free()
	await frames()

	# 2. Arena TimeCore, ReplayHistory, EmergencyRewind, and Native Held Space Wiring
	var arena: Node3D = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	arena.director.clear()
	arena.history.clear()
	arena.history.validate_snapshots = true
	arena.history.seed_checkpoint(arena.capture_state())

	var gear: RefCounted = arena.equipment
	var weapons: Node3D = arena.weapons
	var player: CharacterBody3D = arena.player
	var tc: TimeController = arena.time_controller
	var er: EmergencyRewind = arena.emergency_rewind
	var hist: ReplayHistory = arena.history
	var scenes: Node = root.get_node("SceneManager")
	var state: Node = root.get_node("GameState")

	expect(tc is TimeController and er is EmergencyRewind and hist is ReplayHistory,
		"Arena exposes typed time_controller, emergency_rewind, and history")
	expect(hist.has_checkpoint and hist.rejected_count == 0,
		"Arena seeds room-start checkpoint into ReplayHistory with valid value-only payload")
	expect(InputMap.has_action(&"slow_time") and not InputMap.action_get_events(&"slow_time").is_empty(),
		"Arena registers one bound slow_time InputMap action for Space")
	expect(weapons.available_tools == [1, 2, 3],
		"Arena initializes three weapons (1..3) with no fourth clock slot")

	# Key 4 is ignored and never selects a 4th tool
	key(KEY_4, true)
	key(KEY_4, false)
	await frames()
	expect(weapons.selected_tool == 1, "Key 4 is ignored in 3-weapon arena")

	# Native held Space slows immediately without re-arm/release-required delay
	var start_meter: float = tc.meter
	key(KEY_SPACE, true)
	arena._physics_process(0.2)
	expect(tc.slow_requested and tc.slow_active and is_equal_approx(tc.world_scale, tc.settings.slow_scale) and tc.meter < start_meter,
		"Holding Space immediately activates slow_requested and scales world_delta")
	key(KEY_SPACE, false)
	arena._physics_process(0.1)
	expect(not tc.slow_requested and not tc.slow_active and is_equal_approx(tc.world_scale, 1.0),
		"Releasing Space immediately restores normal world_scale")

	# First fresh Space input right after popup close or reset works immediately without extra release/repress
	scenes.push_popup(&"Settings")
	await frames()
	scenes.close_popup(&"Settings")
	await frames()
	key(KEY_SPACE, true)
	arena._physics_process(0.1)
	expect(tc.slow_requested and tc.slow_active and is_equal_approx(tc.world_scale, tc.settings.slow_scale),
		"First fresh Space press after popup close works immediately without extra release/repress")
	key(KEY_SPACE, false)
	arena._physics_process(0.1)

	# Voluntary slow drain to 0 stops slow without triggering emergency rewind or spending a charge
	var charges_before_drain: int = tc.charges_remaining
	tc.begin_attempt()
	key(KEY_SPACE, true)
	for _i in range(50):
		arena._physics_process(0.25)
	expect(is_equal_approx(tc.meter, 0.0) and not tc.slow_active
		and not tc.emergency_active and not er.active and tc.charges_remaining == charges_before_drain,
		"Voluntary slow drain to 0.0 stops slow without triggering emergency or spending a charge")
	key(KEY_SPACE, false)
	tc.begin_attempt()

	# 3. Smart Repair Target (E), Auto-Advance on Completion, and Auto-Close When All Owned Tools Are Full
	gear.reset_state()
	var all_three: Array[int] = [1, 2, 3]
	weapons.set_loadout(all_three, 1)
	expect(gear.is_full(&"ring") and gear.is_full(&"beam") and gear.is_full(&"cone"),
		"All 3 weapons start at 100% condition")

	# Pressing E when all owned tools are full does NOT open a lingering Ready screen
	key(KEY_E, true)
	key(KEY_E, false)
	await frames()
	expect(not scenes.has_popup(&"Repair"),
		"Pressing E when all owned tools are full does not open a lingering Ready screen")

	# Damage Beam to 50% condition and Cone to 25% condition while Ring (equipped = 1) is 100% full
	gear.spend(&"beam", gear.capacity(&"beam") * 0.50) # 50% condition
	gear.spend(&"cone", gear.capacity(&"cone") * 0.75) # 25% condition (most damaged!)
	weapons.select_tool(1) # Ring is equipped, but full!

	key(KEY_E, true)
	key(KEY_E, false)
	await frames()
	var panel: Control = arena._active_repair_panel()
	expect(scenes.has_popup(&"Repair") and panel != null and panel.tool == &"cone" and weapons.selected_tool == 3,
		"When equipped tool is full, E opens Repair targeting the most damaged owned weapon (cone at 25%)")
	expect(arena.status_hud.visible,
		"StatusHUD remains visible during repair so time meter and charges stay readable")

	# If equipped tool IS damaged, E targets the equipped tool even if another tool has lower condition
	key(KEY_E, true)
	key(KEY_E, false)
	await frames()
	expect(not scenes.has_popup(&"Repair"), "Second E press toggles Repair closed")
	weapons.select_tool(2) # Equip Beam (50% condition, while Cone is 25% condition)
	key(KEY_E, true)
	key(KEY_E, false)
	await frames()
	panel = arena._active_repair_panel()
	expect(scenes.has_popup(&"Repair") and panel != null and panel.tool == &"beam" and weapons.selected_tool == 2,
		"When equipped weapon is damaged (beam at 50%), E targets the equipped weapon")

	# Manual target selection (1..3 and Tab / Shift-Tab) works inside Repair
	key(KEY_TAB, true)
	key(KEY_TAB, false)
	await frames()
	expect(panel.tool == &"cone" and weapons.selected_tool == 3,
		"Tab inside Repair switches to Cone (3)")

	# 4. Atomic Per-Checkpoint Time Cost & Active Gesture Reporting (Idle Panel Recharges!)
	# Spend voluntary meter down to 2.0 (< repair_cost_per_checkpoint of 6.0)
	tc.begin_attempt()
	tc.try_spend(tc.capacity - 2.0)
	var low_meter: float = tc.meter
	expect(low_meter < tc.settings.repair_cost_per_checkpoint,
		"Time meter drained below single checkpoint cost (%.1f < %.1f)" % [low_meter, tc.settings.repair_cost_per_checkpoint])

	# Attempting to complete Cone's current checkpoint (stage 1 -> Trace) with insufficient time must fail atomically
	var cone_stage_before: int = gear.stage(&"cone")
	var cone_rem_before: float = gear.remaining(&"cone")
	complete_active_operation(panel)
	expect(gear.stage(&"cone") == cone_stage_before and is_equal_approx(gear.remaining(&"cone"), cone_rem_before)
		and is_equal_approx(tc.meter, low_meter) and panel.feedback.text.contains("Not enough time"),
		"Insufficient time prevents checkpoint completion atomically without spending time or advancing stage")

	# While gesture is actively dragging, repair_gesture_active is true and blocks recharge
	mouse_button(panel, panel.route[0], true)
	mouse_motion(panel, panel.route[1], true)
	expect(panel.dragging and tc.repair_gesture_active,
		"Active repair drag reports repair_gesture_active == true to TimeController")
	var meter_during_drag: float = tc.meter
	arena._physics_process(0.5)
	expect(is_equal_approx(tc.meter, meter_during_drag),
		"Active repair gesture suppresses time meter recharge while dragging")

	# Releasing/stopping the gesture sets repair_gesture_active == false while panel stays open, allowing recharge!
	mouse_button(panel, panel.route[0], false)
	expect(not panel.dragging and not tc.repair_gesture_active and scenes.has_popup(&"Repair"),
		"Idle open repair panel sets repair_gesture_active == false")
	arena._physics_process(1.0)
	expect(tc.meter > meter_during_drag + 5.0 and tc.meter >= tc.settings.repair_cost_per_checkpoint,
		"Idle open repair panel permits time meter recharge so player is never stranded at zero time")

	# Now complete Cone's remaining checkpoints with plenty of time -> verify atomic spend and auto-advance to Beam!
	tc.begin_attempt()
	var meter_before_step: float = tc.meter
	complete_active_operation(panel) # Cone stage 1 -> stage 2 (Trace)
	expect(gear.stage(&"cone") == 2 and is_equal_approx(tc.meter, meter_before_step - tc.settings.repair_cost_per_checkpoint),
		"Completing one repair checkpoint spends repair_cost_per_checkpoint (%.1f) atomically" % tc.settings.repair_cost_per_checkpoint)

	# Finish Cone (stage 2 -> 4 via Connect pairs A and B) -> must automatically advance to damaged Beam!
	tc.begin_attempt()
	complete_active_operation(panel)
	await frames()
	expect(gear.is_full(&"cone") and scenes.has_popup(&"Repair") and panel.tool == &"beam" and weapons.selected_tool == 2,
		"Finishing Cone automatically advances Repair to the remaining damaged weapon (Beam)")

	# Finish Beam (stage 2 -> 4 via Bellows Trace) -> all owned tools (Ring, Beam, Cone) are now full -> must auto-close!
	tc.begin_attempt()
	complete_active_operation(panel)
	await frames()
	expect(gear.is_full(&"beam") and gear.is_full(&"ring") and gear.is_full(&"cone") and not scenes.has_popup(&"Repair") and gear.repairing == &"",
		"Finishing the last damaged owned weapon automatically closes Repair with no lingering Ready screen")

	# 5. Forgiving Bidirectional Spin & WASD Movement During Repair Across All 3 Weapons
	for idx in range(Gestures.TOOL_ORDER.size()):
		var tool_id: StringName = Gestures.TOOL_ORDER[idx]
		gear.reset_state()
		gear.spend(tool_id, gear.capacity(tool_id))
		tc.begin_attempt()
		weapons.select_tool(idx + 1)
		key(KEY_E, true)
		key(KEY_E, false)
		await frames()
		panel = arena._active_repair_panel()
		expect(panel != null and panel.tool == tool_id and panel.active_kind == &"spin",
			"%s opens on Spin operation" % String(tool_id))
		if panel == null:
			break

		var center: Vector2 = panel.active_op["center"]
		var radius: float = float(panel.active_op["radius"])
		var ccw_oval: Array[Vector2] = [center + Vector2(3.0, -2.0)]
		var steps := 24
		for s in range(steps + 1):
			var ang: float = 2.4 - (Gestures.SPIN_FULL_RADIANS * 1.12) * (float(s) / float(steps))
			var rx: float = radius * 1.65 + sin(float(s) * 0.9) * 8.0
			var ry: float = radius * 0.62 + cos(float(s) * 0.7) * 6.0
			var shifted_center: Vector2 = center + Vector2(10.0, -7.0)
			ccw_oval.append(shifted_center + Vector2(cos(ang) * rx, sin(ang) * ry))

		player.position = Vector3.ZERO
		Input.action_press("move_right")
		mouse_button(panel, ccw_oval[0], true)
		for pt_idx in range(1, ccw_oval.size()):
			arena._physics_process(1.0 / 60.0)
			mouse_motion(panel, ccw_oval[pt_idx], true)
		mouse_button(panel, ccw_oval[-1], false)
		Input.action_release("move_right")
		expect(gear.stage(tool_id) == 1 and player.position.x > 0.2 and not _weapons_attacking(weapons),
			"%s completes forgiving CCW oval Spin while moving with WASD and without weapon leak" % String(tool_id))
		key(KEY_E, true)
		key(KEY_E, false)
		await frames()

	# 6. Emergency Rewind Input (Wheel to Scrub, Click / Enter to Confirm) & World Snapshot Exclusions
	arena.reset_arena()
	arena.director.clear()
	var partial_owned: Array[int] = [2, 3]
	weapons.set_loadout(partial_owned, 2)
	player.position = Vector3(-4.0, 0.55, 2.0)
	arena.history.clear()
	arena.history.seed_checkpoint(arena.capture_state())
	for step_i in range(1, 25):
		player.position = Vector3(-4.0 + float(step_i) * 0.3, 0.55, 2.0)
		arena.history.record(0.1, arena.capture_state)
	var pos_at_present: Vector3 = player.position

	# Open repair on damaged Beam, then trigger hit-driven depletion -> must close repair and enter emergency rewind!
	gear.spend(&"beam", 4.0)
	key(KEY_E, true)
	key(KEY_E, false)
	await frames()
	expect(scenes.has_popup(&"Repair"), "Repair open before lethal hit")

	var charges_before_hit: int = tc.charges_remaining
	tc.apply_hit(tc.capacity)
	await frames()
	expect(tc.emergency_active and er.active and tc.charges_remaining == charges_before_hit - 1 and not scenes.has_popup(&"Repair"),
		"Hit-driven depletion spends 1 charge, activates EmergencyRewind, and closes open Repair popup")
	expect(er.selected_index == 0 and player.position.distance_to(pos_at_present) < 0.05,
		"EmergencyRewind starts at choice 0 (NOW) with recorded history choices available")

	# Mouse wheel DOWN steps toward older snapshots (+1); mouse wheel UP steps toward newer snapshots (-1)
	raw_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true)
	raw_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, false)
	raw_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true)
	raw_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, false)
	arena.scrub_view.step(1.0)
	expect(er.selected_index == 2 and player.position.x < pos_at_present.x - 0.1,
		"Mouse wheel down steps emergency selection into the past and previews older world state")
	raw_mouse_button(MOUSE_BUTTON_WHEEL_UP, true)
	raw_mouse_button(MOUSE_BUTTON_WHEEL_UP, false)
	arena.scrub_view.step(1.0)
	expect(er.selected_index == 1,
		"Mouse wheel up steps emergency selection toward newer snapshot")

	# Confirm emergency rewind with Left Mouse Button without leaking into weapon attack or refunding charge
	raw_mouse_button(MOUSE_BUTTON_LEFT, true)
	raw_mouse_button(MOUSE_BUTTON_LEFT, false)
	await frames()
	expect(not er.active and not tc.emergency_active
		and tc.charges_remaining == charges_before_hit - 1
		and tc.meter >= tc.settings.recovery_floor - 0.01
		and tc.protected
		and weapons.available_tools == partial_owned
		and not _weapons_attacking(weapons),
		"Left-click confirms emergency rewind, restores recovery floor + grace, preserves charges/owned tools, and does not leak into weapon fire")

	# Advance past recovery grace, trigger a second emergency, and confirm with Enter key
	arena._physics_process(tc.settings.recovery_grace_seconds + 0.1)
	for step_i in range(1, 10):
		player.position = Vector3(float(step_i) * 0.4, 0.55, 0.0)
		arena.history.record(0.1, arena.capture_state)
	tc.apply_hit(tc.capacity * 2.0)
	await frames()
	expect(er.active and tc.charges_remaining == charges_before_hit - 2, "Second hit-driven depletion enters emergency rewind")
	raw_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true)
	raw_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, false)
	key(KEY_ENTER, true)
	key(KEY_ENTER, false)
	await frames()
	expect(not er.active and not tc.emergency_active and tc.charges_remaining == charges_before_hit - 2,
		"Enter key confirms emergency rewind")

	# Focus loss cleans up slow, repair, and pauses game safely
	arena._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames()
	expect(not tc.slow_requested and not tc.repair_gesture_active and state.state == state.State.PAUSED,
		"Focus loss clears slow_requested, repair_gesture_active, and pauses game")
	state.start_game()
	await frames()

	arena.queue_free()
	await frames()
	await create_timer(0.10).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
