extends Control

# Explanations freeze via the campaign's world/action guard, not SceneTree.pause.
# Practice resumes actions but keeps crowd pressure gated until complete_lesson.
signal resume_requested(id: StringName)
signal lesson_completed(id: StringName)
signal blocking_changed(value: bool)

const UI = preload("res://scenes/ui/ui_style.gd")
const ToolStyle = preload("res://scenes/prototype/tool_style.gd")
const BLUE: Color = ToolStyle.RING
const ORANGE: Color = ToolStyle.CONE
const YELLOW: Color = ToolStyle.BEAM
const VIOLET: Color = ToolStyle.CLOCK
const GUIDE: Color = ToolStyle.REPAIR_GUIDE

# Entry format: [imperative_heading, subtle_body, lesson_key, subtle_subtitle]
const LESSONS := {
	"cut": ["Hold, draw, release", "1 · Ring Cutter — draw across the blue link.", "cut", "1 · RING CUTTER"],
	"heat": ["Aim and hold", "3 · Heat Bellows — strip orange armor and push threats back.", "heat", "3 · HEAT BELLOWS"],
	"shot": ["Click to shoot", "2 · Focused Flash — aim at the yellow core.", "shot", "2 · FOCUSED FLASH"],
	"slow": ["Hold Space", "Hold Space to slow the world, shoot the target, then release.", "slow", "TIME SLOW"],
	"repair": ["Press E to repair", "Press E to open repair: spin, connect, and trace to 100%; closes when full.", "repair", "TOOL REPAIR"],
	"charge": ["Hold, then release", "2 · Focused Flash — charge until bright to pierce aligned targets.", "charge", "2 · FOCUSED FLASH · PIERCE"],
	"opening": ["Cut or heat, then shoot", "Open the blue link or orange armor, then switch to 2 for yellow.", "opening", "OPEN · THEN 2 · FOCUSED FLASH"],
	"pair": ["Click A, then B", "2 · Focused Flash — shoot A to open B before its shutter closes.", "pair", "2 · FOCUSED FLASH · PAIR"],
	"loop": ["Hold, draw, release", "1 · Ring Cutter — cut every blue support, then charge 2 on yellow.", "loop", "1 · RING CUTTER · LOOP"],
	"zigzag": ["Hold, draw, release", "1 · Ring Cutter — bend across each blue span, then charge 2 on yellow.", "zigzag", "1 · RING CUTTER · ZIGZAG"],
	"rewind": ["Scroll, then press Enter", "When a hit spends an emergency charge, scroll the wheel to an earlier safe moment and confirm.", "rewind", "EMERGENCY REWIND"],
	"final": ["Open each lock, then shoot", "Clear pair, zigzag, and loop phases, then finish the yellow core.", "final", "THE BURIAL DEVICE"],
}

var blocking := false
var practicing := false
var active_id: StringName = &""
var learned: Dictionary = {}
var world_points: Array[Vector3] = []
var ghost: Array[Vector2] = []
var projected: Array[Vector2] = []
var offscreen: Array[bool] = []
var camera: Camera3D
var age := 0.0
var align_pattern := false
var card: PanelContainer
var heading: Label
var body_label: Label
var state_label: Label
var practice_button: Button
var accent: Color = BLUE
var _subtitle_text := ""
var _layout_size := Vector2(-1, -1)
var _layout_dirty := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UI.skin()
	_ensure_authored_hierarchy()
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	if not GameState.settings_changed.is_connected(_on_settings_changed):
		GameState.settings_changed.connect(_on_settings_changed)
	hide()


func _ensure_authored_hierarchy() -> void:
	if get_node_or_null("Card") == null:
		var packed: PackedScene = load("res://scenes/ui/tutorial.tscn")
		if packed != null:
			var authored: Control = packed.instantiate()
			var authored_card: PanelContainer = authored.get_node_or_null("Card") as PanelContainer
			if authored_card != null:
				authored.remove_child(authored_card)
				add_child(authored_card)
			authored.free()
	card = get_node_or_null("Card") as PanelContainer
	state_label = get_node_or_null("Card/Column/StateLabel") as Label
	heading = get_node_or_null("Card/Column/HeadingLabel") as Label
	body_label = get_node_or_null("Card/Column/BodyLabel") as Label
	practice_button = get_node_or_null("Card/Column/PracticeButton") as Button
	if is_instance_valid(body_label):
		body_label.modulate = UI.MUTED
	if is_instance_valid(practice_button) and not practice_button.pressed.is_connected(request_practice):
		practice_button.pressed.connect(request_practice)


func _on_resized() -> void:
	_layout(true)


func setup(value: Camera3D) -> void:
	camera = value


static func is_drawing_lesson(id: StringName) -> bool:
	return id in [&"cut", &"loop", &"zigzag"]


static func accent_for_lesson(id: StringName) -> Color:
	if id == &"heat":
		return ORANGE
	if id in [&"shot", &"charge", &"pair", &"final"]:
		return YELLOW
	if id in [&"slow", &"rewind"]:
		return VIOLET
	if id == &"repair":
		return GUIDE
	return BLUE


static func subtitle_for_lesson(id: StringName) -> String:
	if LESSONS.has(String(id)):
		var entry: Array = LESSONS[String(id)]
		if entry.size() >= 4:
			return String(entry[3])
	return "ACTION GUIDE"


func set_phase_accent(color: Color, subtitle: String = "") -> void:
	accent = color
	if is_instance_valid(state_label):
		state_label.modulate = accent
		if not subtitle.is_empty():
			_subtitle_text = subtitle
			state_label.text = subtitle
	queue_redraw()


func show_known_lesson(id: StringName, targets: Array[Vector3]) -> bool:
	if not LESSONS.has(String(id)):
		return false
	var text: Array = LESSONS[String(id)]
	_subtitle_text = subtitle_for_lesson(id)
	show_lesson(id, String(text[0]), String(text[1]), targets, gesture_for(id))
	if active_id == id:
		align_pattern = is_drawing_lesson(id)
	return visible and active_id == id


func show_lesson(id: StringName, title: String, text: String, targets: Array[Vector3], gesture: Array[Vector2] = []) -> void:
	_ensure_authored_hierarchy()
	if is_learned(id) or id == active_id or not active_id.is_empty():
		return
	active_id = id
	align_pattern = false
	world_points = targets.duplicate()
	ghost.clear()
	if is_drawing_lesson(id) or not LESSONS.has(String(id)):
		ghost.assign(gesture)
	heading.text = title
	body_label.text = text
	accent = accent_for_lesson(id)
	_subtitle_text = subtitle_for_lesson(id)
	state_label.modulate = accent
	state_label.text = _subtitle_text
	practice_button.focus_mode = Control.FOCUS_ALL
	practice_button.mouse_filter = Control.MOUSE_FILTER_STOP
	practice_button.show()
	practicing = false
	age = 0.0
	_set_blocking(true)
	show()
	_layout(true)
	practice_button.grab_focus.call_deferred()


func request_practice() -> void:
	if active_id.is_empty() or not blocking or SceneManager.has_popup():
		return
	practicing = true
	practice_button.release_focus()
	practice_button.focus_mode = Control.FOCUS_NONE
	practice_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	practice_button.hide()
	state_label.modulate = accent
	state_label.text = _subtitle_text + " · YOUR TURN"
	_set_blocking(false)
	resume_requested.emit(active_id)
	_layout(true)


func complete_lesson(id: StringName) -> void:
	# Only the campaign/harness calls this after observing actual success.
	if id != active_id or not practicing:
		return
	learned[id] = true
	active_id = &""
	practicing = false
	_set_blocking(false)
	world_points.clear()
	projected.clear()
	ghost.clear()
	hide()
	lesson_completed.emit(id)


func is_learned(id: StringName) -> bool:
	return bool(learned.get(id, false)) or not bool(GameState.preferences().tutorial)


func dismiss() -> void:
	active_id = &""
	practicing = false
	_set_blocking(false)
	world_points.clear()
	projected.clear()
	ghost.clear()
	hide()


func reset_run() -> void:
	learned.clear()
	active_id = &""
	practicing = false
	_set_blocking(false)
	world_points.clear()
	projected.clear()
	ghost.clear()
	hide()


func _set_blocking(value: bool) -> void:
	var filter := Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	mouse_filter = filter
	if is_instance_valid(card):
		card.mouse_filter = filter
	if blocking != value:
		blocking = value
		blocking_changed.emit(value)


func _on_settings_changed(values: Dictionary) -> void:
	if not values.tutorial and not active_id.is_empty():
		var id := active_id
		var prior := learned.duplicate()
		reset_run()
		learned = prior
		resume_requested.emit(id)


func _layout(force: bool = true) -> void:
	if not is_instance_valid(card):
		return
	if is_inside_tree() and (size.x <= 1.0 or size.y <= 1.0):
		size = get_viewport_rect().size
	if force or _layout_dirty or _layout_size != size:
		_layout_size = size
		_layout_dirty = false
		var factor := UI.scale_for(self)
		theme.default_font_size = roundi(18 * factor)
		var width := minf(420 * factor, maxf(210, size.x - 32))
		var inner_w := maxf(160.0, width - 32.0)
		var col := card.get_node_or_null("Column") as Control
		if is_instance_valid(col):
			col.custom_minimum_size.x = inner_w
			col.size.x = inner_w
		for ctrl: Control in [state_label, heading, body_label, practice_button]:
			if is_instance_valid(ctrl):
				ctrl.custom_minimum_size.x = inner_w
				ctrl.size.x = inner_w
		card.custom_minimum_size.x = width
		card.size = Vector2(width, 0.0)
		heading.add_theme_font_size_override("font_size", roundi((22 if size.y < 480 else 26) * factor))
		body_label.add_theme_font_size_override("font_size", roundi((13 if size.y < 480 else 14) * factor))
		state_label.add_theme_font_size_override("font_size", roundi(12 * factor))
		card.reset_size()
	var min_size := card.get_combined_minimum_size()
	if absf(card.size.y - min_size.y) > 1.0:
		card.size.y = min_size.y
	card.position.x = (size.x - card.size.x) * 0.5
	var target_y := size.y * 0.4
	if not projected.is_empty():
		target_y = projected[0].y
	card.position.y = maxf(14, size.y - card.size.y - 16) if target_y < size.y * 0.55 else 16


func _process(delta: float) -> void:
	if not visible:
		return
	if is_inside_tree() and (size.x <= 1.0 or size.y <= 1.0):
		size = get_viewport_rect().size
	# Pause/settings cover this card and stop its practice controls; emergency mode stays uncovered.
	var in_emergency: bool = GameState.has_method("is_in_emergency") and bool(GameState.call("is_in_emergency")) and not GameState.is_paused()
	var covered: bool = SceneManager.has_popup() or (not GameState.is_playing() and not in_emergency)
	card.visible = not covered
	if covered:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()
		return
	var filter := Control.MOUSE_FILTER_STOP if blocking else Control.MOUSE_FILTER_IGNORE
	mouse_filter = filter
	card.mouse_filter = filter
	age += delta
	projected.clear()
	offscreen.clear()
	if is_instance_valid(camera):
		var rect := get_viewport_rect().grow(-36)
		for point in world_points:
			var behind := camera.is_position_behind(point)
			var screen := camera.unproject_position(point)
			if behind:
				var local := camera.to_local(point)
				var direction := Vector2(local.x, -local.y)
				if direction.is_zero_approx():
					direction = Vector2.DOWN
				screen = size * 0.5 + direction.normalized() * size.length()
			var outside := behind or not rect.has_point(screen)
			projected.append(screen.clamp(rect.position, rect.end))
			offscreen.append(outside)
	_layout(false)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if blocking and event is InputEventMouse:
		accept_event()


func _draw() -> void:
	if not visible or not card.visible:
		return
	if blocking:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.025, 0.035, 0.22))
	var font := ThemeDB.fallback_font
	var factor := UI.scale_for(self)
	for i in range(projected.size()):
		var p := projected[i]
		draw_arc(p, 21 + 2.5 * sin(age * 4), 0, TAU, 36, accent, 2.5, true)
		draw_circle(p, 3.5, accent)
		if projected.size() > 1 or offscreen[i]:
			var caption := str(i + 1) + (" · offscreen" if offscreen[i] else "")
			var label_position := p + Vector2(26, 6)
			label_position.x = clampf(label_position.x, 16, maxf(16, size.x - 160 * factor))
			draw_string(font, label_position, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(15 * factor), GUIDE)
		if offscreen[i]:
			var direction := (p - size * 0.5).normalized()
			var side := direction.orthogonal()
			draw_colored_polygon(PackedVector2Array([p + direction * 17, p - direction * 8 + side * 8, p - direction * 8 - side * 8]), accent)
	# A blue line only teaches drawing; never draw a moving line for clicks, holds, Space, or rewind.
	if ghost.size() >= 2 and (is_drawing_lesson(active_id) or not LESSONS.has(String(active_id))) and not projected.is_empty() and not offscreen.has(true):
		var area := Rect2(projected[0], Vector2.ZERO)
		for p in projected:
			area = area.expand(p)
		area = area.grow(48)
		var path := PackedVector2Array()
		for p in ghost:
			path.append(area.position + p * area.size)
		if align_pattern and active_id in [&"loop", &"zigzag"] and projected.size() >= 2:
			path = PackedVector2Array(projected)
			if active_id == &"loop":
				path.append(projected[0])
		draw_polyline(path, Color(BLUE, 0.5), 3.0, true)
		var step := fmod(age * 0.65, 1.0) * (path.size() - 1)
		var index := mini(int(step), path.size() - 2)
		var cursor := path[index].lerp(path[index + 1], step - index)
		draw_circle(cursor, 6.5, GUIDE)
		draw_arc(cursor, 10.5, 0, TAU, 24, BLUE, 2.0, true)


# Ghost coordinates are normalized to the padded projected target bounds.
# Only drawing lessons return a blue trace path; clicks/holds/Space/rewind use real action demos.
static func gesture_for(id: StringName) -> Array[Vector2]:
	var empty: Array[Vector2] = []
	if id == &"loop":
		var path: Array[Vector2] = []
		for i in range(25):
			path.append(Vector2(0.5, 0.5) + Vector2(cos(i * TAU / 24), sin(i * TAU / 24)) * 0.43)
		return path
	if id == &"zigzag":
		return [Vector2(0, 0.75), Vector2(0.25, 0.2), Vector2(0.5, 0.8), Vector2(0.75, 0.2), Vector2(1, 0.7)]
	if id == &"cut":
		return [Vector2(0, 0.75), Vector2(1, 0.25)]
	return empty
