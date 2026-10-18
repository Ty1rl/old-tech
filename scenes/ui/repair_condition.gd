class_name RepairConditionView
extends Control
## A read-only view of actual equipment condition, including rewound repairs.
const Segments = preload("res://scenes/ui/condition_segments.gd")
const ToolStyle = preload("res://scenes/prototype/tool_style.gd")
const COLORS := {&"ring": ToolStyle.RING, &"beam": ToolStyle.BEAM, &"cone": ToolStyle.CONE}
const NAMES := {&"ring": "Cutter", &"beam": "Flash", &"cone": "Bellows"}
@onready var gauge: Control = %Gauge
@onready var condition_label: Label = %ConditionLabel
@onready var progress: Label = %Progress
var equipment: WeaponEquipment
var tool: StringName = &""
var _flash := 0.0
var _display := ""

func _ready() -> void:
	gauge.draw.connect(_draw_gauge)
	gauge.resized.connect(gauge.queue_redraw)
	_refresh()

func bind_equipment(value: WeaponEquipment, selected_tool: StringName) -> void:
	if equipment != null and equipment.repaired.is_connected(_on_repaired):
		equipment.repaired.disconnect(_on_repaired)
	equipment = value
	tool = selected_tool
	_flash = 0
	_display = ""
	if equipment != null: equipment.repaired.connect(_on_repaired)
	if is_node_ready(): _refresh()

func segment_count() -> int:
	return equipment.repair_steps if equipment != null else 0

func filled_segments() -> int:
	if equipment == null or tool not in WeaponEquipment.TOOLS: return 0
	return clampi(floori(equipment.condition(tool) * segment_count() + .000001), 0, segment_count())

func _on_repaired(repaired_tool: StringName, restored: float) -> void:
	if repaired_tool != tool or restored <= 0: return
	_flash = 1
	_refresh()

func _process(delta: float) -> void:
	var flashing := _flash > 0
	_flash = maxf(0, _flash - delta * 2.5)
	_refresh()
	if flashing: gauge.queue_redraw()

func _refresh() -> void:
	var valid := equipment != null and tool in WeaponEquipment.TOOLS
	var next := "%s:%s:%d" % [tool, str(equipment.condition(tool)), segment_count()] if valid else "Choose a weapon"
	if next == _display: return
	_display = next
	condition_label.text = String(NAMES[tool]) + " condition" if valid else "Weapon condition"
	progress.text = "%d / %d segments · %.0f%%" % [filled_segments(), segment_count(), equipment.condition(tool) * 100] if valid else "Choose a weapon"
	gauge.queue_redraw()

func _draw_gauge() -> void:
	if equipment == null or tool not in WeaponEquipment.TOOLS: return
	var radius := minf(gauge.size.x * .38, gauge.size.y * .78)
	var center := Vector2(gauge.size.x * .5, gauge.size.y * .87)
	var color: Color = COLORS[tool]
	Segments.draw(gauge, center, radius, -PI + .08, -.08, equipment.condition(tool),
		segment_count(), color.lightened(_flash * .5), Color(color, .16), 8)
	gauge.draw_arc(center, radius + 8, -PI + .08, -.08, 32, Color(color, .8), 1.5, true)
