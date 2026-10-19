extends Control
const UI = preload("res://scenes/ui/ui_style.gd")
@onready var column: VBoxContainer = %Column
@onready var heading: Label = %Heading
@onready var margin: MarginContainer = %Margin
@onready var footer: Label = %Footer
@onready var play: Button = %PlayButton
var buttons: Array[Button] = []
var _layout_size := Vector2.ZERO
var _layout_factor := 0.0

func _ready() -> void:
	AudioManager.set_music_context(&"menu")
	for node in column.get_children():
		if node is Button:
			buttons.append(node)
			node.draw.connect(_draw_selection.bind(node))
			for event in [node.focus_entered, node.focus_exited, node.mouse_entered, node.mouse_exited]:
				event.connect(node.queue_redraw)
	resized.connect(_fit)
	get_window().size_changed.connect(_fit)
	_fit()
	UI.focus_on_open(self, play)

func _exit_tree() -> void:
	if get_window().size_changed.is_connected(_fit): get_window().size_changed.disconnect(_fit)

func _fit() -> void:
	if not is_instance_valid(column): return
	var factor := UI.scale_for(self)
	if size == _layout_size and is_equal_approx(factor, _layout_factor): return
	_layout_size = size
	_layout_factor = factor
	var compact := size.y < 480 * factor
	var left := roundi(clampf(size.x * .05, 24 * factor, 76 * factor))
	var column_width := minf(size.x - left * 2, maxf(300 * factor, size.x * .47))
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_right", maxi(left, roundi(size.x - left - column_width)))
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, roundi((16 if compact else 32) * factor))
	column.add_theme_constant_override("separation", roundi((4 if compact else 10) * factor))
	for text: Label in column.find_children("*", "Label", true, false):
		var font_size := (12 if compact else 14) if text == footer else (14 if compact else 19)
		text.add_theme_font_size_override("font_size", roundi(font_size * factor))
	var title_font := heading.get_theme_font("font")
	var line_width := title_font.get_string_size("SOME ASSEMBLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x
	var title_size := minf(size.y * (.12 if compact else .125), column_width * 100 / maxf(1, line_width))
	heading.add_theme_font_size_override("font_size", roundi(clampf(title_size, 30 * factor, 108 * factor)))
	heading.add_theme_constant_override("line_spacing", roundi(-title_size * .22))
	for button in buttons:
		var text_size := 18 if compact else 25
		if button == play: text_size = 23 if compact else 32
		button.add_theme_font_size_override("font_size", roundi(text_size * factor))
		button.queue_redraw()

func _draw_selection(button: Button) -> void:
	if not button.has_focus() and not button.is_hovered(): return
	var y := button.size.y * .5
	button.draw_colored_polygon(PackedVector2Array([Vector2(5, y - 5), Vector2(5, y + 5), Vector2(13, y)]), UI.ACCENT)
	var font := button.get_theme_font("font")
	var text_width := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
	var inset := button.get_theme_stylebox("normal").get_content_margin(SIDE_LEFT)
	button.draw_line(Vector2(inset, button.size.y - 3), Vector2(minf(button.size.x - 8, inset + text_width), button.size.y - 3), UI.ACCENT, 2, true)


func _on_play_button_pressed() -> void: SceneManager.push_popup(&"NewGame")
func _on_settings_button_pressed() -> void: SceneManager.push_popup(&"Settings")
func _on_exit_button_pressed() -> void: AudioManager.request_quit()
