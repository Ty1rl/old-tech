ROUND J — FIRST CREATURE FAMILY

Sources: patient.blend, conjoined.blend, bellows_belly.blend.
Exports: assets/enemies/{patient,conjoined,bellows_belly}.glb.
All geometry is editable, with named skin, linen, leather, cloth and mechanism
surfaces. Main anatomy uses shaped lofts and a single union pass. Targets are
separate scene nodes. No downloaded assets, textures or player-model reuse.

Patient: lean, hunched wrapped humanoid; long hands, chest drum and braced shin.
Conjoined: two related lean bodies of different stature; one bright blue span.
Bellows Belly: squat, broad torso and shoulders with a large orange cover.
These are the first three family assets; no six-creature behavior expansion.

Scale and axes
Metres; foot/root ground is zero. Body heights are approximately 1.7–1.84m.
No gameplay enlargement, collision shapes, stats or combat scripts are included.
Source Blender +Z up / -Y front; exported Godot +Y up / -Z front.
Attach the whole imported scene under the runtime facing pivot. Preserve its
imported EnemyRoot/skeleton transforms; do not reset internal root rotations.
The common Blender root is yawed 180 degrees only during explicit GLB export.

Parts / integration
Patient -> existing yellow / shot role. Hide YellowCore after its existing state
says it is broken. YellowCore is at (0,1.75,0), matching core_point(). The chest
drum feeds a raised spinal lens: this is a deliberate adaptation of the concept
to the current raised hit marker and overhead camera, not a relocated hit test.
The lens is flatter/smaller than the current 0.3m-radius placeholder sphere.

Conjoined -> existing blue / cut role. Hide BlueConnector when cut. Its centre
is (0,.85,0); CableStart=(-.4,.85,0), CableEnd=(+.4,.85,0), matching the bridge
points exactly. The hose radius is .125–.13m rather than the placeholder .19m;
existing ring assist/hit logic remains authoritative. A_* and B_* mesh prefixes
identify the two bodies; their corresponding bones have A. and B. prefixes.
Death separation/tilting is not implemented in this asset pass.

Bellows Belly -> existing orange / heat role. Hide OrangePlate as a whole when
its state is removed. Its root is (0,.12,-.95), matching the radius-.7 plate
placement. The front envelope is 1.435m wide and 1.0m tall. The oval cover and
upper mantle extend beyond the simple front rectangle for overhead readability;
keep current cone/heat logic, not mesh-surface hit tests. No hidden yellow core
is added to the heat-only creature. Metal cover braces are children of the part
and disappear with it; body standoffs remain with the body.

Exact anchors, model counts and art/placeholder differences are recorded in
assets/enemies/part_contract.json. All three target groups remain fixed relative
to EnemyRoot while the body deforms, preserving the existing hit-marker positions.

Simple rig
Patient and Bellows Belly: 18 bones each. Conjoined: one 35-bone skeleton.
root > A.pelvis > A.spine > A.chest > A.neck > A.head.
A.chest > A.upper_arm.L/R > A.forearm.L/R > A.hand.L/R.
A.pelvis > A.thigh.L/R > A.shin.L/R > A.foot.L/R.
Conjoined repeats the hierarchy with B. under the same root.
Idle is a two-second subtle body cycle. Walk is a 1.2-second in-place shuffle,
with planted/swing feet, gentle arm motion and no forward root travel. Nominal
unscaled stance travel is .21m per .6s, approximately .35m/s; tune playback with
runtime speed after review. No facial/finger rig, attack library or runtime IK.
Use jam-1's existing animation/time clock, not another independent process.

Authoring and preservation
build_family.py and family_rig.py preserve the editable construction recipe.
Run only through project blender.py. Existing .blend files are explicitly opened
before refinement. An existing rig causes a refusal before saving: review manual
edits rather than rebuilding over them. Do not bypass that guard over another
person's hand edits. The .gdignore excludes source files from automatic Godot
import; GLB export remains explicit. Source REVIEW collections do not export.
assets/enemies/post_import.gd marks Idle/Walk looping and the target materials
unshaded on import, matching the colored-part rendering convention. Keep the
three .glb.import files with that hook.

Evidence / limits
Own state/exports/round-j/review.html: Patient before/after, final family views,
current ortho22/-55degree/1280x800 views, captured walk cycle, four facings per
creature and removed-part views. Verification and full-log paths are alongside.
Two focused design passes were followed by bounded deformation/bind repairs.
These are stylized first family models: simplified faces and fixed fingers,
some cloth/wrist/shoulder compression, triangulated anatomy and no texture pass.
The larger silhouettes can extend beyond current collision radii; those radii
and all combat behavior were deliberately left unchanged. Final art review,
animation-speed tuning, collision/readability judgment and integration belong
to jam-1. No protagonist, equipment, museum or gameplay file is edited here.
