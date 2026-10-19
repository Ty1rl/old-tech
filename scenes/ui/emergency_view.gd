class_name EmergencyRewindView
extends Control
## Compact read-only scrub bar. Arena owns wheel/click/Enter and calls
## EmergencyRewind directly so confirmation is consumed before weapon input.

const UI = preload("res://scenes/ui/ui_style.gd")
const ToolStyle = preload("res://scenes/prototype/tool_style.gd")

@onready var panel: PanelContainer = %Panel
@onready var choice: Label = %Choice
@onready var charges: Label = %Charges
@onready var timeline: Control = %Timeline
@onready var instructions: Label = %Instructions

var emergency_rewind: EmergencyRewind
var lesson_mode := false


func _ready() -> void:
	_apply_panel_style()
	visible = is_instance_valid(emergency_rewind) and emergency_rewind.active
	timeline.draw.connect(_draw_timeline)
	resized.connect(_fit)
	get_window().size_changed.connect(_fit)
	_fit.call_deferred()
	_refresh()


func _apply_panel_style() -> void:
	if panel == null:
		return
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.07, 0.09, 0.9)
	box.border_color = Color(ToolStyle.CLOCK, 0.55)
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 6
	box.content_margin_bottom = 7
	panel.add_theme_stylebox_override("panel", box)


func set_lesson_mode(active: bool) -> void:
	if lesson_mode == active:
		return
	lesson_mode = active
	if is_node_ready():
		_refresh()


func bind_emergency_rewind(session: EmergencyRewind) -> void:
	if is_instance_valid(emergency_rewind):
		emergency_rewind.started.disconnect(_started)
		emergency_rewind.selection_changed.disconnect(_selection_changed)
		emergency_rewind.ended.disconnect(_ended)
	emergency_rewind = session
	if is_instance_valid(session):
		session.started.connect(_started)
		session.selection_changed.connect(_selection_changed)
		session.ended.connect(_ended)
	if is_node_ready():
		_refresh()


func _started(_count: int) -> void:
	_refresh()


func _selection_changed(_index: int, _age: float, _state: Dictionary) -> void:
	_refresh()


func _ended() -> void:
	_refresh()


func _refresh() -> void:
	visible = is_instance_valid(emergency_rewind) and emergency_rewind.active
	if not visible:
		return
	var age := emergency_rewind.choice_age(emergency_rewind.selected_index)
	choice.text = "NOW" if age == 0 else "ROOM CHECKPOINT" if age == EmergencyRewind.CHECKPOINT_AGE else "−%.2fs" % age
	var controller := emergency_rewind.time_controller
	if lesson_mode:
		charges.text = "Choose an earlier safe moment · 3 / 3 charges kept"
		instructions.text = "Scroll earlier · Enter or click to recover"
	else:
		charges.text = "1 rewind spent · %d left" % controller.charges_remaining if is_instance_valid(controller) else "Choose a recovery moment"
		instructions.text = "Scroll to choose · Enter or click to recover"
	if emergency_rewind.choice_count == 1:
		choice.text += " · no earlier moments"
	timeline.queue_redraw()


func _draw_timeline() -> void:
	if not is_instance_valid(emergency_rewind) or not emergency_rewind.active:
		return
	var color := ToolStyle.CLOCK
	var left := Vector2(8.0, timeline.size.y * 0.5)
	var right := Vector2(maxf(left.x + 1.0, timeline.size.x - 8.0), left.y)
	timeline.draw_line(left, right, Color(color, 0.32), 2.0, true)
	var count := emergency_rewind.choice_count
	# Bound rendering work for the 240-snapshot buffer; selection remains exact.
	var stride := maxi(1, ceili(float(count) / 36.0))
	for i in range(0, count, stride):
		var at := right.lerp(left, float(i) / maxf(1.0, float(count - 1)))
		timeline.draw_line(at + Vector2(0.0, -2.5), at + Vector2(0.0, 2.5), Color(color, 0.42), 1.0, true)
	var cursor := right.lerp(left, float(emergency_rewind.selected_index) / maxf(1.0, float(count - 1)))
	timeline.draw_circle(cursor, 4.5, color)
	timeline.draw_circle(cursor, 2.0, UI.PAPER)


func _exit_tree() -> void:
	if get_window().size_changed.is_connected(_fit):
		get_window().size_changed.disconnect(_fit)


func _fit() -> void:
	if not is_node_ready() or is_queued_for_deletion():
		return
	var win_size := get_window().size if get_window() != null else Vector2i(1280, 800)
	var raw_factor := UI.scale_for(self)
	var factor := 1.0 if win_size.y <= 480 or size.y <= 480.0 else minf(raw_factor, 1.15)
	var avail_w := maxf(200.0, size.x - 40.0)
	var target_w := clampf(330.0 * factor, 200.0, minf(400.0, avail_w))
	if panel != null:
		panel.custom_minimum_size = Vector2(target_w, 0.0)
	if timeline != null:
		timeline.custom_minimum_size = Vector2(maxf(160.0, target_w - 32.0), roundf(11.0 * factor))
	for text in find_children("*", "Label", true, false):
		if text.has_meta("base_font_size"):
			text.add_theme_font_size_override("font_size", roundi(float(text.get_meta("base_font_size")) * factor))
	timeline.queue_redraw()
