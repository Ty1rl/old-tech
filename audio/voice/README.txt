SUPPLIED DIALOGUE — Some Assembly Required
37 original MP3 recordings supplied by Matt, 2026-10-19. Bytes unchanged.

EVENTS.tsv maps event IDs, relative filenames, suggested triggers and upload names.
Tutorial lesson filenames match the actual lesson keys:shot,charge,heat,repair,
slow,cut,opening,rewind,loop,pair,zigzag. Supplementary cues teach the meter,
charge budget,repair gestures,and practice handoff.
Protagonist filenames name both the event and the spoken variant. Rows sharing
an event ID are alternatives,not instructions to play both recordings.
Boss IDs use the actual enemy kinds:loop_boss,sequence_boss,final_boss.

Classification uses Matt's upload titles;spoken wording has not been transcribed
or verified. The Loop Curator file is assigned to its entrance by its supplied
boss title. No audio was trimmed,normalized,converted or given voice effects.

Runtime library:audio/voice/library.tres;playback:scripts/autoloads/audio_manager.gd.
Intro plays once on the title screen with Skip narration. Tutorials,repair gestures,
boss entrances and occasional protagonist reactions use actual gameplay events.
Only one voice plays at once;incidental speech has an 18-second cooldown.
Voice volume is separate in Settings. World/music duck while speech plays.
Voice stays at normal speed during time changes,with a lower boss register.
Scene exit cancels speech;history preview never starts or restores dialogue.
Menu/window quit drains native audio before closing.
