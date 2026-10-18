extends Control
const UI = preload("res://scenes/ui/ui_style.gd")
const Backdrop = preload("res://scenes/ui/menu_backdrop.gd")
var column: VBoxContainer
var heading: Label
var margin: MarginContainer
var buttons: Array[Button] = []
var footer: Label
var _layout_size := Vector2.ZERO
var _layout_factor := 0.0

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
			var x := size.x * float(i) / 32
			shade.draw_rect(Rect2(x,0,size.x/32+1,size.y),Color(0.02,0.018,0.014,lerpf(.96,.18,float(i)/31))))
	shade.resized.connect(shade.queue_redraw)
	add_child(shade)
	margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	margin.add_child(scroll)
	column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	column.owner = self
	UI.label(column,"AFTER HOURS / THE MUSEUM",14).modulate = UI.ACCENT
	var top_space := Control.new()
	top_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(top_space)
	heading = UI.label(column,"SOME ASSEMBLY\nREQUIRED",48)
	UI.label(column,"A museum of unfinished things.",20).modulate = UI.MUTED
	var gap := Control.new(); gap.custom_minimum_size.y = 12; column.add_child(gap)
	var play := _menu_button("NEW GAME",_on_play_button_pressed,"PlayButton")
	_menu_button("SETTINGS",_on_settings_button_pressed,"SettingsButton")
	_menu_button("QUIT",_on_exit_button_pressed)
	if SceneManager.developer_tools:
		var debug := _menu_button("Encounter select · F10",func(): SceneManager.push_popup(&"Developer"))
		debug.set_meta("base_button_font",14)
		debug.modulate = UI.MUTED
	var bottom_space := Control.new()
	bottom_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(bottom_space)
	footer = UI.label(column,"WASD Move · Mouse Aim · E Toggle repair · Space Slow",14)
	footer.modulate = UI.MUTED
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

func _menu_button(text: String, action: Callable, node_name: String = "") -> Button:
	var button := UI.button(column,text,action,node_name)
	buttons.append(button)
	button.set_meta("base_button_font",24)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for state in ["normal","hover","pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0,0,0,0)
		style.content_margin_left = 22; style.content_margin_right = 18
		style.content_margin_top = 7; style.content_margin_bottom = 7
		if state != "normal":
			style.border_color = UI.ACCENT
			style.border_width_left = 2
		button.add_theme_stylebox_override(state,style)
	button.add_theme_color_override("font_focus_color",UI.ACCENT)
	button.add_theme_color_override("font_hover_color",UI.ACCENT)
	button.draw.connect(func():
		if button.has_focus():
			var y := button.size.y * .5
			button.draw_colored_polygon(PackedVector2Array([Vector2(6,y-5),Vector2(6,y+5),Vector2(13,y)]),UI.ACCENT))
	return button

func _unhandled_input(event: InputEvent) -> void:
	if SceneManager.developer_tools and event is InputEventKey and event.pressed and event.physical_keycode == KEY_F10:
		SceneManager.push_popup(&"Developer")

func _on_play_button_pressed() -> void: SceneManager.start_play()
func _on_settings_button_pressed() -> void: SceneManager.push_popup(&"Settings")
func _on_exit_button_pressed() -> void: get_tree().quit()
