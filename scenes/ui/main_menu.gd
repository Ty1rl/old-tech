extends Control
const UI = preload("res://scenes/ui/ui_style.gd")
@onready var column: VBoxContainer = %Column
@onready var heading: Label = %Heading
@onready var margin: MarginContainer = %Margin
@onready var footer: Label = %Footer
@onready var play: Button = %PlayButton
@onready var developer_button: Button = %DeveloperButton
var buttons: Array[Button] = []
var _layout_size := Vector2.ZERO
var _layout_factor := 0.0

func _ready() -> void:
	developer_button.visible = SceneManager.developer_tools
	for node in column.get_children():
		if node is Button:
			buttons.append(node)
			node.draw.connect(_draw_selection.bind(node))
	resized.connect(_fit)
	get_window().size_changed.connect(_fit)
	_fit()
	UI.focus_on_open(self, play)

func _exit_tree() -> void:
	if get_window().size_changed.is_connected(_fit): get_window().size_changed.disconnect(_fit)

func _fit() -> void:
	if not is_instance_valid(column): return
	var factor := UI.scale_for(self)
	if size == _layout_size and is_equal_approx(factor,_layout_factor): return
	_layout_size = size; _layout_factor = factor
	for side in ["left","right"]: margin.add_theme_constant_override("margin_"+side,roundi(42*factor))
	for side in ["top","bottom"]: margin.add_theme_constant_override("margin_"+side,roundi(26*factor))
	column.add_theme_constant_override("separation",roundi(10*factor))
	for text in column.find_children("*","Label",true,false):
		if text.has_meta("base_font_size"):
			text.add_theme_font_size_override("font_size",roundi(text.get_meta("base_font_size")*factor))
	# The long title can wrap inside a narrow window; the controls can scroll.
	for button in buttons:
		button.add_theme_font_size_override("font_size",roundi(button.get_meta("base_button_font")*factor))

func _draw_selection(button: Button) -> void:
	if button.has_focus():
		var y := button.size.y * .5
		button.draw_colored_polygon(PackedVector2Array([Vector2(6,y-5),Vector2(6,y+5),Vector2(13,y)]), UI.ACCENT)

func _on_developer() -> void: SceneManager.push_popup(&"Developer")

func _unhandled_input(event: InputEvent) -> void:
	if SceneManager.developer_tools and event is InputEventKey and event.pressed and event.physical_keycode == KEY_F10:
		SceneManager.push_popup(&"Developer")

func _on_play_button_pressed() -> void: SceneManager.push_popup(&"NewGame")
func _on_settings_button_pressed() -> void: SceneManager.push_popup(&"Settings")
func _on_exit_button_pressed() -> void: get_tree().quit()
