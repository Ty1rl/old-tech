extends RefCounted

const INK := Color("191713")
const PAPER := Color("f1eadb")
const MUTED := Color("aaa69d")
const ACCENT := Color("e9b954")

static func scale_for(node: Node) -> float:
	# Delayed layout can outlive a popup's window during scene teardown.
	if not node.is_inside_tree(): return 1.0
	var pixels := node.get_window().size.x
	return clampf(node.get_viewport().get_visible_rect().size.x / maxf(1, pixels), 1, 1.5)

static func skin() -> Theme:
	return preload("res://scenes/ui/museum_theme.tres").duplicate()

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
	backdrop.color = Color(0.035, 0.03, 0.025, 0.78)
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
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation",12)
	panel.add_child(stack)
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation",8)
	stack.add_child(header)
	label(header,"MUSEUM AFTER HOURS",13).modulate=ACCENT
	label(header,title,34)
	label(header,subtitle,17).modulate=MUTED
	header.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",14)
	scroll.add_child(column)
	column.owner = root
	# Titles stay outside the scroll area; keyboard focus only scrolls controls.
	var root_ref: WeakRef = weakref(root)
	var panel_ref: WeakRef = weakref(panel)
	var scroll_ref: WeakRef = weakref(scroll)
	var header_ref: WeakRef = weakref(header)
	var window_ref: WeakRef = weakref(root.get_window())
	var fit := func() -> void:
		var view: Control = root_ref.get_ref()
		var surface: PanelContainer = panel_ref.get_ref()
		var scroller: ScrollContainer = scroll_ref.get_ref()
		var title_block: VBoxContainer = header_ref.get_ref()
		if view == null or surface == null or scroller == null or title_block == null: return
		if not view.is_inside_tree(): return
		var factor := scale_for(view)
		var body_font := roundi(19*factor)
		if view.theme.default_font_size != body_font: view.theme.default_font_size=body_font
		for text in view.find_children("*","Label",true,false):
			if text.has_meta("base_font_size"):
				var font_size := roundi(text.get_meta("base_font_size")*factor)
				if text.get_theme_font_size("font_size") != font_size:
					text.add_theme_font_size_override("font_size",font_size)
		surface.custom_minimum_size.x=maxf(200,minf(540*factor,view.size.x-40))
		var budget:=maxf(120,minf(height*factor,view.size.y-84))
		scroller.custom_minimum_size.y=maxf(64,budget-title_block.get_combined_minimum_size().y-12)
	root.resized.connect(fit)
	root.get_window().size_changed.connect(fit)
	header.minimum_size_changed.connect(fit,CONNECT_DEFERRED)
	root.tree_exiting.connect(func():
		var window: Window=window_ref.get_ref()
		if window!=null and window.size_changed.is_connected(fit):window.size_changed.disconnect(fit))
	fit.call_deferred()
	return column


# Deferred focus is shared by menus only. Neither a closing popup nor an old
# scene may take focus back from the current top popup.
static func focus_on_open(view: Control, target: Control) -> void:
	var view_ref: WeakRef = weakref(view)
	var target_ref: WeakRef = weakref(target)
	var apply := func() -> void:
		var owner_view: Control = view_ref.get_ref()
		var control: Control = target_ref.get_ref()
		if owner_view == null or control == null or not control.is_inside_tree(): return
		var parent: Node = control
		while parent != null:
			if parent.is_queued_for_deletion(): return
			parent = parent.get_parent()
		if not owner_view.can_process() or not control.is_visible_in_tree(): return
		var manager := control.get_node_or_null("/root/SceneManager")
		if manager != null and manager.has_popup():
			var popup: Node = manager.get_popup(&"")
			if popup != null and popup != owner_view and not popup.is_ancestor_of(owner_view): return
		wire_focus(owner_view)
		var current := control.get_viewport().gui_get_focus_owner()
		if current != null and owner_view.is_ancestor_of(current):
			var ancestor := current.get_parent()
			while ancestor != null and ancestor != owner_view:
				if ancestor is ScrollContainer:
					ancestor.ensure_control_visible(current)
					break
				ancestor = ancestor.get_parent()
			return
		control.grab_focus()
	apply.call_deferred()
	# Old popup holders restore focus as they exit at frame end. Reconcile once
	# after that queue drains, while preserving navigation inside the new view.
	var tree := view.get_tree()
	tree.process_frame.connect(func(): tree.process_frame.connect(apply, CONNECT_ONE_SHOT), CONNECT_ONE_SHOT)

static func wire_focus(view: Control) -> void:
	var controls: Array[Control] = []
	for node in view.find_children("*", "Control", true, false):
		if not (node is BaseButton or node is Slider) or not node.is_visible_in_tree(): continue
		if node is BaseButton and node.disabled: continue
		if node.focus_mode == Control.FOCUS_NONE: continue
		controls.append(node)
	for i in range(controls.size()):
		var previous := controls[posmod(i - 1, controls.size())]
		var next := controls[(i + 1) % controls.size()]
		controls[i].focus_previous = controls[i].get_path_to(previous)
		controls[i].focus_next = controls[i].get_path_to(next)
		controls[i].focus_neighbor_top = controls[i].focus_previous
		controls[i].focus_neighbor_bottom = controls[i].focus_next
