extends RefCounted

# Distances are world units; durations are real seconds unless stated otherwise.
const PLAYER = {"speed": 6.0, "health": 100.0, "visual_scale": 1.3}
const VIEW = {"camera_size": 22.0, "showcase_size": 18.0, "blue_assist_pixels": 22.0,
	"yellow_assist_pixels": 20.0}
const SLOW = {"scale": 0.18, "drain": 1.0}
const RING = {"range": 14.0, "length": 22.0, "minimum_length": 0.6,
	"sample_spacing": 0.18, "outbound_speed": 24.0, "stroke_speed": 38.0,
	"return_speed": 28.0, "radius": 0.4, "damage": 36.0, "arc_height": 3.2}
const BEAM = {"range": 35.0, "radius": 0.35, "min_damage": 30.0, "max_damage": 100.0,
	"charge_time": 0.9, "speed": 42.0, "cooldown": 0.25, "max_pulses": 8}
const CONE = {"range": 5.0, "half_angle": 0.65, "damage_per_second": 16.0}
const ENEMIES = {
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
const MATCHUPS = {"body_damage": 0.12, "heat_seconds": 0.9, "heat_decay": 0.15,
	"cut_radius": 0.28, "core_radius": 0.38, "attack_windup": 0.5, "attack_recovery": 1.7,
	"push_light": 1.25, "push_heavy": 0.15, "stagger_scale": 2.4}
# Slots follow a shrinking arc around the player; 0 strength restores direct chase.
const PACK = {"size": 5, "neighbor_range": 14.0, "spacing": 1.8,
	"strength": 0.85, "advance": 1.1, "separation": 0.3, "break_distance": 3.0}
# A fully charged 100-damage flash plus this bonus finishes a 240-health guard.
const PARTS = {"cable_bonus": 65.0, "core_bonus": 140.0, "core_min_charge": 0.6,
	"heat_threshold": 1.1, "heat_decay": 0.25, "open_seconds": 4.0,
	"cable_radius": 0.10, "core_radius": 0.28, "armor_multiplier": 0.35,
	"push_resistance": 0.25, "stagger_resistance": 0.8}
const ARMOR = {"front_multiplier": 0.25, "front_half_angle": 1.05}
const CONTACT_COOLDOWN = 1.0 # World seconds: time slow delays enemy attacks too.
const ARENA_HALF_SIZE = 20.0

# Generous first-pass service intervals, measured in actual use, not wall time.
const GEAR = {
	"ring": {"capacity": 32.0, "unit": "launches"},
	"beam": {"capacity": 48.0, "unit": "shots"},
	"cone": {"capacity": 45.0, "unit": "seconds"},
	"clock": {"capacity": 24.0, "unit": "seconds"},
}
const REPAIR_STEPS = 4
const CONTROL = {"pulse_interval": 1.2, "pulse_cost": 1.5, "pulse_impulse": 22.0,
	"pulse_stagger": 0.85, "stagger": 0.85, "sustained_push": 5.0, "drag": 4.0,
	"brute_resistance": 0.4, "brute_stagger_resistance": 0.8}
# Costs use real elapsed inspection time and actual seconds rewound.
const REWIND = {"browse_drain": 0.2, "jump_cost": 1.0, "scroll_step": 0.25}
const ENCOUNTER = {"duration": 75.0, "interval": 12.0, "max_enemies": 8}
