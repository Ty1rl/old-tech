Scene loading

SceneManager.start_play(sandbox=false, difficulty=&"easy", skip_tutorials=false)
passes the selected run settings to the campaign after the intro completes.

The loading panel appears before dependency loading. The manager loads hints
leaf-first on the main thread, yielding after an 8 ms slice. A single resource
load remains indivisible. Cached root scenes bypass the hint sweep. Retained
references keep resources available until the destination scene owns them.

resource_steps.gd contains hints for campaign and sandbox. Regenerate it with
build_resource_steps.py after substantial dependency changes. Missing hints are
skipped; the final root load still resolves its actual dependencies.

cancel_transition() accepts cancellation before commit and restores scene
processing, params, GameState and initiating focus. Load failures show Back.
At commit, SceneTree swaps scenes and disposes the outgoing scene. The new scene
resumes after the existing fade. Popups and outgoing speech are cleared during
this transition; stale terminal callbacks cannot start another campaign.

last_transition_profile records resource loading, instantiation, scene swap,
first draw and fades. It is diagnostic data, not a gameplay clock.

Focused checks in scenes/prototype/checks/: startup_r, startup_profile_r,
startup_shutdown_r. Checks must await is_transitioning() with a bounded timeout
rather than assume a fixed frame count.
