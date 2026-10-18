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
@export var boss_escort_count: int = 2
@export var mixed_reinforcements: bool = false


static func load_for(difficulty: Variant = &"easy") -> CampaignDifficulty:
	if difficulty is CampaignDifficulty:
		return difficulty
	var key := String(difficulty).strip_edges().to_lower()
	var path := HARD_PATH if key == "hard" else EASY_PATH
	var loaded := load(path) as CampaignDifficulty
	if loaded != null:
		return loaded
	var fallback := CampaignDifficulty.new()
	if key == "hard":
		fallback.id = &"hard"
		fallback.title = "Hard"
		fallback.count_scale = 1.35
		fallback.count_bonus = 2
		fallback.burst_bonus = 1
		fallback.early_max_live = 8
		fallback.sustained_max_live = 11
		fallback.interval_scale = 0.82
		fallback.refill_delay_scale = 0.72
		fallback.recovery_scale = 0.88
		fallback.boss_escort_count = 4
		fallback.mixed_reinforcements = true
	return fallback
