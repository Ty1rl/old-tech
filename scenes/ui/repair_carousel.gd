class_name RepairCarouselView
extends Control
## Display/optional neighbor clicks only. Repair owns the selected model and input.
signal tool_selected(tool: StringName)
@onready var condition: RepairConditionView = %SelectedCondition
@onready var left: RepairSidePreview = %Left
@onready var right: RepairSidePreview = %Right
var equipment: WeaponEquipment
var selected: StringName = &""
var owned_slots: Array[int] = []
var _region := Rect2()
var _slide: Tween
var _layout_transform := Transform2D.IDENTITY

func _ready() -> void:
	left.hit_area.pressed.connect(_choose.bind(left))
	right.hit_area.pressed.connect(_choose.bind(right))
	resized.connect(_layout)
	_sync(false)

func bind_equipment(gear: WeaponEquipment, selected_tool: StringName, slots: Array[int]) -> void:
	var owned: Array[int] = []
	for slot in slots:
		if slot in [1, 2, 3] and slot not in owned: owned.append(slot)
	if equipment == gear and selected == selected_tool and owned_slots == owned: return
	var switched := selected != selected_tool
	equipment = gear
	selected = selected_tool
	owned_slots = owned
	if is_node_ready(): _sync(switched)

func set_model_region(rect: Rect2) -> void:
	if _region == rect and _layout_transform == get_global_transform_with_canvas(): return
	_region = rect
	if is_node_ready(): _layout()

func _choose(preview: RepairSidePreview) -> void:
	if preview.visible and equipment != null and preview.tool in WeaponEquipment.TOOLS:
		tool_selected.emit(preview.tool)

func _sync(animate: bool) -> void:
	var index := WeaponEquipment.TOOLS.find(selected)
	var position_in_slots := owned_slots.find(index + 1)
	var valid := equipment != null and position_in_slots >= 0
	condition.bind_equipment(equipment if valid else null, selected if valid else &"")
	left.visible = valid and owned_slots.size() > 1
	right.visible = valid and owned_slots.size() > 2
	if left.visible:
		left.bind_equipment(equipment, WeaponEquipment.TOOLS[owned_slots[posmod(position_in_slots - 1, owned_slots.size())] - 1])
	else:
		left.bind_equipment(null, &"")
		left.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if right.visible:
		right.bind_equipment(equipment, WeaponEquipment.TOOLS[owned_slots[(position_in_slots + 1) % owned_slots.size()] - 1])
	else:
		right.bind_equipment(null, &"")
		right.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_layout()
	if _slide != null: _slide.kill()
	if animate and (left.visible or right.visible):
		_slide = create_tween().set_parallel(true)
		for preview: RepairSidePreview in [left, right]:
			if not preview.visible: continue
			var target := preview.position
			var sign := 1 if preview == left else -1
			preview.position += Vector2(24 * sign, 0)
			preview.rotation = .045 * sign
			_slide.tween_property(preview, "position", target, .18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			_slide.tween_property(preview, "rotation", 0, .18)

func _layout() -> void:
	if not is_node_ready(): return
	if _slide != null:
		_slide.kill()
		_slide = null
	left.rotation = 0
	right.rotation = 0
	condition.visible = equipment != null and _region.has_area() and selected in WeaponEquipment.TOOLS and WeaponEquipment.TOOLS.find(selected) + 1 in owned_slots
	left.visible = condition.visible and owned_slots.size() > 1
	right.visible = condition.visible and owned_slots.size() > 2
	if not _region.has_area():
		left.hide(); right.hide(); return
	_layout_transform = get_global_transform_with_canvas()
	var transform := _layout_transform.affine_inverse()
	var rect := transform * _region
	condition.position = rect.position
	condition.size = rect.size
	# Selected inspection area never moves. Neighbors fit the remaining margins.
	var bounds:Rect2 = transform * get_viewport_rect()
	var radius := rect.size.length() * .5 + 24
	var extent := minf(rect.position.x - bounds.position.x, bounds.end.x - rect.end.x)
	var side := clampf(extent * .75, 70, 180)
	var center := rect.get_center()
	var gap := radius + side * .65
	_fit_neighbor(left, center - Vector2(gap, 0), side, bounds)
	_fit_neighbor(right, center + Vector2(gap, 0), side, bounds)

func _fit_neighbor(preview: RepairSidePreview, center: Vector2, side: float, bounds: Rect2) -> void:
	var minimum := bounds.position + Vector2.ONE * 20
	var maximum := (bounds.end - Vector2.ONE * (side + 20)).max(minimum)
	var corner := (center - Vector2.ONE * side * .5).clamp(minimum, maximum)
	preview.fit(Rect2(corner, Vector2.ONE * side))
