class_name CombatAudioCue
extends Resource
## One editable sound: the bank owns content, feedback owns live playback state.
@export var id: StringName
@export var stream: AudioStream
@export_range(-40, 0, 0.5) var volume_db: float = -12.0
@export_range(0, 5, 1) var priority: int = 2
@export var responsive: bool = false
@export_range(0, 2, 0.01) var cooldown: float = 0.08
@export_range(0.5, 2, 0.01) var pitch: float = 1.0
@export var looping: bool = false
@export var effect: StringName
