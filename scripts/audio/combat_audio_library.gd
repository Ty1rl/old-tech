class_name CombatAudioLibrary
extends Resource
## Inspector palette. Streams/settings are shared and never modified by playback.
@export_group("Sound effects")
@export var cues: Array[CombatAudioCue] = []
@export_group("Music")
## Optional licensed compressed music. Null leaves a ready but silent music slot.
@export var music: AudioStream
@export_range(-50, -10, 0.5) var music_volume_db: float = -30.0
