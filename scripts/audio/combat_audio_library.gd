class_name CombatAudioLibrary
extends Resource
## Inspector palette. Streams/settings are shared and never modified by playback.
@export_group("Sound effects")
@export var cues: Array[CombatAudioCue] = []
@export_group("Music")
## Context streams are played only by AudioManager. Intro intentionally has none.
@export var music_tracks: Dictionary[StringName, AudioStream] = {}
@export_range(-50, -10, 0.5) var music_volume_db: float = -30.0
