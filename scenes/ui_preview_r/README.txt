Round R / JAM-7 / base 25cf66f

Menu/Start emphasis, authored black NewGameIntro, and independent persisted Skip
tutorials checkbox. Production UI calls JAM-6's delivered audio API and JAM-5's
agreed start_play(false,difficulty,skip_tutorials). Only the assigned GameState
preference fields changed; no other owner's production file was edited.

Prepare disposable audio composition from signed JAM-6 e3d2d0c:
python3 scenes/prototype/checks/ui_r_prepare_audio.py
Real GameState/config and checkbox checks:
python3 /home/mattlongname/game-jams/projects/old-tech/check.py --seat jam-7 --suite ui_r_preferences --timeout 60
Story/audio lifetime checks using JAM-6's actual implementation:
python3 /home/mattlongname/game-jams/projects/old-tech/check.py --seat jam-7 --suite ui_r_story --timeout 60
Full transition/transport suite (requires JAM-5's real manager in composition):
python3 /home/mattlongname/game-jams/projects/old-tech/check.py --seat jam-7 --suite ui_r --timeout 60
Private normal/compact rendering:
python3 /home/mattlongname/game-jams/projects/old-tech/render.py --seat jam-7 --script res://scenes/ui_preview_r/capture.gd --name ui-r --timeout 60

Audio composition is explicit, bounded and outside the project. All AudioManager
function bodies are byte-identical to signed JAM-6 delivery; only its exported
library initializer/type is replaced with an injected actual library. The copied
library omits class_name to avoid the base global-type collision. Supplied MP3
bytes are unchanged. audio-composition.json records all source/copy SHA256 values.
The test child binds the existing Voice and a Music player, supplies the real
tracks, hides the old BASE scene's global Skip, intercepts Quit, and can queue
narration behind a real test clip. It does not replace speech lifetime, pause,
terminal events, or contextual music logic. No SceneManager transport stub exists.

Implementation/integration notes:
- NewGame disables the underlying scene and uses its existing popup stack for
  an authored black overlay. Campaign remains unconstructed during narration.
  SceneManager owns the existing black fade into gameplay after completion.
- Only an intentional New Game/Start says narration.intro. Menu entry, retry,
  continuing and encounter jumps do not request story. Fresh story bypasses the
  old app-once play_intro gate. Explicit Skip remains separate from Skip tutorials.
- Polls is_speaking (including queued speech) and listens to speech_finished;
  never awaits a potentially lost event. Missing/unavailable speech reaches ready.
- Uses native tree pause; JAM-6's delivered manager already handles it. No audio
  process-mode mutation or removed skip_intro field reference remains in UI.
  Native Settings stacks above the story, pauses it, and Back leaves it paused.
- Skip/Menu/Settings/Pause/Quit only act for the top popup after initial control
  release. Natural completion/Skip wait for all held controls before committing;
  teardown callbacks are disabled before start_play to avoid stopping new speech.
- GameState adds only skip_tutorials=false plus reload from the existing settings
  file. Checkbox remembers it, independent of Easy/Hard and tutorial hints.
  Start snapshots difficulty + flag through the story. JAM-4 owns consumption,
  acquisition order and skipping demonstrations/practice/tutorial-only encounters.
- Menu/intro semantic contexts delegate music entirely to JAM-6.

Remaining cross-seat verification:
JAM-5's inspected source still had the original two-argument start_play. ui_r
therefore reports an explicit missing-real-API prerequisite failure. It never
substitutes a transport implementation. Final ui_r_story reaches the genuine
held-input boundary; ui_r_preferences verifies real persistence/Start snapshot.
The prior 96-check pre-addendum pass is historical evidence only, not a final
transport claim. JAM-1 must test Easy/Hard x skip off/on after JAM-5/JAM-4 merge,
then run the final merged real-audio/music smoke check. Base-composition harnesses
are tied to this source/environment; do not silently reuse them on a merged tree.

Unowned Settings retains its preexisting MUSEUM AFTER HOURS eyebrow. Owned main
menu/New Game contain neither removed phrase. A global removal in other menus
needs the relevant owner's change.

Full logs, captures, failed attempts, composition manifest and verification receipt
are isolated in state/old-tech-jam-7/exports/round-r. Local signed delivery only.
