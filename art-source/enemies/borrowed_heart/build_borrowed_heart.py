"""Borrowed Heart: three bounded authoring passes; no runtime/gameplay dependencies.
Run via project blender.py. Set own state exports/round-j/pass.txt to 1,2,3.
The default rebuild is the final pass (3). All units are metres.
"""
import bpy, math, os, json, random
from pathlib import Path
from mathutils import Vector, Matrix
ROOT=Path(os.environ.get('JAM_REPO',Path.cwd()))
OUT=Path(os.environ['JAM_STATE_ROOT'])/'exports/round-j'
PASS=int((OUT/'pass.txt').read_text()) if (OUT/'pass.txt').exists() else 3
random.seed(707)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for data in list(bpy.data.materials): bpy.data.materials.remove(data)
parts={}; weights={}

def mat(name,color,metal=0,rough=.8,emit=0):
    color=tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in color)
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
    if emit: p.inputs['Emission Color'].default_value=(*color,1); p.inputs['Emission Strength'].default_value=emit
    return m
skin=mat('01 | Ashen warm skin',(.43,.375,.335))
skinlight=mat('02 | Raised skin planes',(.51,.45,.40))
cloth=mat('03 | Stained linen',(.56,.48,.36))
edge=mat('04 | Linen worn edges',(.70,.61,.47))
dark=mat('05 | Creases and gaskets',(.055,.042,.033))
leather=mat('06 | Oxblood leather',(.16,.085,.042))
steel=mat('07 | Oxidised iron',(.22,.235,.22),.65,.56)
brass=mat('08 | Aged brass rivets',(.40,.28,.13),.65,.54)
orange=mat('09 | Heat covering orange',(.93,.48,.16),.25,.48)
chip=mat('10 | Exposed plate edges',(.35,.21,.09),.6,.6)
blue=mat('11 | Cut conduit blue',(.025,.26,.95),.15,.38,.18)
bluehi=mat('12 | Conduit bands',(.055,.53,1),.2,.4,.10)
yellow=mat('13 | Exposed core yellow',(1,.66,.015),.2,.35,.35)

def record(o,name,m,bone,group='Body'):
    o.name=name; o.data.materials.append(m)
    # Mesh coordinates are baked into common rest space before binding.
    bpy.context.view_layer.objects.active=o
    o.select_set(True); bpy.ops.object.transform_apply(location=True,rotation=True,scale=True); o.select_set(False)
    parts.setdefault(group,[]).append(o); weights[o.name]=bone
    return o

def ell(name,at,scale,m,bone,group='Body',seg=16,rings=10):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg,ring_count=rings,location=at)
    o=bpy.context.object; o.scale=scale
    for f in o.data.polygons: f.use_smooth=True
    return record(o,name,m,bone,group)

def box(name,at,scale,m,bone,group='Body',bev=.02,rot=(0,0,0)):
    bpy.ops.mesh.primitive_cube_add(size=1,location=at,rotation=rot); o=bpy.context.object; o.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bev:
        mod=o.modifiers.new('Forged edges','BEVEL');mod.width=bev;mod.segments=2
        bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
        mod=o.modifiers.new('Weighted plane normals','WEIGHTED_NORMAL');bpy.ops.object.modifier_apply(modifier=mod.name)
    return record(o,name,m,bone,group)

def tube(name,points,radii,m,bone,group='Body',sides=12):
    pts=[Vector(p) for p in points]; verts=[]; faces=[]
    for i,p in enumerate(pts):
        tangent=(pts[min(i+1,len(pts)-1)]-pts[max(i-1,0)]).normalized()
        ref=Vector((0,1,0)) if abs(tangent.y)<.9 else Vector((1,0,0))
        u=tangent.cross(ref).normalized();v=tangent.cross(u).normalized()
        r=radii[i] if isinstance(radii,list) else radii
        rx,ry=r if isinstance(r,tuple) else (r,r)
        for j in range(sides):
            a=j*2*math.pi/sides
            verts.append(p+rx*math.cos(a)*u+ry*math.sin(a)*v)
    faces.append(tuple(reversed(range(sides))))
    for i in range(len(pts)-1):
        for j in range(sides): faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    faces.append(tuple((len(pts)-1)*sides+j for j in range(sides)))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o)
    for f in mesh.polygons: f.use_smooth=True
    return record(o,name,m,bone,group)

def rod(name,a,b,r,m,bone,group='Body'):
    return tube(name,[a,b],r,m,bone,group)

def ring(name,center,normal,radius,width,m,bone,group='Body',thick=.022):
    n=Vector(normal).normalized();ref=Vector((0,1,0)) if abs(n.y)<.9 else Vector((1,0,0))
    u=n.cross(ref).normalized();v=n.cross(u).normalized();c=Vector(center)
    verts=[]; faces=[];N=24
    for k in range(4):
        rr=radius+(thick if k in [0,1] else 0);w=width/2*(1 if k in [0,3] else -1)
        for j in range(N):verts.append(c+u*math.cos(j*2*math.pi/N)*rr+v*math.sin(j*2*math.pi/N)*rr+n*w)
    for k in range(4):
        for j in range(N):faces.append((k*N+j,k*N+(j+1)%N,((k+1)%4)*N+(j+1)%N,((k+1)%4)*N+j))
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
    o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o)
    return record(o,name,m,bone,group)

# Lean frame, bony shoulders and long hanging arms.
ell('Narrow pelvis',(0,.025,1.18),(.27,.18,.24),skin,'pelvis')
tube('Hollow ribcage',[(0,.03,1.22),(0,.06,1.48),(0,.05,1.82),(0,.10,2.04)],[(.21,.16),(.20,.15),(.32,.19),(.35,.16)],skin,'chest')
rod('Sinewed neck',(0,.05,1.98),(0,-.02,2.27),.115,skin,'neck')
ell('Hanging skull',(0,-.075,2.34),(.18,.155,.235),skin,'head')
ell('Jaw',(0,-.14,2.22),(.12,.12,.13),skinlight,'head')
# Face planes remain subtle, without competing bright eyes.
ell('Brow ridge',(0,-.204,2.36),(.145,.028,.04),skinlight,'head')
ell('Nose',(0,-.235,2.28),(.045,.042,.075),skinlight,'head')
rod('Mouth seam',(-.067,-.244,2.195),(.067,-.244,2.195),.009,dark,'head')
for s in [-1,1]:
    label='L' if s>0 else 'R'
    ell('Shoulder '+label,(s*.36,.065,2.01),(.17,.175,.18),skinlight,'arm.'+label)
    tube('Upper arm '+label,[(s*.35,.07,2.03),(s*.45,.04,1.86),(s*.52,-.015,1.60)],[(.14,.13),(.115,.11),(.076,.08)],skin,'arm.'+label)
    ell('Elbow '+label,(s*.52,-.015,1.60),(.085,.075,.10),skinlight,'forearm.'+label)
    tube('Forearm '+label,[(s*.52,-.015,1.60),(s*.57,-.08,1.38),(s*.60,-.15,1.11)],[(.08,.08),(.105,.085),(.052,.06)],skin,'forearm.'+label)
    ell('Palm '+label,(s*.605,-.15,1.01),(.088,.06,.13),skin,'hand.'+label)
    for f in range(4):
        x=s*(.55+f*.037);z=.94-([0,.035,.025,-.005][f])
        tube('Finger '+label+str(f),[(x,-.17,1),(x,-.20,z),(x,-.17,z-.07)],[.019,.017,.013],skin,'hand.'+label,sides=8)
    tube('Thumb '+label,[(s*.55,-.16,1.04),(s*.50,-.20,.99),(s*.51,-.21,.94)],.025,skin,'hand.'+label,sides=8)
    # Bent knees, one asymmetric external shin brace.
    tube('Thigh '+label,[(s*.16,.02,1.23),(s*.22,.005,1.01),(s*.23,-.045,.71)],[(.13,.14),(.13,.12),(.083,.085)],skin,'thigh.'+label)
    ell('Patella '+label,(s*.23,-.10,.71),(.09,.055,.10),skinlight,'shin.'+label)
    tube('Calf '+label,[(s*.23,-.02,.70),(s*.25,.05,.46),(s*.27,.035,.15)],[(.08,.09),(.09,.10),(.05,.055)],skin,'shin.'+label)
    ell('Bare foot '+label,(s*.27,-.065,.115),(.095,.19,.085),skin,'foot.'+label)
    for f in range(4):ell('Toe '+label+str(f),(s*.27+(f-1.5)*.044,-.22,.085),(.026,.065,.035),skinlight,'foot.'+label,seg=10,rings=6)
    ring('Wrist restraint '+label,(s*.594,-.133,1.16),(.08,-.05,-.45),.061,.095,leather,'forearm.'+label)
    for z in [.30,.57]:
        ring('Leg strap '+label+str(z),(s*.26,.03,z),(0,0,1),.087,.065,leather,'shin.'+label)
        box('Strap buckle '+label+str(z),(s*.26,-.072,z),(.073,.025,.061),brass,'shin.'+label,bev=.007)
    if s>0:
        box('Splint wood',(s*.29,-.065,.43),(.115,.075,.49),leather,'shin.'+label,bev=.015,rot=(0,-.035,.025))
        box('Splint iron',(s*.29,-.11,.43),(.042,.027,.46),steel,'shin.'+label,bev=.008)

# Ragged waist apron, uneven hem cut as one mesh.
N=24;vs=[];fs=[]
for row in range(3):
    for j in range(N):
        a=2*math.pi*j/N;r=.26+row*.025
        z=[1.29,1.12,.96][row]-(.12*(j%3)/2 if row==2 else 0)
        vs.append((r*math.cos(a),.02+r*.72*math.sin(a),z))
for row in range(2):
    for j in range(N):fs.append((row*N+j,row*N+(j+1)%N,(row+1)*N+(j+1)%N,(row+1)*N+j))
me=bpy.data.meshes.new('Torn linen hem');me.from_pydata(vs,[],fs);me.update();o=bpy.data.objects.new('Torn linen apron',me);bpy.context.collection.objects.link(o)
record(o,o.name,cloth,'pelvis');ring('Waist belt',(0,.02,1.28),(0,0,1),.26,.065,leather,'pelvis')
# Crossed wrappings around bowed head; layered strips rather than painted lines.
for j in range(5):
    z=2.30+j*.054
    r=.18*math.sqrt(max(.1,1-((z-2.34)/.25)**2))+.003
    wrap=ring('Head wrap '+str(j),(0,-.073,z),(0,.04 if j%2 else -.04,1),r,.057,cloth if j%2 else edge,'head',thick=.009)
    for v in wrap.data.vertices:v.co.y=-.073+(v.co.y+.073)*.87
# Shoulder harness and plate suspension.
for s in [-1,1]:
    tube('Shoulder leather '+str(s),[(s*.23,-.22,1.55),(s*.23,-.23,1.98),(s*.23,.02,2.12),(s*.23,.23,1.80)],[(.039,.016)]*4,leather,'chest',sides=6)
    box('Harness buckle '+str(s),(s*.23,-.245,1.99),(.10,.045,.105),brass,'chest',bev=.008)

# Separate orange heat plate surrounds a visible shutter; core is behind it.
# Both cover and shutter belong to HeatCover, so they can disappear together.
box('Plate upper',(0,-.248,1.99),(.55,.10,.17),orange,'chest','HeatCover',.04)
box('Plate lower',(0,-.25,1.51),(.49,.12,.22),orange,'chest','HeatCover',.05)
for s in [-1,1]:box('Plate rail '+str(s),(s*.235,-.259,1.77),(.10,.12,.41),orange,'chest','HeatCover',.024)
box('Closed inspection shutter',(0,-.255,1.77),(.34,.075,.30),orange,'chest','HeatCover',.01)
for s in [-1,1]:
    for z in [1.53,2.0]:ell('Cover rivet',(s*.20,-.318,z),(.024,.011,.024),brass,'chest','HeatCover',seg=10,rings=6)
ring('Core seat',(0,-.175,1.75),(0,1,0),.19,.10,steel,'chest','CoreTarget',thick=.035)
ell('Yellow heart',(0,-.175,1.75),(.18,.075,.18),yellow,'chest','CoreTarget')
ell('Heart lens glint',(-.045,-.242,1.80),(.025,.009,.035),edge,'chest','CoreTarget')

# Companion: rounded linen pressure sac on four crouching humanoid limbs.
C=-1.57
ell('Companion organic trunk',(C,.07,.64),(.37,.36,.36),skin,'crawler','Companion')
ell('Companion wrapped sac',(C,.12,.78),(.37,.33,.30),cloth,'crawler','Companion')
ell('Companion bowed head',(C,-.27,.50),(.15,.18,.16),skin,'crawler','Companion')
for j in range(3): ring('Companion cap '+str(j),(C,-.27,.51+j*.045),(0,0,1),.145,.05,edge,'crawler','Companion',thick=.01)
for sx in [-1,1]:
    for sy in [-1,1]:
        label=('L' if sx>0 else 'R')+('F' if sy<0 else 'B');bone='crawl.'+label
        x=C+sx*.25;y=.04+sy*.22
        elbow=(C+sx*.37,.04+sy*.29,.27);wrist=(C+sx*.35,.04+sy*.42,.10)
        ell('Crawler shoulder '+label,(x,y,.57),(.10,.11,.12),skin,bone,'Companion')
        tube('Crawling limb '+label,[(x,y,.57),elbow,wrist],[(.084,.08),(.063,.065),(.039,.045)],skin,bone,'Companion')
        ell('Crawler hand '+label,(wrist[0],wrist[1]-.035,.071),(.069,.09,.05),skin,bone,'Companion')
        for j in range(3):ell('Crawler digit '+label+str(j),(wrist[0]+(j-1)*.037,wrist[1]-.10,.047),(.023,.05,.025),skinlight,bone,'Companion',seg=8,rings=6)
# Widthwise iron bands and a longitudinal leather spine make the sac a braced thing.
for y in [-.05,.28]:
    ring('Companion belly brace '+str(y),(C,y,.70),(0,1,0),.355,.065,leather,'crawler','Companion',thick=.03)
    box('Companion top buckle '+str(y),(C,y,1.07),(.14,.095,.045),steel,'crawler','Companion',.009)
box('Companion spine',(C,.12,1.064),(.065,.57,.035),leather,'crawler','Companion',.01)

# Belt-mounted hip brace supports the .85m lateral conduit.
box('Hip conduit bracket',(-.285,.035,1.04),(.075,.11,.43),steel,'root','ConduitCouplings',.018)
ring('Hip port restraint',(-.285,0,.91),(0,0,1),.12,.07,leather,'root','ConduitCouplings',thick=.018)

# Lateral cuttable conduit. Its central segment overlaps the existing .85m hit line.
points=[(-.15,0,.85),(-.50,-.015,.85),(-.78,-.025,.83),(-1.0,-.01,.85),(-1.20,0,.85)]
tube('Blue lateral conduit',points,.108 if PASS==1 else .125,blue,'root','CutConduit',sides=16)
for x in [-.33,-1.20]:
    ring('Pipe flange '+str(x),(x,0,.85),(1,0,0),.15,.085,steel,'root','ConduitCouplings',thick=.03)
    ring('Pipe gasket '+str(x),(x-.06,0,.85),(1,0,0),.13,.04,dark,'root','ConduitCouplings')
# Refinement 1: visible wrapping, ribs, straps, and a distinct crawler muzzle.
if PASS>=2:
    for i in range(8):
        x=-.45-i*.085
        ring('Conduit rib '+str(i),(x,-.015,.84),(1,0,0),.124,.014,bluehi,'root','CutConduit',thick=.008)
    for s in [-1,1]:
        for i in range(4):
            z=1.29+i*.06;x=s*(.576-(z-1.3)*.17)
            ring('Forearm linen '+str(s)+str(i),(x,-.10,z),(.08,-.06,-.48),.087,.055,cloth if i%2 else edge,'forearm.'+('L' if s>0 else 'R'),thick=.009)
    for z in [1.40,1.48]:
        ring('Abdomen linen '+str(z),(0,.035,z),(0,0,1),.205,.07,cloth,'chest',thick=.014)
    for i in range(3):
        z=2.34+i*.055
        rod('Wrap seam '+str(i),(-.15,-.158,z),(.13,-.17,z+.035),.009,cloth,'head')
    for s in [-1,1]:
        tube('Back brace '+str(s),[(s*.27,.24,1.35),(s*.29,.25,1.71),(s*.25,.22,2.02)],.025,steel,'chest')
        box('Companion flank bracket '+str(s),(C+s*.35,.05,.70),(.045,.43,.09),steel,'crawler','Companion',.015)
        ell('Crawler cheek '+str(s),(C+s*.105,-.38,.48),(.06,.05,.07),skinlight,'crawler','Companion')
    rod('Crawler mouth',(C-.08,-.434,.45),(C+.08,-.434,.45),.012,dark,'crawler','Companion')
# Refinement 2: plate edge wear, torso anatomy and clear restraint hardware.
if PASS>=3:
    for s in [-1,1]:
        for i in range(3):
            z=1.62+i*.095
            tube('Exposed lateral rib '+str(s)+str(i),[(s*.22,-.13,z),(s*.295,-.07,z+.035),(s*.30,.04,z+.05)],.016,skinlight,'chest')
        for z in [1.58,1.9]:
            box('Chest restraint tab',(s*.30,-.18,z),(.12,.055,.07),leather,'chest',bev=.009)
            box('Chest clasp',(s*.32,-.215,z),(.06,.03,.08),steel,'chest',bev=.006)
        for i in range(4):
            ell('Crawler brace rivet',(C+s*.37,-.10+i*.10,.70),(.013,.015,.017),brass,'crawler','Companion',seg=8,rings=6)
    for i in range(17):
        s=random.choice([-1,1]);x=s*random.uniform(.18,.26);z=random.uniform(1.48,2.04)
        box('Plate paint loss',(x,-.321,z),(random.uniform(.009,.025),.004,random.uniform(.012,.04)),chip,'chest','HeatCover',.002,rot=(0,random.uniform(-.3,.3),0))
    for x in [-.33,-1.20]:
        for j in range(6):
            a=j*math.tau/6
            ell('Flange stud',(x-.05,.17*math.cos(a),.85+.17*math.sin(a)),(.018,.022,.022),brass,'root','ConduitCouplings',seg=8,rings=6)

# An ordinary skinned rig, no constraints or runtime solver.
data=bpy.data.armatures.new('BorrowedHeart skeleton');rig=bpy.data.objects.new('BorrowedHeartRig',data);bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
def bone(name,a,b,parent=None):
    o=data.edit_bones.new(name);o.head=a;o.tail=b
    if parent:o.parent=data.edit_bones[parent]
bone('root',(0,0,0),(0,0,.15))
bone('pelvis',(0,.02,1.15),(0,.03,1.4),'root')
bone('chest',(0,.03,1.4),(0,.07,2.04),'pelvis')
bone('neck',(0,.07,2.04),(0,-.02,2.23),'chest')
bone('head',(0,-.02,2.23),(0,-.07,2.58),'neck')
for s in [-1,1]:
    l='L' if s>0 else 'R'
    bone('arm.'+l,(s*.35,.07,2.03),(s*.52,-.015,1.6),'chest')
    bone('forearm.'+l,(s*.52,-.015,1.6),(s*.60,-.15,1.11),'arm.'+l)
    bone('hand.'+l,(s*.60,-.15,1.11),(s*.60,-.17,.9),'forearm.'+l)
    bone('thigh.'+l,(s*.16,.02,1.23),(s*.23,-.045,.71),'pelvis')
    bone('shin.'+l,(s*.23,-.045,.71),(s*.27,.035,.15),'thigh.'+l)
    bone('foot.'+l,(s*.27,.035,.15),(s*.27,-.22,.08),'shin.'+l)
bone('crawler',(C,.08,.55),(C,.08,.95),'root')
for sx in [-1,1]:
    for sy in [-1,1]:
        l=('L' if sx>0 else 'R')+('F' if sy<0 else 'B')
        bone('crawl.'+l,(C+sx*.25,.04+sy*.22,.57),(C+sx*.35,.04+sy*.42,.1),'crawler')
bpy.ops.object.mode_set(mode='OBJECT');rig.select_set(False)
# Bind per authored piece; join to eight meaningful removable surfaces.
for group,objects in parts.items():
    for o in objects:
        vg=o.vertex_groups.new(name=weights[o.name]);vg.add(list(range(len(o.data.vertices))),1,'REPLACE')
        # Skin receives restrained per-vertex variation, exported as COLOR_0.
        colors=o.data.color_attributes.new(name='Patina',type='BYTE_COLOR',domain='CORNER')
        for loop in o.data.loops:
            p=o.data.vertices[loop.vertex_index].co
            val=1-.06*(.5+.5*math.sin(p.x*89+p.y*63+p.z*47))
            colors.data[loop.index].color=(val,val,val,1)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();o=bpy.context.object;o.name=group
    o.parent=rig;mod=o.modifiers.new('Borrowed Heart skin','ARMATURE');mod.object=rig
    o['visual_role']=group
    o.select_set(False)
# Root turns authored Blender -Y facing into Godot -Z facing.
export_root=bpy.data.objects.new('BorrowedHeart',None);bpy.context.collection.objects.link(export_root);export_root.rotation_euler.z=math.pi;rig.parent=export_root
export_root['runtime_archetype']='side_guard';export_root['art_pass']=PASS
# Socket coordinates are authored to match existing side_guard part queries.
for name,pos in [('CoreSocket',(0,0,1.75)),('ConduitStart',(-.15,0,.85)),('ConduitEnd',(-1.15,0,.85)),('CompanionSocket',(C,.08,.55)),('CoverSocket',(0,-.25,1.75))]:
    o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.parent=export_root;o.location=pos;o.empty_display_size=.08
# Bake bounded in-place clips. Art state is sampled by the arena, never wall time.
bpy.context.scene.render.fps=30
for name,frames in [('Idle',60),('Walk',30),('Flinch',18)]:
    rig.animation_data_create();act=bpy.data.actions.new(name);rig.animation_data.action=act
    for f in range(frames+1):
        phase=math.tau*f/frames
        for pb in rig.pose.bones:pb.rotation_mode='XYZ';pb.rotation_euler=(0,0,0);pb.location=(0,0,0)
        if name=='Idle':
            rig.pose.bones['chest'].rotation_euler.x=.015*math.sin(phase)
            rig.pose.bones['head'].rotation_euler.z=.018*math.sin(phase)
            rig.pose.bones['crawler'].scale=(1,1,1+.018*math.sin(phase+.4))
        elif name=='Walk':
            rig.pose.bones['pelvis'].location.y=.025*(1-math.cos(phase*2))
            for s,l in [(-1,'R'),(1,'L')]:
                rig.pose.bones['thigh.'+l].rotation_euler.x=s*.24*math.sin(phase)
                rig.pose.bones['shin.'+l].rotation_euler.x=-.25*max(0,s*math.sin(phase))
                rig.pose.bones['arm.'+l].rotation_euler.x=-s*.12*math.sin(phase)
            for i,l in enumerate(['LF','RF','LB','RB']):rig.pose.bones['crawl.'+l].rotation_euler.x=.18*math.sin(phase+(0 if i in [0,3] else math.pi))
        else:rig.pose.bones['chest'].rotation_euler.x=-.16*math.sin(math.pi*f/frames)
        for pb in rig.pose.bones:
            pb.keyframe_insert('rotation_euler',frame=f);pb.keyframe_insert('location',frame=f);pb.keyframe_insert('scale',frame=f)
    track=rig.animation_data.nla_tracks.new();track.name=name;track.strips.new(name,1,act);rig.animation_data.action=None
    for pb in rig.pose.bones:pb.rotation_euler=(0,0,0);pb.location=(0,0,0);pb.scale=(1,1,1)
rig.animation_data.action=None
for track in rig.animation_data.nla_tracks:track.mute=True
bpy.context.scene.frame_set(0)
# Export actions through NLA tracks without the authoring muting state.
source=ROOT/'art-source/enemies/borrowed_heart/borrowed_heart.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(source))
for track in rig.animation_data.nla_tracks:track.mute=False
bpy.ops.object.select_all(action='SELECT')
glb=ROOT/'assets/enemies/borrowed_heart/borrowed_heart.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_yup=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_skins=True,export_extras=True,export_materials='EXPORT')
summary={'pass':PASS,'meshes':len(parts),'bones':len(data.bones),'vertices':sum(len(o.data.vertices) for o in bpy.context.scene.objects if o.type=='MESH'),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in bpy.context.scene.objects if o.type=='MESH'),'clips':['Idle','Walk','Flinch'],'source':str(source),'glb':str(glb)}
(OUT/f'pass-{PASS}-model.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary))
