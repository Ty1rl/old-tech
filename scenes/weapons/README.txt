Weapon scenes

Open scenes/weapons/weapons.tscn. Its named children are the real RingCutter,
FocusedFlash and HeatBellows implementations; Presentation is shared light/air.
WeaponController (scenes/prototype/weapons.gd) coordinates equip/input and signals.
No child composition is deleted/recreated in _ready. Procedural guide/air/light
meshes remain dynamic because they follow raw strokes and projectile flight.

CONCRETE EDIT EXAMPLE
Open ring_cutter.tscn, select RingCutter, expand Settings. Change stroke_speed
from 38 to 19 in settings/ring_cutter.tres. The actual flight takes twice as long;
the flash and bellows scripts require no change. For one scene variation, make
Settings unique and save it as a new .tres. Resource values are read-only during
play: flight, pulses, ledgers and condition are stored on their own actor instances.
The focused check verifies 0.38m travel in 0.02s with the edited 19m/s resource.

FocusedFlash's resource owns charge/cooldown/piercing/projectile tuning.
HeatBellows's resource owns heat/pulse/displacement tuning. Condition resource
owns ring/beam/cone capacity and repair checkpoint count. Tuning.RING/BEAM/CONE
preload those same default resources for world geometry/aim consumers; no duplicate
weapon-number dictionaries or fallback ladders remain. Time tuning is exclusively
scripts/time/time_settings.tres; weapons never create or advance a time authority.

MANUAL BENCH
Run scenes/weapons/preview.tscn manually. 1/2/3 select; mouse draws/charges/blows;
Space manually slows through the one TimeController. R resets targets/conditions.
V saves and B restores world/weapon values. Time meter/charges are never restored.
Targets are stationary contact fixtures. Use a private virtual display for
automated pictures.

COMPOSITION
The arena binds the same equipment and time controller to the weapons and HUD:
  var weapons: WeaponController = preload("res://scenes/weapons/weapons.tscn").instantiate()
  var equipment := WeaponEquipment.new(weapons.condition_settings)
  weapons.equipment = equipment
  weapons.cover = cover
  weapons.time_controller = time_controller # arena's existing ONE authority
  add_child(weapons)
Use the same equipment reference in repair/campaign/HUD. No selectable clock4.
No Tuning.PLAYER.health, SLOW, REWIND, dictionary GEAR, or REPAIR_STEPS remains.
Use equipment.repair_steps and TimeController/TimeSettings for those duties.

Controller lifecycle is retained: set_loadout/select_tool, handle_event/step,
cancel_input/reset_state, capture_state/restore_state, presentation_state,
selected_tool/available_tools, resolved_hit and combat_event. Input owner handles
Tab, repair, emergency choice, Space and pause. Controller immediately cancels
held actions on emergency/exhaustion signals, including when the arena skips
stepping while frozen. It handles three number keys/mouse actions. It refuses invalid IDs and filters invalid/duplicate loadouts.

HUD should read presentation_state() for tool/charging/charge/ready/air/phase.
Detailed behavior state belongs to the concrete children, without mirrored aliases:
  ring.drawing, preview_points, preview_length, preview_blocked, flight_phase,
       head, flight_points, stroke_index, hit_ids, settings
  flash.charging, charge, cooldown, pulses, flash_timer, settings.pierce_threshold
  bellows.active, pulse_cooldown, forward, settings
Rebuild display with rebuild_visuals(player), not the retired private helper.
Player visual is a Node3D adapter boundary. Components receive concrete origins/muzzles;
none reads player health, slow charge or visual internals. Contacts use the actual
enemy receive_attack/combat_id/attack_radius/has_cuttable_part/apply_control API.

Capture shape is {ring, flash, bellows, overlay, selected_tool, phase, last_aim,
last_feedback}; nested dictionaries hold value-only world state. Overlay shape
is unchanged. No acquired tools, training policy, settings or time/charges enter
weapon snapshots. Restore cancels held input; only existing flight resumes.
Ring point count, pulse count and stable hit ledgers retain explicit bounds.
Equipment keeps condition/session/stage/complete_step/repaired and training policy;
repair owner must pay try_spend_repair_checkpoint BEFORE calling complete_step.

Pass real delta and the already-scaled world delta to step. When omitted, world
delta reads the bound TimeController.world_scale. An emergency/exhaustion rejects
input and freezes flight/wear/cooldowns even if a caller accidentally passes positive
deltas. Idle visuals have no independent simulation tick. Normal charging/cooldown/
condition use real time; flight/heat/shoves/pulse cadence use world time.

CHECKS
Project check.py --seat jam-5 --suite weapons / equipment / weapon_components_n /
weapon_presentation / weapon_smoothing_n. Existing display_smoothing_m also passes.
weapon_smoothing_n runs independently; optional N1 timing comparison uses the saved
baseline source in the receipt's baseline/ folder. To recreate that evidence:
  git show 8b38209:scenes/prototype/weapon_presentation.gd > <receipt>/baseline/weapon_presentation.gd
Functional checks never require the saved baseline. Open-floor smoothing performs
zero expensive cover sweeps; raw points, deliberate turns and wall safety stay exact.

Private review script: scenes/weapons/capture.gd via render.py. Images/logs/receipt:
state/old-tech-jam-5/exports/round-n-wave2/. Mixed-consumer integration belongs to jam-1;
legacy arena/player/repair/HUD tests still require their owners' Wave 2 changes.
