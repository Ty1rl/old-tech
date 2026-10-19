class_name CampaignDifficulty
extends Resource

const EASY_PATH := "res://scenes/prototype/settings/difficulty_easy.tres"
const HARD_PATH := "res://scenes/prototype/settings/difficulty_hard.tres"

@export var id: StringName = &"easy"
@export var title: String = "Easy"
@export var count_scale: float = 1.0
@export var count_bonus: int = 0
@export var burst_bonus: int = 0
@export var early_max_live: int = 5
@export var sustained_max_live: int = 6
@export var interval_scale: float = 1.0
@export var refill_delay_scale: float = 1.0
@export var recovery_scale: float = 1.0
@export var boss_escort_count: int = 6
@export var mixed_reinforcements: bool = false

@export_group("Enemy combat")
@export var enemy_damage_scale := 1.0
@export var attack_windup_scale := 1.0
@export var melee_reach_padding := 0.35
@export var aim_turn_scale := 1.0


static func load_for(difficulty: Variant = &"easy") -> CampaignDifficulty:
	if difficulty is CampaignDifficulty:
		return difficulty
	var key := String(difficulty).strip_edges().to_lower()
	var path := HARD_PATH if key == "hard" else EASY_PATH
	var loaded := load(path) as CampaignDifficulty
	assert(loaded != null, "Missing campaign difficulty resource: " + path)
	return loaded
