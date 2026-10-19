extends RefCounted

# Distances are world units; durations are real seconds unless stated otherwise.
const PLAYER = {"speed": 6.0, "visual_scale": 1.3, "tool_scale": 1.25}
const MOVEMENT = {"acceleration": 48.0, "braking": 80.0, "reversal": 72.0}
const VIEW = {"fov": 52.0, "camera_size": 22.0, "default_zoom": 18.0, "showcase_size": 18.0, "blue_assist_pixels": 22.0,
	"yellow_assist_pixels": 20.0}
# Actual inspector resources, also read by world geometry and aim helpers.
const RING = preload("res://scenes/weapons/settings/ring_cutter.tres")
const BEAM = preload("res://scenes/weapons/settings/focused_flash.tres")
const CONE = preload("res://scenes/weapons/settings/heat_bellows.tres")
const ENEMIES = {
	"ranged": {"health": 110.0, "speed": 1.35, "radius": 0.65, "damage": 10.0},
	"loop_boss": {"health": 840.0, "speed": 0.85, "radius": 1.45, "damage": 22.0, "mechanism": "pattern"},
	"sequence_boss": {"health": 780.0, "speed": 1.0, "radius": 1.4, "damage": 20.0, "mechanism": "pattern"},
	"loop": {"health": 300.0, "speed": 1.15, "radius": 1.0, "damage": 9.0},
	"zigzag": {"health": 300.0, "speed": 1.05, "radius": 1.15, "damage": 9.0},
	"pair": {"health": 240.0, "speed": 1.35, "radius": 1.0, "damage": 8.0},
	"final_boss": {"health": 1200.0, "speed": 0.8, "radius": 1.4, "damage": 15.0},
	"target": {"health": 100.0, "speed": 0.0, "radius": 0.7, "damage": 0.0},
	"swarmer": {"health": 32.0, "speed": 2.8, "radius": 0.4, "damage": 5.0},
	"brute": {"health": 180.0, "speed": 1.2, "radius": 1.0, "damage": 12.0},
	"skirmisher": {"health": 65.0, "speed": 3.2, "radius": 0.55, "damage": 7.0},
	"warden": {"health": 240.0, "speed": 1.3, "radius": 1.1, "damage": 12.0},
	"blue": {"health": 360.0, "speed": 2.1, "radius": 0.65, "damage": 7.0, "mechanism": "cut", "layout": "bridge"},
	"yellow": {"health": 300.0, "speed": 1.9, "radius": 0.65, "damage": 7.0, "mechanism": "shot", "layout": "front"},
	"orange": {"health": 400.0, "speed": 1.8, "radius": 0.7, "damage": 7.0, "mechanism": "heat", "layout": "front"},
	"side_guard": {"health": 500.0, "speed": 1.6, "radius": 0.8, "damage": 10.0, "mechanism": "open", "layout": "side"},
	"front_guard": {"health": 500.0, "speed": 1.6, "radius": 0.8, "damage": 10.0, "mechanism": "open", "layout": "front"},
}
# Pattern windows and attack timing use WORLD seconds.
# Partial links keep one fixed deadline across launches; repeated cuts cannot extend it.
const PATTERNS = {"window": 6.5, "pair_window": 2.4, "core_charge": 0.85,
	"body_armored": 0.12, "body_bare": 0.3, "windup": 0.8, "commit": 0.18,
	"recovery": 1.9, "boss_recovery_turn_rate": 1.5, "link_radius": 0.28, "target_radius": 0.40}
const MATCHUPS = {"body_damage": 0.12, "heat_seconds": 0.9, "heat_decay": 0.15,
	"cut_radius": 0.40, "core_radius": 0.38, "attack_windup": 0.35, "attack_recovery": 1.7, "attack_reach_padding": 0.35,
	"push_light": 1.25, "push_heavy": 0.15, "stagger_scale": 2.4}
# Slots follow a shrinking arc around the player; 0 strength restores direct chase.
const PACK = {"size": 5, "neighbor_range": 14.0, "spacing": 1.8,
	"strength": 0.85, "advance": 1.1, "separation": 0.7, "break_distance": 3.0}
# A fully charged 100-damage flash plus this bonus finishes a 240-health guard.
const PARTS = {"cable_bonus": 65.0, "core_bonus": 140.0, "core_min_charge": 0.6,
	"heat_threshold": 1.1, "heat_decay": 0.25, "open_seconds": 4.0,
	"cable_radius": 0.10, "core_radius": 0.28, "armor_multiplier": 0.35,
	"push_resistance": 0.25, "stagger_resistance": 0.8}
const ARMOR = {"front_multiplier": 0.25, "front_half_angle": 1.05}
const CONTACT_COOLDOWN = 1.0 # World seconds: time slow delays enemy attacks too.
const ARENA_HALF_SIZE = 20.0

# Weapon condition uses three tools only. Time tuning is scripts/time/time_settings.tres.
const GEAR = preload("res://scenes/weapons/settings/weapon_condition.tres")
# Enemy knockback resistance/drag; bellows pulse behavior is in its own resource.
const CONTROL = {"stagger": 0.85, "drag": 4.0,
	"brute_resistance": 0.4, "brute_stagger_resistance": 0.8}
const ENCOUNTER = {"duration": 75.0, "interval": 12.0, "max_enemies": 8}
