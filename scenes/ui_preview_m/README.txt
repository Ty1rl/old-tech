ROUND M — JAM-7 MENUS / HUD

Branch starts at signed 7b02642. Owned changes only: status_hud.gd and the
existing menu/settings/pause/result/encounter/ui_style scripts. Arena, campaign,
repair controls, equipment, input and autoload source are unchanged.

Player-facing result
  The warm museum remains the main menu backdrop. Main controls gain a clear
  ivory/brass selection, readable small-window sizing, and scroll-to-focus.
  Popup titles and descriptions remain fixed while the controls below scroll.
  The museum remains visible behind popup panels; the panel text stays opaque.
  Keyboard Tab/Shift-Tab and controller D-pad navigation have explicit paths.
  Settings keep the existing saved preference files and pause/menu return flow.
  Closing and immediately reopening a popup cannot leave focus behind it.

  All four gear arcs remain. Locked tracks are neutral and have no low-wear dot;
  the acquired selected arc has a stronger outline. Full / damaged / empty gear
  gets concise local text. The ivory health arc and actual damage pulse remain.
  Cursor charge and the rewind-only timeline remain responsive. UI geometry and
  type scale for the small window; the secondary color legend yields space to
  campaign feedback there. Hint strings only change when sound/developer state
  changes. HUD projection still updates every rendered frame.

  Repair copy says E toggle/close; Space is described as manual slow. Encounter
  select remains behind SceneManager.developer_tools, including a guard inside
  the picker. Actual room/phase parameters and checkpoint equipment are retained.

Lifecycle / performance
  Deferred initial focus uses weak references and checks the current popup.
  One bounded follow-up after two frames reconciles old popup focus restoration.
  It does not reset navigation within the new popup and does not poll forever.
  Existing shell resize callbacks keep weak references. Layout font overrides
  now change only when the size actually changes; main layout ignores unchanged
  viewport size/scale. Native font measurement is retained after measurement.
  The headless probe is a microbenchmark of grouped HUD update/hint/timeline calls,
  not a full-game FPS claim. Raw samples and the discarded width-cache trial are
  retained in the seat's round-m evidence.

Focused verification (from repo root)
  python3 ../../../check.py --seat jam-7 --suite import
  python3 ../../../check.py --seat jam-7 --suite ui_m
  python3 ../../../check.py --seat jam-7 --suite menus_l
  python3 ../../../check.py --seat jam-7 --suite presentation_j
  python3 ../../../check.py --seat jam-7 --suite hud_profile_m
  python3 ../../../render.py --seat jam-7 \
    --script res://scenes/ui_preview_m/capture.gd --name ui-m-final --timeout 60

The capture/profile phase name comes from own state/exports/round-m/phase.txt.
Before, initial and final captures are preserved separately. The graphical runner
uses only project render.py/private Xvfb. Captures use actual campaign perspective,
room models and HUD data with combat stepping disabled for repeatable UI review.
Some condition/charge/timeline values are explicit display fixtures, not a full
combat or rewind playtest. ui_m also exercises a live final-boss phase/loadout,
actual player damage, actual GUI/controller input and real menu transitions.

Integration with other Round M delegates
  Jam-3 owns the actual E-toggle/manual-Space behavior. This seat changes the UI
  copy only; the isolated 7b02642 arena still implements the old hold-E behavior.
  Its diagnostic header still says Hold E (arena.gd), which Jam-3 must update.
  Arena._update_hud() also hides status_hud during repair. That existing visibility
  policy is not overridden here: Jam-3/Jam-1 decide whether the repaired view should
  expose local arcs underneath the large transparent repair UI. Caption support
  for full/damaged gear while repairing is ready on this branch.
  No three-boss, acquisition, checkpoint, projectile, wear or rewind policy changes.
