extends RefCounted

# Distances are world units; durations are real seconds unless stated otherwise.
const PLAYER = {"speed": 6.0, "health": 100.0}
const SLOW = {"scale": 0.18, "capacity": 5.0, "drain": 1.0, "regeneration": 0.6}
const RING = {"range": 14.0, "length": 22.0, "minimum_length": 0.6,
	"sample_spacing": 0.18, "outbound_speed": 24.0, "stroke_speed": 38.0,
	"return_speed": 28.0, "radius": 0.4, "damage": 36.0}
const BEAM = {"range": 18.0, "radius": 0.35, "damage": 28.0, "cooldown": 0.25}
const CONE = {"range": 5.0, "half_angle": 0.65, "damage_per_second": 24.0}
const ENEMIES = {
	"target": {"health": 100.0, "speed": 0.0, "radius": 0.7, "damage": 0.0},
	"swarmer": {"health": 32.0, "speed": 2.8, "radius": 0.4, "damage": 5.0},
	"brute": {"health": 180.0, "speed": 1.2, "radius": 1.0, "damage": 12.0},
	"skirmisher": {"health": 65.0, "speed": 3.2, "radius": 0.55, "damage": 7.0},
}
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
const CONTROL = {"burst_interval": 1.5, "burst_cost": 1.5, "impulse": 13.0, "stagger": 0.65,
	"sustained_push": 5.0, "drag": 5.0, "brute_resistance": 0.25}
const ENCOUNTER = {"duration": 75.0, "interval": 12.0, "max_enemies": 6}
