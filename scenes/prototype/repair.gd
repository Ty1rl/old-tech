extends Control

# Round C: jam-2 owns this popup and its scene/checks.
var equipment: RefCounted
var tool: StringName = &"ring"
var _session: int = -1


func setup(params: Dictionary) -> void:
	equipment = params.equipment
	tool = params.get("tool", &"ring")
	_session = equipment.begin_repair(tool)


func _ready() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(120, 220)
	panel.custom_minimum_size = Vector2(500, 180)
	add_child(panel)
	var label := Label.new()
	label.text = "Repair %s — puzzle pending Round C\nWASD still moves. E or Escape closes." % tool
	panel.add_child(label)
	var button := Button.new()
	button.text = "Close"
	button.pressed.connect(queue_free)
	panel.add_child(button)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_E, KEY_ESCAPE]:
			get_viewport().set_input_as_handled()
			queue_free()


func _exit_tree() -> void:
	if equipment != null:
		equipment.end_repair(_session)
