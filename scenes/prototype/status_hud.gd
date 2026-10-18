extends Control

const Tuning = preload("res://scenes/prototype/tuning.gd")
const ToolStyle = preload("res://scenes/prototype/tool_style.gd")
# Screen-space geometry keeps these small gauges readable at any camera zoom.
# Leave the center empty: neither a filled disc nor a label covers the player.
const TOOLS: Array[StringName] = [&"ring", &"beam", &"cone", &"clock"]
const COLORS: Array[Color] = [ToolStyle.RING, ToolStyle.BEAM, ToolStyle.CONE, ToolStyle.CLOCK]
const NAMES: Array[String] = ["Ring", "Flash", "Cone", "Clock"]
const KEYS: Array[String] = ["1", "2", "3", "4"]
const RADIUS := 51.0
const WIDTH := 5.0
const GAP := 0.16
const READOUT_FILE := "user://combat-hud.cfg"
const READOUT_ALPHA: Array[float] = [1.0, 0.25, 0.0]

var readout_mode: int = 1 # Start dim; the local gauges should carry normal play.
var center := Vector2.ZERO
var fractions: Array[float] = [1.0, 1.0, 1.0, 1.0]
var selected: int = 0
var health_fraction := 1.0
var slowing := false
var repairing := false
var caption := ""
var available_tools: Array[int] = [1,2,3,4]
var charge_fraction := 0.0
var charging := false
var damage_bright := 0.0
var key_hint: Label
var tracked_player: Node3D
var inspecting := false
var history_seconds := 0.0
var selected_age := 0.0
var jump_cost := 0.0
var time_feedback := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settings := ConfigFile.new()
	if settings.load(READOUT_FILE) == OK:
		readout_mode = clampi(int(settings.get_value("hud", "readout", 1)), 0, 2)
	key_hint = Label.new()
	key_hint.text = "F7 · numbers: full / dim / hidden"
	key_hint.add_theme_font_size_override("font_size", 13)
	key_hint.modulate = Color(1, 1, 1, 0.55)
	key_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(key_hint)
	key_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	key_hint.offset_left = 16
	key_hint.offset_top = -28
	key_hint.offset_right = 360
	key_hint.offset_bottom = -8
	var legend := RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.scroll_active = false
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend.add_theme_font_size_override("normal_font_size", 12)
	add_child(legend)
	legend.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	legend.offset_left = 16
	legend.offset_right = -16
	legend.offset_top = -52
	legend.offset_bottom = -30
	legend.text = "[center][color=#%s]Cut blue[/color] · [color=#%s]Heat orange[/color] · [color=#%s]Shoot yellow[/color][/center]" % [ToolStyle.RING.to_html(false), ToolStyle.CONE.to_html(false), ToolStyle.BEAM.to_html(false)]


func cycle_readout() -> void:
	readout_mode = (readout_mode + 1) % READOUT_ALPHA.size()
	var settings := ConfigFile.new()
	settings.set_value("hud", "readout", readout_mode)
	settings.save(READOUT_FILE)


func set_combat_hint(muted: bool) -> void:
	key_hint.text = "M sound: %s · F7 numbers · F10 encounters" % ("off" if muted else "on")


func update_status(player: Node3D, weapons: Node3D, equipment: RefCounted) -> void:
	tracked_player = player
	var camera: Camera3D = player.camera
	visible = not camera.is_position_behind(player.global_position)
	selected = clampi(weapons.selected_tool - 1, 0, 3)
	repairing = equipment.repairing != &""
	if repairing:
		selected = TOOLS.find(equipment.repairing)
	var next_health := clampf(player.health / Tuning.PLAYER.health, 0.0, 1.0)
	if next_health < health_fraction: damage_bright = 1.0
	health_fraction = next_health
	available_tools.assign(weapons.available_tools)
	charging = weapons.beam_charging
	charge_fraction = weapons.beam_charge
	slowing = player.world_scale < 1.0
	for i in range(TOOLS.size()):
		fractions[i] = clampf(equipment.remaining(TOOLS[i]) / equipment.capacity(TOOLS[i]), 0.0, 1.0)
	caption = NAMES[selected] if not available_tools.is_empty() else "Find the illuminated exhibit"
	if repairing:
		caption += " · repair · slow" if slowing else " · repair · normal time"
	elif not equipment.can_use(TOOLS[selected], 1.0 if selected < 2 else 0.000001):
		caption += " · empty · E repair"
	elif selected == 0 and weapons.ring_drawing:
		caption += " · draw %.0f%%" % (100.0 * weapons.preview_length / Tuning.RING.length)
	elif selected == 0 and weapons.ring_phase != "idle":
		caption += " · " + weapons.ring_phase
	elif selected == 1 and weapons.beam_charging:
		caption += " · charge %.0f%%" % (weapons.beam_charge * 100.0)
	elif selected == 1 and weapons.beam_cooldown > 0.0:
		caption += " · %.1fs" % weapons.beam_cooldown
	elif selected == 2 and weapons.cone_active:
		caption += " · firing"
	elif selected == 2 and weapons.cone_burst_cooldown > 0.0:
		caption += " · shove %.1fs" % weapons.cone_burst_cooldown
	elif selected == 3:
		caption += " · Space inspect · E repair" if fractions[selected] < 0.999 else " · Space inspect"
	elif fractions[selected] < 0.999:
		caption += " · E repair"
	else:
		caption += " · ready"
	queue_redraw()


func _process(_delta: float) -> void:
	damage_bright = maxf(0.0, damage_bright - _delta * 1.6)
	if not is_instance_valid(tracked_player):
		return
	# Camera and player both interpolate. Project their rendered transforms
	# together so the gauges do not drift during movement or a timeline jump.
	var camera: Camera3D = tracked_player.camera
	var point: Vector3 = tracked_player.get_global_transform_interpolated() * (Vector3.UP * 0.5)
	var view: Vector3 = camera.get_global_transform_interpolated().affine_inverse() * point
	var clip: Vector4 = camera.get_camera_projection() * Vector4(view.x, view.y, view.z, 1.0)
	if absf(clip.w) > 0.000001:
		center = (Vector2(clip.x, -clip.y) / clip.w + Vector2.ONE) * get_viewport_rect().size * 0.5
	queue_redraw()


func update_timeline(history: RefCounted, cost: float, feedback: String, clock_after: float) -> void:
	inspecting = history.inspecting
	history_seconds = history.available_seconds
	selected_age = history.selected_seconds_ago
	jump_cost = cost
	time_feedback = feedback
	if inspecting:
		caption = "NOW · release Space to resume" if selected_age < 0.000001 else "−%.2fs · cost %.1f · clock %.1f after" % [selected_age, jump_cost, clock_after]
	queue_redraw()


func _draw() -> void:
	for i in range(TOOLS.size()):
		var start := -PI + i * PI * 0.5 + GAP
		var finish := start + PI * 0.5 - GAP * 2.0
		var active := i == selected or (i == 3 and (slowing or inspecting))
		var unlocked := i + 1 in available_tools
		var color := COLORS[i]
		# The track is visible even when empty; nothing fills the center.
		draw_arc(center, RADIUS, start, finish, 32, Color(color, 0.12), WIDTH + 2.0, true)
		if fractions[i] > 0.0 and unlocked:
			draw_arc(center, RADIUS, start, lerpf(start, finish, fractions[i]), 32,
				Color(color, 0.62 if active else 0.32), WIDTH, true)
		if i == selected:
			draw_arc(center, RADIUS + 6.0, start, finish, 32, Color(color, 0.4), 1.0, true)
		var middle := (start + finish) * 0.5
		var label_at := center + Vector2(cos(middle), sin(middle)) * (RADIUS + 18.0)
		_draw_centered(KEYS[i], label_at + Vector2(0, 4), 12, Color(color, 0.8 if active else 0.45))
		if fractions[i] < 0.25:
			# A quiet, persistent low-condition mark; avoid four flashing warnings.
			draw_circle(center + Vector2(cos(middle), sin(middle)) * (RADIUS - 9.0), 2.0,
				Color(color, 0.9))
	# Ivory health is distinct from the four equipment colors, with an empty center.
	var health_start := -PI * 0.4
	var health_end := health_start + TAU * 0.8
	draw_arc(center, RADIUS - 14, health_start, health_end, 48, Color("ece4d2", 0.12), 3.0, true)
	if health_fraction > 0:
		draw_arc(center, RADIUS - 14, health_start, lerpf(health_start, health_end, health_fraction),
			48, Color("ece4d2", 0.35 + damage_bright * 0.6), 3.0, true)
	if charging:
		var pointer := get_viewport().get_mouse_position() + Vector2(0,-24)
		draw_arc(pointer, 12, -PI * 0.5, PI * 1.5, 32, Color(COLORS[1],0.2),3,true)
		draw_arc(pointer, 12, -PI * 0.5, -PI * 0.5 + TAU * charge_fraction, 32, Color(COLORS[1],0.9),3,true)
	_draw_centered(caption, center + Vector2(0, RADIUS + 39), 13, Color(COLORS[selected], 0.9))
	if inspecting:
		var left := center + Vector2(-100, RADIUS + 57)
		var right := left + Vector2(200, 0)
		draw_line(left, right, Color(COLORS[3], 0.35), 3, true)
		var fraction := selected_age / history_seconds if history_seconds > 0.0 else 0.0
		var cursor := right.lerp(left, fraction)
		draw_line(cursor - Vector2(0, 5), cursor + Vector2(0, 5), COLORS[3], 2, true)
		_draw_centered("−%.1fs" % history_seconds, left + Vector2(0, 20), 11, COLORS[3])
		_draw_centered("NOW", right + Vector2(0, 20), 11, COLORS[3])
		var hint := "Wheel ↓ past / ↑ present · Esc cancel" if selected_age < 0.000001 else "Wheel ↓ past / ↑ present · release Space to jump · Esc cancel"
		_draw_centered(time_feedback if not time_feedback.is_empty() else hint, center + Vector2(0, RADIUS + 100), 12, Color(COLORS[3], 0.85))


func _draw_centered(text: String, at: Vector2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	# A small shadow keeps lettering legible without opaque backing panels.
	draw_string(font, at - Vector2(width * 0.5, -1), text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, font_size, Color(0, 0, 0, 0.65))
	draw_string(font, at - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, font_size, color)
