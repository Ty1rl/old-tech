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
knee and wrist surfaces blend across bones. Hair, pocket hardware and boot
soles retain their shapes through appropriate single-bone or limited blends.

Idle: two-second breathing loop. Walk: one-second in-place cycle at 30 fps,
with bent knees, a planted stance, lifted swing foot and restrained arm swing.
Starting travel-speed estimate: 0.76 m/s from the 0.38 m stance excursion over
half the cycle; jam-1 should tune animation playback against the game's speed.
RingHold, FlashHold, ConeHold, ClockHold: one-second constant holding clips.
post_import.gd marks all six clips LOOP_LINEAR on Godot import because glTF
does not standardize loop flags. Keep protagonist.glb.import with the asset.
No runtime IK, facial rig, finger bones, combat clips or root travel.

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
