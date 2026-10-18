extends Control
const UI = preload("res://scenes/ui/ui_style.gd")
const Backdrop = preload("res://scenes/ui/menu_backdrop.gd")

func _ready() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.skin()
	add_child(Backdrop.new())
	var shade := Control.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.draw.connect(func():
		for i in range(32):
			var x := size.x*float(i)/32
			shade.draw_rect(Rect2(x,0,size.x/32+1,size.y),Color(0.02,0.018,0.014,lerpf(.96,.18,float(i)/31))))
	shade.resized.connect(shade.queue_redraw)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right"]: margin.add_theme_constant_override("margin_"+side,48)
	for side in ["top","bottom"]: margin.add_theme_constant_override("margin_"+side,32)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",15)
	margin.add_child(column)
	column.owner = self
	UI.label(column,"AFTER HOURS / THE MUSEUM",14).modulate = UI.ACCENT
	var top_space := Control.new(); top_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(top_space)
	var heading := UI.label(column,"SOME ASSEMBLY\nREQUIRED",48)
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	UI.label(column,"A museum of unfinished things.",20).modulate = UI.MUTED
	var gap := Control.new();gap.custom_minimum_size.y=20;column.add_child(gap)
	var play := _menu_button(column,"NEW GAME",_on_play_button_pressed,"PlayButton")
	_menu_button(column,"SETTINGS",_on_settings_button_pressed,"SettingsButton")
	_menu_button(column,"QUIT",_on_exit_button_pressed)
	if SceneManager.developer_tools:
		var debug := _menu_button(column,"Encounter select · F10",func(): SceneManager.push_popup(&"Developer"))
		debug.add_theme_font_size_override("font_size",14)
		debug.modulate = UI.MUTED
	var bottom_space := Control.new(); bottom_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(bottom_space)
	UI.label(column,"WASD Move    Mouse Aim    Space Time",14).modulate = UI.MUTED
	play.grab_focus.call_deferred()

func _menu_button(column: Node, text: String, action: Callable, node_name: String = "") -> Button:
	var button := UI.button(column,text,action,node_name)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size",24)
	for state in ["normal","hover","pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0,0,0,0)
		style.content_margin_left = 10; style.content_margin_right = 18
		style.content_margin_top = 7; style.content_margin_bottom = 7
		if state != "normal":
			style.border_color = UI.ACCENT
			style.border_width_left = 3
		button.add_theme_stylebox_override(state,style)
	button.add_theme_color_override("font_focus_color",UI.ACCENT)
	button.add_theme_color_override("font_hover_color",UI.ACCENT)
	return button

func _unhandled_input(event: InputEvent) -> void:
	if SceneManager.developer_tools and event is InputEventKey and event.pressed and event.physical_keycode == KEY_F10:
		SceneManager.push_popup(&"Developer")

func _on_play_button_pressed() -> void: SceneManager.start_play()
func _on_settings_button_pressed() -> void: SceneManager.push_popup(&"Settings")
func _on_exit_button_pressed() -> void: get_tree().quit()
