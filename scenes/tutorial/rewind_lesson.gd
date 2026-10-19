class_name RewindLesson
extends Node
## Forced staged demonstration for the EmergencyRewind lesson.
##
## Public Contract (for jam-4 Wave B campaign integration & standalone checks):
## - `begin(arena: Node) -> bool`:
##     Starts the forced staged example on `arena` (`CombatArena` / `MuseumCampaign`).
##     Requires NO player movement, shooting, or AI hit to trigger. Returns `false`
##     if already active or if the completion latch (`is_completed`) is already set.
## - `step(real_delta: float) -> void`:
##     Advances the lesson by `real_delta` (unscaled engine seconds). Call every
##     physics tick from the campaign/driver BOTH during `Phase.STAGING` and while
##     the world is frozen in `Phase.SCRUB` (`time_controller.world_scale == 0.0`).
##     Safe to call whether `arena._physics_process(real_delta)` also ran or is
##     disabled in headless checks.
## - `cancel() -> void`:
##     Idempotently aborts an in-progress `STAGING` or `SCRUB` session (e.g. room
##     retry or scene exit), cleans up staged entities, and restores a valid non-
##     frozen attempt without setting the completion latch.
## - `signal completed`:
##     Emitted ONCE after the player confirms recovery in `EmergencyRewind`, AFTER
##     `EmergencyRewind.confirm()` has finished restoring the safe earlier moment and
##     `TimeController.begin_attempt()` has established the fresh real-play boundary
##     with all 3 charges (`charges_remaining == 3`) and full time meter.
##     Because `completed` fires after `EmergencyRewind.ended`, callers can safely
##     spawn the next wave inside their `completed` handler without reentrant resets.

signal completed

enum Phase {
	IDLE,
	STAGING,
	SCRUB,
	COMPLETED,
	CANCELLED,
}

const UI = preload("res://scenes/ui/ui_style.gd")
const ToolStyle = preload("res://scenes/prototype/tool_style.gd")

const STAGING_DURATION := 1.55
const SHOT_TIME := 0.32
const AMBUSH_TIME := 0.90
const MAX_STAGE_SLICE := 0.06
const PLAYER_SPAWN_Y := 0.55

@onready var overlay: CanvasLayer = get_node_or_null("Overlay") as CanvasLayer
@onready var banner: PanelContainer = get_node_or_null("%Banner") as PanelContainer
@onready var title_label: Label = get_node_or_null("%TitleLabel") as Label
@onready var action_label: Label = get_node_or_null("%ActionLabel") as Label
@onready var skip_button: Button = get_node_or_null("%SkipButton") as Button

var phase: Phase = Phase.IDLE
## Completion latch lives outside world snapshots so previewing or restoring
## earlier snapshots can never re-arm or repeat the forced lesson.
var _completed_latch := false
var was_skipped := false
var audio_manager_override: Node = null

var phase_name: StringName:
	get:
		match phase:
			Phase.STAGING: return &"staging"
			Phase.SCRUB: return &"scrub"
			Phase.COMPLETED: return &"completed"
			Phase.CANCELLED: return &"cancelled"
			_: return &"idle"

var active: bool:
	get: return phase == Phase.STAGING or phase == Phase.SCRUB

var is_staging: bool:
	get: return phase == Phase.STAGING

var is_scrubbing: bool:
	get: return phase == Phase.SCRUB

var is_completed: bool:
	get: return _completed_latch

var is_cancelled: bool:
	get: return phase == Phase.CANCELLED

var default_safe_index: int:
	get: return _default_safe_index

var min_safe_index: int:
	get: return _min_safe_index

var completed_count: int:
	get: return _completed_count

var _arena: Node = null
var _staging_elapsed := 0.0
var _shot_fired := false
var _ambush_spawned := false
var _safe_origin := Vector3(0.0, PLAYER_SPAWN_Y, 4.0)
var _exposed_pos := Vector3(1.5, PLAYER_SPAWN_Y, 2.2)
var _target_pos := Vector3(1.5, PLAYER_SPAWN_Y, -4.2)
var _staged_enemies: Array[Node3D] = []
var _staged_enemy_ids: Array[int] = []
var _safe_snapshot_count := 0
var _safe_fallback_state: Dictionary = {}
var _min_safe_index := 1
var _default_safe_index := 1
var _entering_scrub := false
var _confirmed_in_lesson := false
var _adjusting_selection := false
var _cancelling := false
var _finishing_completion := false
var _completed_count := 0
var _last_history_clock := -1.0
var _suppress_next_lmb_up := false
var _suppress_enter_until_release := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_skip_button()
	_style_banner()
	if get_window() != null and not get_window().size_changed.is_connected(_fit_banner):
		get_window().size_changed.connect(_fit_banner)
	_fit_banner.call_deferred()
	_sync_banner()


func _bind_skip_button() -> void:
	if skip_button == null:
		skip_button = get_node_or_null("%SkipButton") as Button
	if is_instance_valid(skip_button):
		skip_button.focus_mode = Control.FOCUS_NONE
		skip_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		skip_button.shortcut = null
		skip_button.text = "Skip"
		if not skip_button.pressed.is_connected(_on_skip_button_pressed):
			skip_button.pressed.connect(_on_skip_button_pressed)


func _on_skip_button_pressed() -> void:
	skip_lesson(true)


func is_point_on_skip_button(screen_pos: Vector2) -> bool:
	if not active or overlay == null or not overlay.visible:
		return false
	if not is_instance_valid(skip_button) or not skip_button.visible or skip_button.disabled:
		return false
	return skip_button.get_global_rect().has_point(screen_pos)


func _get_audio_manager() -> Node:
	if is_instance_valid(audio_manager_override):
		return audio_manager_override
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("AudioManager") if tree != null and tree.root != null else null


func _stop_tutorial_dialogue() -> void:
	var am := _get_audio_manager()
	if is_instance_valid(am) and am.has_method("stop_dialogue"):
		am.call("stop_dialogue")


func _input(event: InputEvent) -> void:
	if _suppress_next_lmb_up and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_suppress_next_lmb_up = false
		if is_inside_tree() and get_viewport() != null:
			get_viewport().set_input_as_handled()
		return
	if _suppress_enter_until_release and event is InputEventKey:
		var enter_code: int = event.physical_keycode if event.physical_keycode else event.keycode
		if enter_code == KEY_ENTER or enter_code == KEY_KP_ENTER:
			if not event.pressed:
				_suppress_enter_until_release = false
				if is_instance_valid(_arena) and "_suppress_enter_until_release" in _arena:
					_arena.set("_suppress_enter_until_release", false)
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()
			return
	if not active or _is_interrupted_by_pause_or_modal():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if is_point_on_skip_button(event.position):
			skip_lesson(true)
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()
			return
	if event is InputEventKey:
		var key_code: int = event.physical_keycode if event.physical_keycode else event.keycode
		if key_code == KEY_ENTER or key_code == KEY_KP_ENTER:
			if phase == Phase.STAGING:
				if is_inside_tree() and get_viewport() != null:
					get_viewport().set_input_as_handled()
				return
			elif phase == Phase.SCRUB:
				if is_inside_tree() and get_viewport() != null:
					get_viewport().set_input_as_handled()
				if event.pressed and not event.echo:
					_suppress_enter_until_release = true
					if is_instance_valid(_arena) and "_suppress_enter_until_release" in _arena:
						_arena.set("_suppress_enter_until_release", true)
					var er: EmergencyRewind = _arena.get("emergency_rewind") as EmergencyRewind if is_instance_valid(_arena) else null
					if is_instance_valid(er) and er.active:
						er.confirm()
				return


func _exit_tree() -> void:
	if get_window() != null and get_window().size_changed.is_connected(_fit_banner):
		get_window().size_changed.disconnect(_fit_banner)
	if active:
		cancel()
	else:
		_disconnect_arena_signals()


## Resets the run-level completion latch when starting a brand-new campaign run.
func reset_for_new_run() -> void:
	if active:
		cancel()
	_completed_latch = false
	was_skipped = false
	_completed_count = 0
	_suppress_next_lmb_up = false
	_suppress_enter_until_release = false
	phase = Phase.IDLE
	_sync_banner()


## Starts the forced staged demonstration on `arena`. Returns false if already
## active or already completed once in this run.
func begin(arena: Node) -> bool:
	if _completed_latch or active:
		return false
	if arena == null or not is_instance_valid(arena):
		return false
	var tc: TimeController = arena.get("time_controller") as TimeController
	var er: EmergencyRewind = arena.get("emergency_rewind") as EmergencyRewind
	var hist: ReplayHistory = arena.get("history") as ReplayHistory
	if tc == null or er == null or hist == null:
		return false

	_bind_skip_button()
	_arena = arena
	was_skipped = false
	_suppress_next_lmb_up = false
	if not Input.is_key_pressed(KEY_ENTER) and not Input.is_key_pressed(KEY_KP_ENTER):
		_suppress_enter_until_release = false
	_staging_elapsed = 0.0
	_shot_fired = false
	_ambush_spawned = false
	_entering_scrub = false
	_confirmed_in_lesson = false
	_adjusting_selection = false
	_staged_enemies.clear()
	_staged_enemy_ids.clear()

	# Unlock rewind so the forced depletion enters EmergencyRewind rather than exhausting.
	tc.set_capabilities(tc.slow_unlocked, true)
	if "_rewind_unlocked" in _arena:
		_arena.set("_rewind_unlocked", true)
	if "_injury_given" in _arena:
		_arena.set("_injury_given", true)

	if er.active:
		er.abandon()
	tc.begin_attempt()

	if _has_popup(&"Repair") and _arena.has_method("_close_repair"):
		_arena.call("_close_repair")
	var tut: Control = _arena.get("tutorial") as Control
	if is_instance_valid(tut):
		tut.hide()

	_clear_live_inputs()
	var director: Node3D = _arena.get("director") as Node3D
	if is_instance_valid(director) and director.has_method("clear"):
		director.call("clear")

	var player: CombatPlayer = _arena.get("player") as CombatPlayer
	var start_pos: Vector3 = player.position if is_instance_valid(player) else Vector3(0.0, PLAYER_SPAWN_Y, 4.0)
	_safe_origin = Vector3(clampf(start_pos.x, -5.5, 5.5), PLAYER_SPAWN_Y, clampf(start_pos.z, -1.0, 7.0))
	_exposed_pos = _safe_origin + Vector3(1.5, 0.0, -1.8)
	_target_pos = _exposed_pos + Vector3(0.0, 0.0, -5.8)

	if is_instance_valid(player):
		player.position = _safe_origin
		player.velocity = Vector3.ZERO
		if is_instance_valid(player.model) and player.model.is_inside_tree():
			player.model.global_basis = Basis.looking_at(Vector3.FORWARD)
		player.reset_physics_interpolation()

	var weapons: Node = _arena.get("weapons") as Node
	if is_instance_valid(weapons):
		var avail: Array = weapons.get("available_tools") if weapons.get("available_tools") is Array else [2]
		var preferred_slot: int = 2 if 2 in avail else (int(avail[0]) if not avail.is_empty() else 2)
		if weapons.has_method("select_tool"):
			weapons.call("select_tool", preferred_slot)
		if is_instance_valid(player) and player.is_inside_tree():
			player.set_visual_tool(preferred_slot)

	# Keep the lesson scrub range short and focused while preserving the 18s/12Hz settings,
	# and pre-seed ~2s of safe baseline snapshots so ~1s wheel steps have multiple safe notches.
	hist.clear()
	_safe_fallback_state = _capture_clean_snapshot()
	hist.seed_checkpoint(_safe_fallback_state)
	hist.push(_safe_fallback_state)
	for _s in range(24):
		hist.record(hist.sample_interval + 0.0005, func() -> Dictionary: return _safe_fallback_state.duplicate(true))
	_safe_snapshot_count = hist.snapshot_count
	_last_history_clock = hist.clock

	# Spawn a single safe practice target ahead for the character's staged shot.
	_spawn_staged_target()

	_connect_arena_signals()
	phase = Phase.STAGING
	_sync_banner()
	if _arena.has_method("_update_hud"):
		_arena.call("_update_hud")
	return true


## Advances the staged sequence or frozen scrub state by `real_delta` seconds.
func step(real_delta: float) -> void:
	if not active:
		return
	if _arena == null or not is_instance_valid(_arena) or not _arena.is_inside_tree():
		cancel()
		return
	if not (real_delta > 0.0) or is_inf(real_delta) or is_nan(real_delta):
		return
	if _is_interrupted_by_pause_or_modal():
		_clear_live_inputs()
		return

	var tut: Control = _arena.get("tutorial") as Control
	if is_instance_valid(tut):
		tut.hide()

	if phase == Phase.STAGING:
		var remaining := minf(real_delta, 4.0)
		while remaining > 0.00001 and phase == Phase.STAGING:
			var slice := minf(remaining, MAX_STAGE_SLICE)
			remaining -= slice
			_step_staging_slice(slice)
	elif phase == Phase.SCRUB:
		_step_scrub_freeze(real_delta)


## Skips the rewind teaching segment via the click-only Skip button, stopping
## active tutorial speech, restoring a clean 3-charge attempt boundary, and
## emitting `completed` once idempotently.
func skip_lesson(from_mouse: bool = true) -> bool:
	if not active or _completed_latch or _cancelling or _finishing_completion:
		return false
	if _is_interrupted_by_pause_or_modal():
		return false
	_finishing_completion = true
	was_skipped = true
	_suppress_next_lmb_up = from_mouse or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_disconnect_arena_signals()
	phase = Phase.COMPLETED
	_completed_latch = true
	_completed_count += 1
	_stop_tutorial_dialogue()

	if is_instance_valid(_arena):
		var ev: EmergencyRewindView = _arena.get("emergency_view") as EmergencyRewindView
		if is_instance_valid(ev):
			ev.set_lesson_mode(false)
		var er: EmergencyRewind = _arena.get("emergency_rewind") as EmergencyRewind
		if is_instance_valid(er) and er.active:
			er.abandon()
		var sv: Variant = _arena.get("scrub_view")
		if sv != null and sv is Object and (sv as Object).has_method("finish"):
			(sv as Object).call("finish")
		var feedback: Node = _arena.get("feedback") as Node
		if is_instance_valid(feedback) and feedback.has_method("clear_effects"):
			feedback.call("clear_effects")
		_cleanup_staged_entities()
		var player: CombatPlayer = _arena.get("player") as CombatPlayer
		if is_instance_valid(player):
			player.position = _safe_origin
			player.reset_input()
			player.reset_physics_interpolation()
		_clear_live_inputs()
		var lmb_down := from_mouse or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if "_suppress_next_lmb_release" in _arena and lmb_down:
			_arena.set("_suppress_next_lmb_release", true)
		var weapons: Node = _arena.get("weapons") as Node
		if is_instance_valid(weapons) and "require_fresh_press" in weapons:
			weapons.set("require_fresh_press", lmb_down)

		if "_rewound" in _arena:
			_arena.set("_rewound", true)
		if "_injury_given" in _arena:
			_arena.set("_injury_given", true)
		if "_rewind_unlocked" in _arena:
			_arena.set("_rewind_unlocked", true)

		var tc: TimeController = _arena.get("time_controller") as TimeController
		if is_instance_valid(tc):
			tc.set_capabilities(tc.slow_unlocked, true)
			tc.begin_attempt()

		if _arena.is_inside_tree():
			_sanitize_history_after_completion()
			if _arena.has_method("_update_hud"):
				_arena.call("_update_hud")

	_sync_banner()
	_finishing_completion = false
	completed.emit()
	_stop_tutorial_dialogue()
	return true


## Cancels an active lesson without setting the completion latch.
func cancel() -> void:
	if _cancelling or _finishing_completion:
		return
	if not active:
		return
	_cancelling = true
	_disconnect_arena_signals()
	phase = Phase.CANCELLED
	if is_instance_valid(_arena):
		var ev: EmergencyRewindView = _arena.get("emergency_view") as EmergencyRewindView
		if is_instance_valid(ev):
			ev.set_lesson_mode(false)
		var er: EmergencyRewind = _arena.get("emergency_rewind") as EmergencyRewind
		if is_instance_valid(er) and er.active:
			er.abandon()
		_cleanup_staged_entities()
		var player: CombatPlayer = _arena.get("player") as CombatPlayer
		if is_instance_valid(player):
			player.position = _safe_origin
			player.reset_input()
			player.reset_physics_interpolation()
		_clear_live_inputs()
		var tc: TimeController = _arena.get("time_controller") as TimeController
		if is_instance_valid(tc):
			tc.begin_attempt()
		var hist: ReplayHistory = _arena.get("history") as ReplayHistory
		if hist != null and _arena.is_inside_tree():
			hist.clear()
			var clean := _capture_clean_snapshot()
			hist.seed_checkpoint(clean)
		if _arena.is_inside_tree() and _arena.has_method("_update_hud"):
			_arena.call("_update_hud")
	_sync_banner()
	_cancelling = false


func _step_staging_slice(dt: float) -> void:
	_clear_live_inputs()
	var prev_elapsed := _staging_elapsed
	_staging_elapsed += dt

	var external_stepped := false
	var hist: ReplayHistory = _arena.get("history") as ReplayHistory
	if hist != null and _last_history_clock >= 0.0 and hist.clock > _last_history_clock + 0.00001:
		external_stepped = true

	var player: CombatPlayer = _arena.get("player") as CombatPlayer
	# 1. Safe character movement + real weapon demonstration (0.0 .. AMBUSH_TIME).
	var walk_t := clampf(_staging_elapsed / AMBUSH_TIME, 0.0, 1.0)
	var desired_pos: Vector3 = _safe_origin.lerp(_exposed_pos, smoothstep(0.0, 1.0, walk_t))
	var current_pos: Vector3 = player.position if is_instance_valid(player) else _safe_origin
	var step_vel: Vector3 = (desired_pos - current_pos) / maxf(0.001, dt)
	if is_instance_valid(player):
		player.position = desired_pos
		player.velocity = step_vel if _staging_elapsed < AMBUSH_TIME else Vector3.ZERO
		var aim_point: Vector3 = _target_pos + Vector3(0.0, 1.2, 0.0)
		var look_dir := Vector3(aim_point.x - desired_pos.x, 0.0, aim_point.z - desired_pos.z)
		if look_dir.length_squared() > 0.001 and is_instance_valid(player.model) and player.model.is_inside_tree():
			player.model.global_basis = Basis.looking_at(look_dir.normalized())
		if is_instance_valid(player.visual) and is_instance_valid(player.model) and player.model.is_inside_tree():
			var local_motion: Vector3 = player.model.global_basis.inverse() * Vector3(step_vel.x, 0.0, step_vel.z)
			player.visual.call("step_visual", dt, local_motion.length(), 7.0, local_motion)

	if not _shot_fired and _staging_elapsed >= SHOT_TIME:
		_shot_fired = true
		_fire_staged_shot(_target_pos + Vector3(0.0, 1.2, 0.0))

	# 2. Record safe history before the ambush appears (distinct timestamps via record()).
	if not _ambush_spawned and prev_elapsed < AMBUSH_TIME and hist != null:
		if not external_stepped:
			_step_arena_subsystems(dt, false)
		_record_clean_history(dt)
		_safe_fallback_state = _capture_clean_snapshot()
		_safe_snapshot_count = hist.snapshot_count
		_last_history_clock = hist.clock

	# 3. Spawn bounded familiar ambush threat + converging incoming volley.
	if not _ambush_spawned and _staging_elapsed >= AMBUSH_TIME:
		_ambush_spawned = true
		_spawn_ambush()
		_sync_banner()

	# 4. Advance incoming volley toward the exposed player position.
	if _ambush_spawned and _staging_elapsed < STAGING_DURATION and hist != null:
		_advance_ambush_poses(dt)
		if not external_stepped:
			_step_arena_subsystems(dt, true)
		_record_clean_history(dt)
		_last_history_clock = hist.clock

	# 5. Impact moment: trigger real EmergencyRewind automatically.
	if _staging_elapsed >= STAGING_DURATION:
		_trigger_forced_depletion()


func _step_arena_subsystems(dt: float, step_director: bool) -> void:
	var tc: TimeController = _arena.get("time_controller") as TimeController
	if is_instance_valid(tc):
		tc.slow_requested = false
		tc.advance(dt)
	var director: Node3D = _arena.get("director") as Node3D
	var player: CombatPlayer = _arena.get("player") as CombatPlayer
	if step_director and is_instance_valid(director) and director.has_method("step"):
		director.call("step", dt, player)
	var weapons: Node = _arena.get("weapons") as Node
	if is_instance_valid(weapons) and weapons.has_method("step") and is_instance_valid(director):
		weapons.call("step", dt, player, _target_pos, director.get("enemies"), dt)
	var feedback: Node = _arena.get("feedback") as Node
	var equipment: Variant = _arena.get("equipment")
	if is_instance_valid(feedback) and feedback.has_method("step"):
		feedback.call("step", dt, dt, 1.0, false, 0.0, weapons, equipment)
	if _arena.has_method("_update_hud"):
		_arena.call("_update_hud")


func _step_scrub_freeze(real_delta: float) -> void:
	var er: EmergencyRewind = _arena.get("emergency_rewind") as EmergencyRewind
	if not is_instance_valid(er) or not er.active:
		return
	if er.selected_index < _min_safe_index and er.choice_count > _min_safe_index:
		_adjusting_selection = true
		er.select(_min_safe_index)
		_adjusting_selection = false
	var sv: Variant = _arena.get("scrub_view")
	if sv != null and sv is Object and (sv as Object).has_method("step"):
		(sv as Object).call("step", real_delta)
	if "_scrub_speed" in _arena:
		var cur_speed := float(_arena.get("_scrub_speed"))
		var feedback: Node = _arena.get("feedback") as Node
		if is_instance_valid(feedback) and feedback.has_method("step"):
			feedback.call("step", real_delta, 0.0, 0.0, true, cur_speed, _arena.get("weapons"), _arena.get("equipment"))
		_arena.set("_scrub_speed", cur_speed * exp(-maxf(real_delta, 0.0) * 8.0))
	if _arena.has_method("_update_hud"):
		_arena.call("_update_hud")


func _spawn_staged_target() -> void:
	var director: Node3D = _arena.get("director") as Node3D
	if not is_instance_valid(director) or not director.has_method("spawn"):
		return
	var target: Node3D = director.call("spawn", &"yellow", _target_pos) as Node3D
	if is_instance_valid(target):
		_freeze_enemy_ai(target)
		target.set("health", 30.0)
		target.set("facing", (_safe_origin - _target_pos).normalized())
		_staged_enemies.append(target)
		_staged_enemy_ids.append(int(target.get("rewind_id")))


func _fire_staged_shot(aim_point: Vector3) -> void:
	var weapons: Node = _arena.get("weapons") as Node
	var player: CombatPlayer = _arena.get("player") as CombatPlayer
	if not is_instance_valid(weapons) or not is_instance_valid(player) or not weapons.has_method("handle_event"):
		return
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	weapons.call("handle_event", press, player, aim_point)
	weapons.call("handle_event", release, player, aim_point)
	var equipment: Variant = _arena.get("equipment")
	if equipment != null and equipment is Object and (equipment as Object).has_method("restore_tool"):
		(equipment as Object).call("restore_tool", &"beam", 1.0)


func _spawn_ambush() -> void:
	var director: Node3D = _arena.get("director") as Node3D
	if not is_instance_valid(director) or not director.has_method("spawn"):
		return
	var offsets: Array[Vector3] = [
		Vector3(-3.6, 0.0, -4.4),
		Vector3(0.0, 0.0, -5.2),
		Vector3(3.6, 0.0, -4.4),
		Vector3(4.4, 0.0, -1.2),
	]
	var kinds: Array[StringName] = [&"ranged", &"yellow", &"blue", &"orange"]
	for i in range(offsets.size()):
		var spawn_pos: Vector3 = _exposed_pos + offsets[i]
		spawn_pos.x = clampf(spawn_pos.x, -15.0, 15.0)
		spawn_pos.z = clampf(spawn_pos.z, -15.0, 15.0)
		var enemy: Node3D = director.call("spawn", kinds[i], spawn_pos) as Node3D
		if is_instance_valid(enemy):
			_freeze_enemy_ai(enemy)
			enemy.set("health", 999.0)
			var to_player: Vector3 = _exposed_pos - spawn_pos
			to_player.y = 0.0
			if to_player.length_squared() > 0.001:
				enemy.set("facing", to_player.normalized())
			_staged_enemies.append(enemy)
			_staged_enemy_ids.append(int(enemy.get("rewind_id")))
			if i < 3 and director.has_method("launch_projectile"):
				var dir: Vector3 = to_player.normalized() if to_player.length() > 0.01 else Vector3.BACK
				var dist: float = to_player.length()
				var speed: float = clampf((dist - 0.5) / maxf(0.25, STAGING_DURATION - AMBUSH_TIME), 6.0, 8.8)
				director.call("launch_projectile", spawn_pos + dir * 0.8, dir, 0.0, speed)


func _advance_ambush_poses(dt: float) -> void:
	for enemy in _staged_enemies:
		if not is_instance_valid(enemy) or float(enemy.get("health")) <= 0.0:
			continue
		var to_player: Vector3 = _exposed_pos - enemy.position
		to_player.y = 0.0
		if to_player.length() > 1.8:
			enemy.position += to_player.normalized() * (1.6 * dt)


func _freeze_enemy_ai(enemy: Node3D) -> void:
	enemy.set("contact_damage", 0.0)
	enemy.set("move_speed", 0.0)
	if "projectile_damage" in enemy:
		enemy.set("projectile_damage", 0.0)
	if "attack_timer" in enemy:
		enemy.set("attack_timer", 99.0)


func _ensure_minimum_safe_history() -> void:
	var hist: ReplayHistory = _arena.get("history") as ReplayHistory
	if hist == null:
		return
	if _safe_fallback_state.is_empty():
		_safe_fallback_state = _capture_clean_snapshot()
	while hist.snapshot_count < 24:
		hist.record(hist.sample_interval + 0.001, func() -> Dictionary: return _safe_fallback_state.duplicate(true))
	if _safe_snapshot_count < 16:
		_safe_snapshot_count = maxi(16, hist.snapshot_count - 2)


func _trigger_forced_depletion() -> void:
	if phase != Phase.STAGING or not is_instance_valid(_arena):
		return
	_ensure_minimum_safe_history()
	var director: Node3D = _arena.get("director") as Node3D
	if is_instance_valid(director) and director.get("projectiles") is Array:
		(director.get("projectiles") as Array).clear()
	var player: CombatPlayer = _arena.get("player") as CombatPlayer
	if is_instance_valid(player):
		player.wounded.emit(24.0)
	if "_damage_flash" in _arena:
		_arena.set("_damage_flash", 0.5)
	if "_injury_given" in _arena:
		_arena.set("_injury_given", true)

	var tc: TimeController = _arena.get("time_controller") as TimeController
	var er: EmergencyRewind = _arena.get("emergency_rewind") as EmergencyRewind
	tc.set_capabilities(tc.slow_unlocked, true)
	_entering_scrub = true
	phase = Phase.SCRUB
	var depleted := tc.force_depletion()
	if not depleted or not er.active:
		tc.begin_attempt()
		tc.force_depletion()
	_entering_scrub = false

	# Select the default safe earlier moment AFTER EmergencyRewind.begin() has
	# finished emitting both `started` and `selection_changed(0, 0.0, _present)`.
	if is_instance_valid(er) and er.active:
		er.min_selectable_index = _min_safe_index
		_adjusting_selection = true
		er.select(_default_safe_index)
		_adjusting_selection = false
	_sync_banner()


func _on_emergency_started(choice_count: int) -> void:
	if phase != Phase.SCRUB and not _entering_scrub:
		return
	phase = Phase.SCRUB
	var ev: EmergencyRewindView = _arena.get("emergency_view") as EmergencyRewindView
	if is_instance_valid(ev):
		ev.set_lesson_mode(true)
	var tut: Control = _arena.get("tutorial") as Control
	if is_instance_valid(tut):
		tut.hide()

	var hist: ReplayHistory = _arena.get("history") as ReplayHistory
	var total_recorded: int = hist.snapshot_count if hist != null else 0
	var unsafe_newest: int = maxi(0, total_recorded - _safe_snapshot_count)
	var max_idx: int = maxi(1, choice_count - 1)
	_min_safe_index = clampi(1 + unsafe_newest, 1, maxi(1, max_idx - 1))
	_default_safe_index = clampi(_min_safe_index + 1, _min_safe_index, maxi(_min_safe_index, max_idx - 1))
	var er: EmergencyRewind = _arena.get("emergency_rewind") as EmergencyRewind
	if is_instance_valid(er):
		er.min_selectable_index = _min_safe_index
	_sync_banner()


func _on_emergency_selection_changed(index: int, _age_seconds: float, _state: Dictionary) -> void:
	if phase != Phase.SCRUB or _adjusting_selection:
		return
	var tut: Control = _arena.get("tutorial") as Control
	if is_instance_valid(tut):
		tut.hide()
	var er: EmergencyRewind = _arena.get("emergency_rewind") as EmergencyRewind
	if is_instance_valid(er) and index < _min_safe_index and er.choice_count > _min_safe_index:
		_adjusting_selection = true
		er.select(_min_safe_index)
		_adjusting_selection = false


func _on_emergency_confirmed(_age_seconds: float, _state: Dictionary) -> void:
	if phase != Phase.SCRUB:
		return
	_confirmed_in_lesson = true
	if is_instance_valid(_arena) and "_suppress_enter_until_release" in _arena and bool(_arena.get("_suppress_enter_until_release")):
		_suppress_enter_until_release = true


func _on_emergency_ended() -> void:
	if phase != Phase.SCRUB:
		return
	if not _confirmed_in_lesson:
		cancel()
		return

	_finishing_completion = true
	_disconnect_arena_signals()
	phase = Phase.COMPLETED
	_completed_latch = true
	_completed_count += 1

	if is_instance_valid(_arena):
		var ev: EmergencyRewindView = _arena.get("emergency_view") as EmergencyRewindView
		if is_instance_valid(ev):
			ev.set_lesson_mode(false)

		_cleanup_staged_entities()
		var player: CombatPlayer = _arena.get("player") as CombatPlayer
		if is_instance_valid(player):
			if (player.position - _exposed_pos).length() < 0.35:
				player.position = _safe_origin
			player.reset_input()
			player.reset_physics_interpolation()
		_clear_live_inputs()
		var weapons: Node = _arena.get("weapons") as Node
		if is_instance_valid(weapons) and "require_fresh_press" in weapons:
			weapons.set("require_fresh_press", false)

		if "_rewound" in _arena:
			_arena.set("_rewound", true)
		if "_injury_given" in _arena:
			_arena.set("_injury_given", true)
		if "_rewind_unlocked" in _arena:
			_arena.set("_rewind_unlocked", true)

		# Fresh real-play attempt boundary: all 3 charges and full time meter.
		var tc: TimeController = _arena.get("time_controller") as TimeController
		if is_instance_valid(tc):
			tc.set_capabilities(tc.slow_unlocked, true)
			tc.begin_attempt()

		_sanitize_history_after_completion()
		if _arena.has_method("_update_hud"):
			_arena.call("_update_hud")

	_sync_banner()
	_finishing_completion = false
	completed.emit()


func _on_attempt_started() -> void:
	if _entering_scrub or _finishing_completion or _cancelling:
		return
	if active:
		cancel()


func _cleanup_staged_entities() -> void:
	if not is_instance_valid(_arena):
		return
	var director: Node3D = _arena.get("director") as Node3D
	if not is_instance_valid(director):
		return
	if director.get("projectiles") is Array:
		(director.get("projectiles") as Array).clear()
	var enemies_arr: Array = director.get("enemies") if director.get("enemies") is Array else []
	for enemy in _staged_enemies:
		if is_instance_valid(enemy):
			enemy.set("health", 0.0)
			if enemies_arr.has(enemy):
				enemies_arr.erase(enemy)
			enemy.queue_free()
	var remaining: Array = []
	for enemy in enemies_arr:
		if is_instance_valid(enemy) and int(enemy.get("rewind_id")) in _staged_enemy_ids:
			enemy.set("health", 0.0)
			enemy.queue_free()
		elif is_instance_valid(enemy):
			remaining.append(enemy)
	enemies_arr.assign(remaining)
	_staged_enemies.clear()


func _record_clean_history(dt: float) -> void:
	if not is_instance_valid(_arena):
		return
	var hist: ReplayHistory = _arena.get("history") as ReplayHistory
	if hist == null:
		return
	hist.record(dt, _capture_clean_snapshot)


func _capture_clean_snapshot() -> Dictionary:
	if not is_instance_valid(_arena) or not _arena.has_method("capture_state"):
		return {}
	var snap: Dictionary = _arena.call("capture_state")
	return _sanitize_snapshot_dict(snap, false)


func _sanitize_snapshot_dict(snap: Dictionary, remove_staged_enemies: bool) -> Dictionary:
	var copy := snap.duplicate(true)
	if copy.has("campaign_wave") and copy["campaign_wave"] is Dictionary:
		var cw: Dictionary = (copy["campaign_wave"] as Dictionary).duplicate(true)
		if cw.has("practice") and cw["practice"] is Dictionary:
			var prac: Dictionary = (cw["practice"] as Dictionary).duplicate(true)
			prac["injury_given"] = true
			prac["rewound"] = true
			cw["practice"] = prac
		copy["campaign_wave"] = cw
	if remove_staged_enemies and copy.has("director") and copy["director"] is Dictionary:
		var dir_data: Dictionary = (copy["director"] as Dictionary).duplicate(true)
		dir_data["projectiles"] = []
		if dir_data.has("enemies") and dir_data["enemies"] is Array:
			var kept: Array = []
			for entry in dir_data["enemies"]:
				if entry is Dictionary and not (int(entry.get("id", -1)) in _staged_enemy_ids):
					kept.append(entry)
			dir_data["enemies"] = kept
		copy["director"] = dir_data
	return copy


func _sanitize_history_after_completion() -> void:
	if not is_instance_valid(_arena):
		return
	var hist: ReplayHistory = _arena.get("history") as ReplayHistory
	if hist == null:
		return
	var count: int = hist.snapshot_count
	var sanitized_states: Array[Dictionary] = []
	for i in range(count):
		sanitized_states.append(_sanitize_snapshot_dict(hist.state_at(i), true))
	var current_clean := _sanitize_snapshot_dict(_arena.call("capture_state"), true)
	hist.clear()
	hist.seed_checkpoint(current_clean)
	for state in sanitized_states:
		hist.record(hist.sample_interval, func() -> Dictionary: return state)
	hist.push(current_clean)


func _clear_live_inputs() -> void:
	if not is_instance_valid(_arena):
		return
	var weapons: Node = _arena.get("weapons") as Node
	if is_instance_valid(weapons):
		if weapons.has_method("cancel_input"):
			weapons.call("cancel_input")
		if "mouse_held" in weapons:
			weapons.set("mouse_held", false)
	var player: CombatPlayer = _arena.get("player") as CombatPlayer
	if is_instance_valid(player):
		player.reset_input()
	if "_space_action_held" in _arena:
		_arena.set("_space_action_held", false)
	var tc: TimeController = _arena.get("time_controller") as TimeController
	if is_instance_valid(tc):
		tc.slow_requested = false


func _has_popup(key: StringName) -> bool:
	var tree := get_tree() if is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	if tree == null or tree.root == null:
		return false
	var sm: Node = tree.root.get_node_or_null("SceneManager")
	return sm != null and sm.has_method("has_popup") and bool(sm.call("has_popup", key))


func _is_interrupted_by_pause_or_modal() -> bool:
	var tree := get_tree() if is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	if tree != null and tree.root != null:
		var gs: Node = tree.root.get_node_or_null("GameState")
		if gs != null and gs.has_method("is_paused") and bool(gs.call("is_paused")):
			return true
	for key in [&"PauseMenu", &"Developer", &"Settings", &"RunResult"]:
		if _has_popup(key):
			return true
	return false


func _connect_arena_signals() -> void:
	_disconnect_arena_signals()
	if not is_instance_valid(_arena):
		return
	var er: EmergencyRewind = _arena.get("emergency_rewind") as EmergencyRewind
	if is_instance_valid(er):
		if not er.started.is_connected(_on_emergency_started):
			er.started.connect(_on_emergency_started)
		if not er.selection_changed.is_connected(_on_emergency_selection_changed):
			er.selection_changed.connect(_on_emergency_selection_changed)
		if not er.confirmed.is_connected(_on_emergency_confirmed):
			er.confirmed.connect(_on_emergency_confirmed)
		if not er.ended.is_connected(_on_emergency_ended):
			er.ended.connect(_on_emergency_ended)
	var tc: TimeController = _arena.get("time_controller") as TimeController
	if is_instance_valid(tc):
		if not tc.attempt_started.is_connected(_on_attempt_started):
			tc.attempt_started.connect(_on_attempt_started)


func _disconnect_arena_signals() -> void:
	if not is_instance_valid(_arena):
		return
	var er: EmergencyRewind = _arena.get("emergency_rewind") as EmergencyRewind
	if is_instance_valid(er):
		if er.started.is_connected(_on_emergency_started):
			er.started.disconnect(_on_emergency_started)
		if er.selection_changed.is_connected(_on_emergency_selection_changed):
			er.selection_changed.disconnect(_on_emergency_selection_changed)
		if er.confirmed.is_connected(_on_emergency_confirmed):
			er.confirmed.disconnect(_on_emergency_confirmed)
		if er.ended.is_connected(_on_emergency_ended):
			er.ended.disconnect(_on_emergency_ended)
	var tc: TimeController = _arena.get("time_controller") as TimeController
	if is_instance_valid(tc):
		if tc.attempt_started.is_connected(_on_attempt_started):
			tc.attempt_started.disconnect(_on_attempt_started)


func _style_banner() -> void:
	if banner == null:
		return
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.07, 0.09, 0.88)
	box.border_color = Color(ToolStyle.CLOCK, 0.5)
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 5
	box.content_margin_bottom = 6
	banner.add_theme_stylebox_override("panel", box)
	if is_instance_valid(skip_button):
		skip_button.focus_mode = Control.FOCUS_NONE
		skip_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS


func _fit_banner() -> void:
	if banner == null or not is_inside_tree():
		return
	var root_ctrl := banner.get_parent_control()
	if root_ctrl == null:
		return
	var factor := UI.scale_for(root_ctrl)
	for lbl in [title_label, action_label]:
		if is_instance_valid(lbl) and lbl.has_meta("base_font_size"):
			lbl.add_theme_font_size_override("font_size", roundi(float(lbl.get_meta("base_font_size")) * factor))
	if is_instance_valid(skip_button) and skip_button.has_meta("base_font_size"):
		skip_button.add_theme_font_size_override("font_size", roundi(float(skip_button.get_meta("base_font_size")) * factor))


func _sync_banner() -> void:
	if overlay == null:
		return
	overlay.visible = active
	if is_instance_valid(skip_button):
		skip_button.text = "Skip"
		skip_button.visible = active
		skip_button.disabled = not active
		skip_button.focus_mode = Control.FOCUS_NONE
		skip_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	if not active:
		return
	if is_instance_valid(title_label):
		title_label.text = "EMERGENCY REWIND"
	if is_instance_valid(action_label):
		if phase == Phase.STAGING:
			action_label.text = "Ambush incoming" if _ambush_spawned else "Watch the ambush"
		else:
			action_label.text = "Scroll earlier · press Enter"
