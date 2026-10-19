class_name RepairConditionView
extends Control
## Read-only, transparent HUD-sector overlay. Parent supplies the model region;
## all active part targets remain inside that region, away from the outer arc.
const Segments = preload("res://scenes/ui/condition_segments.gd")
const Style = preload("res://scenes/prototype/tool_style.gd")
@export_range(.05, 1) var opacity := .55
@export var stroke_width := 9.0
var equipment: WeaponEquipment
var tool: StringName = &""
var _flash := 0.0
var _display := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func bind_equipment(value: WeaponEquipment, selected_tool: StringName) -> void:
	if equipment == value and tool == selected_tool: return
	if equipment != null and equipment.repaired.is_connected(_on_repaired):
		equipment.repaired.disconnect(_on_repaired)
	equipment = value
	tool = selected_tool
	_flash = 0
	_display = ""
	if equipment != null: equipment.repaired.connect(_on_repaired)
	queue_redraw()

func segment_count() -> int:
	return equipment.repair_steps if equipment != null else 0

func filled_segments() -> int:
	if equipment == null or tool not in WeaponEquipment.TOOLS: return 0
	return clampi(floori(equipment.condition(tool) * segment_count() + .000001), 0, segment_count())

func _on_repaired(repaired_tool: StringName, restored: float) -> void:
	if repaired_tool == tool and restored > 0:
		_flash = .28
		queue_redraw()

func _process(delta: float) -> void:
	var flashing := _flash > 0
	_flash = maxf(0, _flash - delta)
	var next := "%s:%s:%d" % [tool, equipment.condition(tool), segment_count()] if equipment != null else ""
	if next != _display or flashing:
		_display = next
		queue_redraw()

func arc_geometry() -> Dictionary:
	# Same one-third upper-circle sector as TimeStatusHUD. The circle contains
	# the entire supplied rectangle, so it never crosses an active part/label.
	var index := WeaponEquipment.TOOLS.find(tool)
	return {"center": size * .5, "radius": size.length() * .5 + 12,
		"start": -PI + index * PI / 3 + .08, "end": -PI + (index + 1) * PI / 3 - .08}

func _draw() -> void:
	if equipment == null or tool not in WeaponEquipment.TOOLS: return
	var arc := arc_geometry()
	var color := Style.color_for(tool)
	Segments.draw(self, arc.center, arc.radius, arc.start, arc.end,
		equipment.condition(tool), segment_count(), Color(color, opacity),
		Color(color, opacity * .2), stroke_width)
	draw_arc(arc.center, arc.radius + 8, arc.start, arc.end, 32, Color(color, opacity * .8), 1.5, true)
	if _flash > 0:
		# Brief neutral confirmation; equipment identity never turns green.
		draw_arc(arc.center, arc.radius + 11, arc.start, arc.end, 32,
			Color(Style.REPAIR_GUIDE, _flash / .28 * .65), 2, true)
