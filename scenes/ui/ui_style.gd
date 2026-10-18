extends RefCounted

const INK := Color("111c22")
const PAPER := Color("ece4d2")
const MUTED := Color("a9b5b5")
const ACCENT := Color("cba66c")

static func scale_for(node: Node) -> float:
	var pixels := node.get_window().size.x
	return clampf(node.get_viewport().get_visible_rect().size.x / maxf(1, pixels), 1, 1.5)

static func skin() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 19
	theme.set_color("font_color", "Label", PAPER)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("293a42") if state == "normal" else Color("45545a")
		style.border_color = ACCENT if state != "normal" else Color("53616a")
		style.set_border_width_all(2 if state == "focus" else 1)
		style.set_corner_radius_all(4)
		style.content_margin_top = 12
		style.content_margin_bottom = 12
		style.content_margin_left = 18
		style.content_margin_right = 18
		theme.set_stylebox(state, "Button", style)
		theme.set_color("font_" + state + "_color", "Button", PAPER)
	return theme

static func label(parent: Node, text: String, font_size: int = 19) -> Label:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.set_meta("base_font_size", font_size)
	node.add_theme_font_size_override("font_size", font_size)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

static func button(parent: Node, text: String, action: Callable, node_name: String = "") -> Button:
	var node := Button.new()
	node.text = text
	if not node_name.is_empty():
		node.name = node_name
		node.unique_name_in_owner = true
	parent.add_child(node)
	node.owner = parent.owner if parent.owner else parent
	node.pressed.connect(action)
	return node

static func shell(root: Control, title: String, subtitle: String, height: float = 560) -> VBoxContainer:
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = skin()
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.035, 0.055, 0.067, 0.97)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, 20)
	root.add_child(outer)
	var center := CenterContainer.new()
	outer.add_child(center)
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = INK
	box.border_color = Color("697376")
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	scroll.add_child(column)
	column.owner = root
	var fit := func() -> void:
		var factor := scale_for(root)
		root.theme.default_font_size = roundi(19 * factor)
		for text in root.find_children("*", "Label", true, false):
			if text.has_meta("base_font_size"):
				text.add_theme_font_size_override("font_size", roundi(text.get_meta("base_font_size") * factor))
		panel.custom_minimum_size.x = maxf(200, minf(540 * factor, root.size.x - 40))
		scroll.custom_minimum_size.y = maxf(120, minf(height * factor, root.size.y - 84))
	root.resized.connect(fit)
	root.get_window().size_changed.connect(fit)
	root.tree_exiting.connect(func():
		if root.get_window().size_changed.is_connected(fit):
			root.get_window().size_changed.disconnect(fit))
	fit.call_deferred()
	label(column, "MUSEUM AFTER HOURS", 13).modulate = ACCENT
	label(column, title, 34)
	label(column, subtitle, 17).modulate = MUTED
	column.add_child(HSeparator.new())
	return column
