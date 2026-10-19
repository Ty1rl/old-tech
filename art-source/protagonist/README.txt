PROTAGONIST — REFINED MESH AND SIMPLE RIG

Authored source: protagonist.blend. Export: assets/characters/protagonist/protagonist.glb.
This continues ca86a0b; original silhouette, bun, sleeves, harness and boots retained.
The file opens in a breathing Idle pose. Mesh data remains editable in its A-pose;
use the armature Rest Position switch when editing the bind mesh.

Pipeline and edit preservation
refine_character.py explicitly opens protagonist.blend and applies guarded mesh
revisions. rig_character.py authors weights and baked bone clips. It refuses to
replace an existing rig by default. The explicit rebuild_rig iteration setting is
for the current authoring session only, never for overwriting another person's edits.
Review any manual changes before rebuilding weights or animation curves.
build_character.py is the archived first-trial generator; it refuses to overwrite
an existing authored source. Do not run it over this model.

Run through project blender.py, not desktop Blender or a network add-on:
python3 ~/game-jams/projects/old-tech/blender.py --seat jam-5 --script /absolute/path/to/refine_character.py --name character-upgrade --timeout 480
Settings and render output: own state/exports/character-upgrade/.
The existing .gdignore keeps all Blender source files out of Godot imports.

Rig and clips
One armature, 20 bones; 19 deform bones plus root. Ordinary linear skinning.
Hierarchy: root > pelvis > spine > chest > neck > head.
chest > clavicle.L/R > upper_arm.L/R > forearm.L/R > hand.L/R.
pelvis > thigh.L/R > shin.L/R > foot.L/R.
All 80 mesh parts have normalized skin weights; torso, shoulder, elbow, hip,
knee, ankle and wrist surfaces blend across bones. In Round J (jam-2), lower-body
weights were refined so Trousers and Shaped knee share a wider, cohesive knee
blend (eliminating knee patch separation), inner-thigh/crotch vertices soften into
pelvis during wide strides, and Trouser turnup cuffs match the lower shin/ankle
blend while Boot shafts blend smoothly from rigid soles (100% foot.L/R) into
shin.L/R (eliminating cuff compression and ankle shearing).

Locomotion & Hold Clips (all marked Animation.LOOP_LINEAR by post_import.gd):
- Idle (2.0 s, frames 1..61 at 30 fps): subtle breathing loop.
- Walk (1.0 s, frames 1..31 at 30 fps): in-place walk with heel-to-toe planted
  stance contact, swing knee lift, and natural counter-rotation.
  * Unscaled stride: 0.56 m per-foot stance excursion = 1.12 m full cycle (1.12 m/s at 1.0x).
  * At 1.3x runtime visual scale: 1.456 m full cycle (1.456 m/s at 1.0x; ~1.35x playback rate for ~2.0 m/s walk).
- Run (0.6667 s, frames 1..21 at 30 fps): energetic in-place run with forward
  torso lean, opposite-arm drive, planted contact, and high swing knee/heel recovery.
  * Unscaled stride: 0.76 m per-foot excursion = 1.52 m full cycle (2.28 m/s at 1.0x).
  * At 1.3x runtime visual scale: 1.976 m (~2.0 m) full cycle (2.964 m/s at 1.0x).
  * Recommended playback rate at 6.0 m/s gameplay speed: ~2.0x (avoids running Walk at 6 cycles/s).
- BackWalk (1.0 s, frames 1..31 at 30 fps): dedicated backward gait loop with
  toe-first rear reach and grounded draw-back stance.
  * Unscaled stride: 0.48 m per-foot excursion = 0.96 m full cycle (1.248 m at 1.3x scale; ~1.5x playback rate).
- RingHold, FlashHold, ConeHold, ClockHold (1.0 s, frames 1..31): static equipment
  holding poses preserving the exact Grip_R / Grip_L socket contract.
Keep protagonist.glb.import with the asset. No runtime IK or root motion.

Attachment contract
Blender: metres, +Z up / -Y front; feet/common root on the ground.
Export yaw: rotate the common armature +180 degrees around Blender Z, then
export selected armature, skinned children and both sockets with Y-up conversion.
Restore the source yaw afterwards; do not apply transforms to individual limbs.
The exported character faces Godot -Z with +Y up and unit scale.

Grip_R is bone-parented to hand.R; Grip_L is bone-parented to hand.L. In each
holding pose their exported bases match the character root (identity relative
rotation). Parent a prop root under Grip_R at identity. Its Grip_L guides the
support hand. Runtime attachment and IK belong to jam-1.
Source socket axes include a compensating yaw; do not remove it when exporting.
Exact bone names and measured Godot socket transforms are in
assets/characters/protagonist/rig_contract.json. Holding grip positions in metres:
             Grip_R (x,y,z)          Grip_L (x,y,z)
RingHold     (+.115,1.170,-.310)      (-.130,1.170,-.440)
FlashHold    (+.150,1.210,-.320)      (-.150,1.210,-.360)
ConeHold     (+.115,1.160,-.290)      (-.115,1.190,-.440)
ClockHold    (+.105,1.160,-.270)      (-.105,1.160,-.290)

Review helpers and limits
REVIEW STUDIO and REVIEW PROPS are excluded from the GLB. The four crude prop
stand-ins demonstrate hand spacing; they are not final equipment assets.
The source retains a stylized face, simplified fingers, triangulated limb/cloth
surfaces and some knee/cuff compression. It is a simple deforming game rig,
not an anatomical or facial animation system. Actual tool handles need final
pose/finger fitting during integration. 80 mesh parts remain a draw-call cost;
selective consolidation can follow art approval without discarding editable source.

Visual evidence, before/after references, captured loops and verification:
state/exports/character-upgrade/review.html and verification.json.
Godot review: project render.py --seat jam-5 --script res://scenes/art_preview/upgrade_capture.gd --name character-upgrade --timeout 90
The preview uses the current ortho-22 / -55-degree / 1280x800 camera contract,
in an isolated stage. No playable prototype file is changed or integrated here.
