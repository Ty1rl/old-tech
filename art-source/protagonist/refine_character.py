"""Refine the existing authored .blend; never rebuild it from the trial generator.

Run using project blender.py. Settings in seat exports/character-upgrade/settings.json
select the bounded review iteration. Mesh edits are revision guarded. New manual
edits must be reviewed before applying a later revision or rebuilding animations.
"""
import bpy
import bmesh
import math
import json
import os
import sys
from pathlib import Path
from mathutils import Vector, Matrix
sys.dont_write_bytecode=True

REPO = Path(os.environ['JAM_REPO'])
STATE_ROOT = Path(os.environ['JAM_STATE_ROOT'])
OUT = STATE_ROOT / os.environ.get('JAM_EXPORT_SUBDIR', 'exports/round-j')
if not (OUT/'settings.json').exists() and (STATE_ROOT/'exports/character-upgrade/settings.json').exists():
    OUT = STATE_ROOT / 'exports/character-upgrade'
OUT.mkdir(parents=True, exist_ok=True)
SETTINGS = json.loads((OUT/'settings.json').read_text()) if (OUT/'settings.json').exists() else {'rig':True,'rebuild_rig':True,'iteration':1}
SOURCE = REPO/'art-source/protagonist/protagonist.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
bpy.context.preferences.filepaths.save_version=0
scene=bpy.context.scene
character=next(c for c in bpy.data.collections if c.name.startswith('PROTAGONIST |'))
studio=bpy.data.collections['REVIEW STUDIO | excluded from GLB']


def find(prefix):
    return next(ob for ob in character.objects if ob.name.startswith(prefix))


def apply(ob, mod):
    bpy.ops.object.select_all(action='DESELECT')
    ob.hide_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active=ob
    bpy.ops.object.modifier_apply(modifier=mod.name)


def smooth(ob, factor=.25, iterations=3):
    mod=ob.modifiers.new('Authoring surface relaxation','SMOOTH')
    mod.factor=factor
    mod.iterations=iterations
    apply(ob,mod)


def subdivide(ob, level=1):
    mod=ob.modifiers.new('Support loops for deformation','SUBSURF')
    mod.subdivision_type='CATMULL_CLARK'
    mod.levels=level
    apply(ob,mod)


def mesh(name, verts, faces, mat, smooth_normals=True):
    data=bpy.data.meshes.new(name)
    data.from_pydata(verts,[],faces)
    data.materials.append(mat)
    bm=bmesh.new(); bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(data); bm.free()
    ob=bpy.data.objects.new(name,data)
    character.objects.link(ob)
    for p in data.polygons: p.use_smooth=smooth_normals
    return ob


def tube(name, points, radii, mat, sides=10):
    rows=[]
    for j,point in enumerate(points):
        p=Vector(point)
        t=(Vector(points[min(j+1,len(points)-1)])-Vector(points[max(j-1,0)])).normalized()
        u=t.cross(Vector((0,1,0))).normalized()
        if u.length<.5: u=t.cross(Vector((1,0,0))).normalized()
        v=t.cross(u).normalized()
        rows.append([p+radii[j]*(u*math.cos(i*2*math.pi/sides)+v*math.sin(i*2*math.pi/sides)) for i in range(sides)])
    verts=[v for row in rows for v in row]
    faces=[(j*sides+i,j*sides+(i+1)%sides,(j+1)*sides+(i+1)%sides,(j+1)*sides+i)
           for j in range(len(rows)-1) for i in range(sides)]
    faces += [tuple(reversed(range(sides))),tuple(range((len(rows)-1)*sides,len(rows)*sides))]
    return mesh(name,verts,faces,mat)


if scene.get('character_mesh_revision',0)<1:
    # Keep the original head surface. Refine its cheek transition and lower jaw.
    head=find('Head |')
    for v in head.data.vertices:
        x,y,z=v.co
        jaw=math.exp(-.5*((z-1.560)/.035)**2)
        v.co.x *= 1-.055*jaw
        if y<.015:
            # Relax the old horizontal cheek shelf; preserve bridge and tip.
            v.co.y += .006*math.exp(-.5*((abs(x)-.065)/.023)**2)*math.exp(-.5*((z-1.649)/.017)**2)
    smooth(head,.16,2)

    # Replace only the small eye assemblies. The surrounding face stays intact.
    skin=bpy.data.materials['01 | warm skin']
    white=bpy.data.materials['08 | eyes and linen laces']
    iris=bpy.data.materials['05 | oxhide leather']
    dark=bpy.data.materials['06 | boot soles and recesses']
    for ob in list(character.objects):
        if ob.name.startswith(('Eye almond','Iris.','Pupil.','Upper eyelid','Lower eyelid')):
            bpy.data.objects.remove(ob,do_unlink=True)
    # Ray cast the original facial surface so eye corners stay in the sockets.
    def face_y(x,z):
        hit,location,normal,index=head.ray_cast(Vector((x,-1,z)),Vector((0,1,0)))
        return location.y if hit else -.07
    for s,label in [(1,'L'),(-1,'R')]:
        xc=s*.047
        center_y=face_y(xc,1.679)-.0055
        outline=[]
        for i in range(32):
            a=2*math.pi*i/32
            x=xc+.0205*math.cos(a)
            # Smaller exposed sclera, heavier upper lid, a very slight outer tilt.
            z=1.679+(.0048 if math.sin(a)>0 else .0052)*math.sin(a)+s*.045*(x-xc)
            outline.append((x,face_y(x,z)-.0017,z))
        verts=[(xc,center_y,1.679)]+outline
        mesh('Eye | inset almond.'+label,verts,[(0,i+1,(i+1)%32+1) for i in range(32)],white)
        # Iris is a curved patch flush with the eye, not a separate protruding ball.
        for name,radius,mat,offset in [('Iris',.0055,iris,.0005),('Pupil',.0026,dark,.001)]:
            verts=[(xc,center_y-offset,1.6785)]
            for i in range(24):
                a=2*math.pi*i/24
                dx=radius*math.cos(a); dz=radius*math.sin(a)
                # Match the eye fan's curved plane at the iris edge.
                ey=center_y+.0024*(dx/radius)**2+.0008*(dz/radius)**2
                verts.append((xc+dx,ey-offset,1.6785+dz))
            mesh(name+'.'+label,verts,[(0,i+1,(i+1)%24+1) for i in range(24)],mat)
        # Skin strips blend eyelids into the socket and cover the white edge.
        for upper,indices in [(True,range(17)),(False,range(16,33))]:
            inner=[Vector(outline[i%32]) for i in indices]
            outer=[]
            for p in inner:
                dx=p.x-xc
                q=p.copy()
                q.x=xc+dx*1.10
                q.z += (.004 if upper else -.0035)*math.sqrt(max(0,1-(dx/.021)**2))
                q.y=face_y(q.x,q.z)-.0003
                outer.append(q)
            verts=inner+outer
            n=len(inner)
            ob=mesh(('Upper lid.' if upper else 'Lower lid.')+label,verts,
                    [(i,i+1,n+i+1,n+i) for i in range(n-1)],skin)
            # Open skin strips deliberately face the review camera / -Y.
            bm=bmesh.new(); bm.from_mesh(ob.data)
            for f in bm.faces:
                if f.normal.y>0: f.normal_flip()
            bm.to_mesh(ob.data); bm.free()
        upper=[outline[i] for i in range(17)]
        tube('Upper lash.'+label,upper,[.00065]*len(upper),iris,5)
    for ob in character.objects:
        if ob.name.startswith('Brow.'):
            smooth(ob,.25,3)
            for v in ob.data.vertices:
                # Inner brow down slightly, outer brow up: focused, less vacant.
                if abs(v.co.x)<.035: v.co.z-=.0025

    # Round the existing hair masses while retaining their authored silhouettes.
    hair=find('Hair | swept')
    subdivide(hair)
    smooth(hair,.16,2)
    for p in hair.data.polygons: p.use_smooth=True

    # Subdivision adds real shoulder and elbow support, rather than rigid pieces.
    shirt=find('Shirt |')
    subdivide(shirt)
    for v in shirt.data.vertices:
        x,y,z=v.co
        # Shoulder slope and small tension folds below the armpits.
        if abs(x)>.12 and z>1.38: v.co.z-=.007*min(1,(abs(x)-.12)/.12)
        fold=math.exp(-.5*((z-1.27)/.035)**2)*math.exp(-.5*((abs(x)-.165)/.045)**2)
        v.co.y += .004*fold*math.sin((z-1.22)*95)
    for p in shirt.data.polygons: p.use_smooth=True
    trouser=find('Trousers |')
    # Relax the decimated surface first; split triangles once at flexing joints.
    smooth(trouser,.30,3)
    bm=bmesh.new(); bm.from_mesh(trouser.data)
    selected=[e for e in bm.edges if any(.46<v.co.z<.65 or .84<v.co.z<.97 for v in e.verts)]
    bmesh.ops.subdivide_edges(bm,edges=selected,cuts=1,use_grid_fill=True)
    bm.to_mesh(trouser.data); bm.free()
    smooth(trouser,.13,2)
    for v in trouser.data.vertices:
        x,y,z=v.co
        # Gentle accordion folds at the knee, subdued on the back.
        if .46<z<.65:
            f=.0035*math.sin((z-.46)*92)*math.sin(math.pi*(z-.46)/.19)**2
            v.co.y += f*(.6 if y>0 else 1)
    for p in trouser.data.polygons: p.use_smooth=True

    for label in ['L','R']:
        arm=find('Forearm.'+label)
        hand=find('Hand | relaxed fingers.'+label)
        smooth(hand,.30,5)
        # A broader palm and gently tapered fingers; soften the squared voxel tips.
        for v in hand.data.vertices:
            v.co.y=-.017+(v.co.y+.017)*1.12
        bpy.ops.object.select_all(action='DESELECT')
        arm.select_set(True); hand.select_set(True)
        bpy.context.view_layer.objects.active=arm
        bpy.ops.object.join()
        arm.name='Arm skin | connected wrist and hand.'+label
        remesh=arm.modifiers.new('Continuous wrist surface','REMESH')
        remesh.mode='VOXEL'; remesh.voxel_size=.0035
        apply(arm,remesh)
        smooth(arm,.22,3)
        dec=arm.modifiers.new('Retain silhouette and joint support','DECIMATE')
        dec.ratio=.27
        apply(arm,dec)
        for p in arm.data.polygons: p.use_smooth=True
    # Reduce and soften the two box-like hip pouches, keeping the signature sleeves.
    for ob in character.objects:
        if ob.name.startswith(('Hip pouch.','Pouch flap.','Pouch fastener.','Pouch stud.')):
            s=1 if ob.name.endswith('.L') else -1
            pivot=Vector((s*.209,-.012,1.023))
            for v in ob.data.vertices:
                d=v.co-pivot
                v.co=pivot+Vector((d.x*.82,d.y*.83,d.z*.84))
            if ob.name.startswith('Hip pouch.'):
                subdivide(ob)
                for p in ob.data.polygons: p.use_smooth=True
    # Small leather/canvas pieces remain faceted; main skin and cloth are selective smooth.
    scene['character_mesh_revision']=1
    character.name='PROTAGONIST | refined editable meshes'

if scene.get('character_mesh_revision',0)<2 and SETTINGS.get('iteration',1)>=2:
    # Match iris/pupil patches to the actual eye surface; no floating or crescent iris.
    for label in ['L','R']:
        eye=find('Eye | inset almond.'+label)
        xc=.047 if label=='L' else -.047
        for prefix,rx,rz,matname,depth in [
            ('Iris.',.0050,.0043,'05 | oxhide leather',.00035),
            ('Pupil.',.0022,.0033,'06 | boot soles and recesses',.00065)]:
            old=find(prefix+label); bpy.data.objects.remove(old,do_unlink=True)
            coords=[(xc,1.679)]+[(xc+rx*math.cos(i*2*math.pi/32),1.679+rz*math.sin(i*2*math.pi/32)) for i in range(32)]
            verts=[]
            for x,z in coords:
                hit,p,normal,index=eye.ray_cast(Vector((x,-1,z)),Vector((0,1,0)))
                if not hit: raise RuntimeError('Iris extends outside the eye surface')
                verts.append((x,p.y-depth,z))
            mesh(prefix+label,verts,[(0,i+1,(i+1)%32+1) for i in range(32)],bpy.data.materials[matname])
    # Smooth passes created redundant triangles on near-straight surfaces.
    for prefix,ratio in [('Arm skin |',.40),('Hair | swept',.60),('Trousers |',.80)]:
        for ob in [o for o in character.objects if o.name.startswith(prefix)]:
            mod=ob.modifiers.new('Keep useful shape, reduce redundant tessellation','DECIMATE')
            mod.ratio=ratio; apply(ob,mod)
    scene['character_mesh_revision']=2

rig=None
if SETTINGS.get('rig',True):
    sys.path.insert(0,str(REPO/'art-source/protagonist'))
    from rig_character import build_rig
    if SETTINGS.get('rebuild_rig',False):
        # Explicit iteration switch, never the default: retain authored mesh data.
        for ob in list(character.objects):
            if ob.type=='MESH':
                for mod in list(ob.modifiers):
                    if mod.type=='ARMATURE': ob.modifiers.remove(mod)
                ob.parent=None
            else: bpy.data.objects.remove(ob,do_unlink=True)
        props=bpy.data.collections.get('REVIEW PROPS | stand-ins only')
        if props:
            for ob in list(props.objects): bpy.data.objects.remove(ob,do_unlink=True)
            bpy.data.collections.remove(props)
        for action in list(bpy.data.actions):
            if action.name in ['Idle','Walk','Run','BackWalk','StrafeLeft','StrafeRight','RingHold','FlashHold','ConeHold','ClockHold']:
                bpy.data.actions.remove(action)
    rig=build_rig(character,OUT)

# Save the source with its original Blender orientation and all studio helpers hidden.
for ob in studio.objects: ob.hide_set(True)
review_props=bpy.data.collections.get('REVIEW PROPS | stand-ins only')
if review_props:
    for ob in review_props.objects: ob.hide_set(True)
scene.unit_settings.system='METRIC'
scene.unit_settings.scale_length=1
for ob in character.objects:
    ob['asset_stage']='refined simple rig' if rig else 'refined mesh review'
    if ob.type=='MESH': ob.hide_set(False)
scene.frame_set(1)
if rig:
    rig.animation_data.action=bpy.data.actions['Idle']
    scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))

# One common export pivot preserves skins, animation tracks and socket relationships.
bpy.ops.object.select_all(action='DESELECT')
if rig:
    rig.rotation_euler.z=math.pi
    for ob in character.objects: ob.select_set(True)
else:
    for ob in character.objects:
        ob.rotation_euler.z=math.pi
        ob.select_set(True)
bpy.context.view_layer.objects.active=rig or find('Head |')
bpy.context.view_layer.update()
bpy.ops.export_scene.gltf(filepath=str(REPO/'assets/characters/protagonist/protagonist.glb'),
    export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',
    export_extras=True,export_cameras=False,export_lights=False,
    export_animations=bool(rig),export_animation_mode='ACTIONS',
    export_force_sampling=True,export_frame_range=False,export_anim_slide_to_zero=True)
if rig: rig.rotation_euler.z=0
else:
    for ob in character.objects: ob.rotation_euler.z=0
bpy.context.view_layer.update()

# CPU review images. Preserve the first trial images under character-art/ untouched.
for ob in studio.objects: ob.hide_set(False)
scene.render.engine='CYCLES'
scene.cycles.device='CPU'; scene.cycles.samples=SETTINGS.get('samples',32)
scene.cycles.use_denoising=False
scene.render.threads_mode='FIXED'; scene.render.threads=4
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
camera=scene.camera
iteration=OUT/('iteration-%02d'%SETTINGS.get('iteration',1))
iteration.mkdir(parents=True,exist_ok=True)
for name in SETTINGS.get('render_views',['three-quarter','walk','walk-side','run','run-side','backwalk','legs-close','ring-hold']):
    scene.render.resolution_x=900
    scene.render.resolution_y=1100
    camera.data.ortho_scale=2.13
    target=Vector((0,0,.94)); camera.location=(3,-5,2.25)
    if rig:
        rig.animation_data.action=bpy.data.actions['Idle']
        scene.frame_set(1)
    if name=='portrait':
        scene.render.resolution_y=900; camera.data.ortho_scale=.57
        target=Vector((0,0,1.65)); camera.location=(2,-5,1.85)
    elif name=='front': camera.location=(0,-6,.94)
    elif name=='back': camera.location=(0,6,.94)
    elif name=='side': camera.location=(6,0,.94)
    elif name=='walk' and rig:
        rig.animation_data.action=bpy.data.actions['Walk']; scene.frame_set(1)
    elif name=='walk-side' and rig:
        rig.animation_data.action=bpy.data.actions['Walk']; scene.frame_set(1)
        camera.location=(5.5,-1.5,1.15); target=Vector((0,0,.88))
    elif name=='walk-swing' and rig:
        rig.animation_data.action=bpy.data.actions['Walk']; scene.frame_set(24)
        camera.location=(4.8,-2.5,1.05); target=Vector((0,0,.78)); camera.data.ortho_scale=1.65
    elif name=='run' and rig:
        rig.animation_data.action=bpy.data.actions['Run']; scene.frame_set(1)
    elif name=='run-side' and rig:
        rig.animation_data.action=bpy.data.actions['Run']; scene.frame_set(2)
        camera.location=(5.5,-1.5,1.15); target=Vector((0,0,.88))
    elif name=='backwalk' and rig:
        rig.animation_data.action=bpy.data.actions['BackWalk']; scene.frame_set(1)
        camera.location=(4.5,-3.5,1.65); target=Vector((0,0,.90))
    elif name=='legs-close' and rig:
        rig.animation_data.action=bpy.data.actions['Run']; scene.frame_set(16)
        scene.render.resolution_y=950; camera.data.ortho_scale=1.18
        target=Vector((0,-.04,.52)); camera.location=(3.8,-3.2,.82)
    elif name.endswith('-hold') and rig:
        action={'ring-hold':'RingHold','flash-hold':'FlashHold','cone-hold':'ConeHold','clock-hold':'ClockHold'}[name]
        rig.animation_data.action=bpy.data.actions[action]; scene.frame_set(1)
    for ob in bpy.data.collections.get('REVIEW PROPS | stand-ins only',[]).objects if bpy.data.collections.get('REVIEW PROPS | stand-ins only') else []:
        ob.hide_render=ob.get('hold_clip') != (action if name.endswith('-hold') else '')
    camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(iteration/(name+'.png'))
    bpy.ops.render.render(write_still=True)
    print('UPGRADE_RENDER',str(scene.render.filepath),flush=True)

vertices=triangles=0
used=set(); object_counts={}
for ob in character.objects:
    if ob.type!='MESH': continue
    ob.data.calc_loop_triangles()
    vertices+=len(ob.data.vertices); triangles+=len(ob.data.loop_triangles)
    object_counts[ob.name]=len(ob.data.loop_triangles)
    used.update(m.name for m in ob.data.materials)
stats={'mesh_objects':len(object_counts),'vertices':vertices,'triangles':triangles,
    'materials':len(used),'triangles_by_object':object_counts,'mesh_revision':scene.get('character_mesh_revision'),
    'rig_bones':len(rig.data.bones) if rig else 0,'clips':[a.name for a in bpy.data.actions] if rig else [],
    'first_pass_reference':str(OUT.parent/'character-art/verification.json')}
(iteration/'model-stats.json').write_text(json.dumps(stats,indent=2)+'\n')
(OUT/'model-stats.json').write_text(json.dumps(stats,indent=2)+'\n')
print('UPGRADE_STATS',json.dumps(stats),flush=True)
