class_name EmergencyRewindView
extends Control
## Read-only view. Arena owns wheel/click/Enter and calls EmergencyRewind directly.
## No input callbacks here: confirmation must be consumed before weapon input.
const UI = preload("res://scenes/ui/ui_style.gd")
@onready var choice: Label = %Choice
@onready var charges: Label = %Charges
@onready var timeline: Control = %Timeline
var emergency_rewind: EmergencyRewind

func _ready() -> void:
	visible = is_instance_valid(emergency_rewind) and emergency_rewind.active
	timeline.draw.connect(_draw_timeline)
	resized.connect(_fit)
	get_window().size_changed.connect(_fit)
	_fit.call_deferred()
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
	if is_node_ready(): _refresh()

func _started(_count: int) -> void: _refresh()
func _selection_changed(_index: int, _age: float, _state: Dictionary) -> void: _refresh()
func _ended() -> void: _refresh()

func _refresh() -> void:
	visible = is_instance_valid(emergency_rewind) and emergency_rewind.active
	if not visible: return
	var age := emergency_rewind.choice_age(emergency_rewind.selected_index)
	choice.text = "NOW · recover here" if age == 0 else "ROOM CHECKPOINT" if age == EmergencyRewind.CHECKPOINT_AGE else "−%.2f seconds" % age
	var controller := emergency_rewind.time_controller
	charges.text = "1 rewind spent · %d left this room attempt" % controller.charges_remaining if is_instance_valid(controller) else "Choose a recovery moment"
	if emergency_rewind.choice_count == 1: choice.text += " · no earlier moments recorded"
	timeline.queue_redraw()

func _draw_timeline() -> void:
	if not is_instance_valid(emergency_rewind) or not emergency_rewind.active: return
	var color := Color("bf92e8")
	var left := Vector2(8, timeline.size.y * .5)
	var right := Vector2(timeline.size.x - 8, left.y)
	timeline.draw_line(left, right, Color(color, .3), 3, true)
	var count := emergency_rewind.choice_count
	# Bound rendering work for the 240-snapshot buffer; selection remains exact.
	var stride := maxi(1, ceili(float(count) / 48))
	for i in range(0, count, stride):
		var at := right.lerp(left, float(i) / maxf(1, count - 1))
		timeline.draw_line(at + Vector2(0, -3), at + Vector2(0, 3), Color(color, .4), 1, true)
	var cursor := right.lerp(left, float(emergency_rewind.selected_index) / maxf(1, count - 1))
	timeline.draw_circle(cursor, 6, color)

func _exit_tree() -> void:
	if get_window().size_changed.is_connected(_fit): get_window().size_changed.disconnect(_fit)

func _fit() -> void:
	if not is_node_ready() or is_queued_for_deletion(): return
	var factor := UI.scale_for(self)
	for text in find_children("*", "Label", true, false):
		if text.has_meta("base_font_size"):
			text.add_theme_font_size_override("font_size", roundi(text.get_meta("base_font_size") * factor))
	timeline.queue_redraw()
