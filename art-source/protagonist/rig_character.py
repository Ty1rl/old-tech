"""Simple skinned character rig, baked motion, and explicit hand attachments.

The solver is authoring-only. Exported clips use ordinary bone transforms,
without runtime IK, constraints, root travel, or gameplay dependencies.
"""
import bpy
import math
import json
from mathutils import Vector, Matrix, Euler, Quaternion


def ease(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)))
    return t*t*(3-2*t)


def build_rig(character,out):
    existing=next((ob for ob in character.objects if ob.type=='ARMATURE'),None)
    if existing:
        raise RuntimeError('Rig already exists. Review the authored source before rebuilding its weights or clips.')
    data=bpy.data.armatures.new('Protagonist skeleton')
    rig=bpy.data.objects.new('ProtagonistRig',data)
    character.objects.link(rig)
    rig.show_in_front=True
    data.display_type='OCTAHEDRAL'
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.context.view_layer.objects.active=rig
    bpy.ops.object.mode_set(mode='EDIT')

    def bone(name,head,tail,parent=None,deform=True):
        b=data.edit_bones.new(name); b.head=head; b.tail=tail
        if parent: b.parent=data.edit_bones[parent]
        b.use_deform=deform
        return b
    bone('root',(0,0,0),(0,0,.15),deform=False)
    bone('pelvis',(0,.008,.94),(0,.008,1.07),'root')
    bone('spine',(0,.008,1.07),(0,.004,1.27),'pelvis')
    bone('chest',(0,.004,1.27),(0,0,1.43),'spine')
    bone('neck',(0,0,1.43),(0,.005,1.54),'chest')
    bone('head',(0,.005,1.54),(0,.018,1.81),'neck')
    for s,label in [(1,'L'),(-1,'R')]:
        bone('clavicle.'+label,(0,0,1.40),(s*.195,0,1.414),'chest')
        bone('upper_arm.'+label,(s*.195,0,1.414),(s*.370,-.003,1.180),'clavicle.'+label)
        bone('forearm.'+label,(s*.370,-.003,1.180),(s*.489,-.013,.976),'upper_arm.'+label)
        bone('hand.'+label,(s*.489,-.013,.976),(s*.535,-.017,.901),'forearm.'+label)
        bone('thigh.'+label,(s*.105,.009,.94),(s*.150,.005,.55),'pelvis')
        bone('shin.'+label,(s*.150,.005,.55),(s*.183,.009,.16),'thigh.'+label)
        bone('foot.'+label,(s*.183,.009,.16),(s*.183,-.145,.075),'shin.'+label)
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in rig.pose.bones: pb.rotation_mode='QUATERNION'

    def torso_weights(z):
        if z<1.12:
            t=ease(1.035,1.14,z); return {'pelvis':1-t,'spine':t}
        t=ease(1.15,1.34,z); return {'spine':1-t,'chest':t}

    def leg_weights(v,label):
        z=v.z
        if z>.81:
            t=ease(.82,.96,z); return {'thigh.'+label:1-t,'pelvis':t}
        t=ease(.47,.64,z)
        return {'shin.'+label:1-t,'thigh.'+label:t}

    def arm_weights(v,label):
        s=1 if label=='L' else -1
        wrist=Vector((s*.489,-.013,.976))
        elbow=Vector((s*.370,-.003,1.180))
        t=(v-elbow).dot((wrist-elbow).normalized())
        f=ease(-.025,.028,t)
        h=ease(-.018,.025,(v-wrist).dot(Vector((s*.046,-.004,-.075)).normalized()))
        return {'upper_arm.'+label:(1-f)*(1-h),'forearm.'+label:f*(1-h),'hand.'+label:h}

    unweighted=0; deforming_meshes=[]
    for ob in list(character.objects):
        if ob.type!='MESH': continue
        name=ob.name
        ob.vertex_groups.clear()
        groups={b.name:ob.vertex_groups.new(name=b.name) for b in data.bones if b.use_deform}
        for v in ob.data.vertices:
            x,y,z=v.co; label='L' if x>=0 else 'R'
            if name.startswith('Shirt |'):
                weights=torso_weights(z)
                # Sleeve ends must fully follow the arm even below the armpit.
                # Keeping chest weight there leaves a visible trailing cloth flap.
                t=ease(.153,.246,abs(x))
                for k in list(weights): weights[k]*=1-t
                weights['upper_arm.'+label]=t
            elif name.startswith('Arm skin |'): weights=arm_weights(v.co,label)
            elif name.startswith('Sleeve roll.'):
                weights=arm_weights(v.co,label)
                # Roll sits above the elbow and mostly follows the upper arm.
                weights={'upper_arm.'+label:1}
            elif name.startswith('Trousers |') or name.startswith('Shaped knee'):
                weights=leg_weights(v.co,label)
            elif name.startswith('Trouser turnup.'):
                t=ease(.24,.30,z); weights={'foot.'+label:1-t,'shin.'+label:t}
            elif name.startswith('Boot'):
                t=ease(.20,.28,z)*.38
                weights={'foot.'+label:1-t,'shin.'+label:t}
            elif name=='Neck':
                t=ease(1.49,1.55,z); weights={'neck':1-t,'head':t}
            elif name.startswith('Collar |'): weights={'chest':.55,'neck':.45}
            elif name.startswith('Harness |'): weights=torso_weights(z)
            elif name.startswith(('Canvas chest','Chest pocket','Pocket mouth','Pocket pen','Shoulder adjuster')):
                weights={'chest':1}
            elif name.startswith(('Belt','Hip pouch','Pouch','Rear trouser','Hanging tool','Tool sleeve')):
                weights={'pelvis':1}
            else: weights={'head':1}
            total=sum(weights.values())
            if total<.999: unweighted+=1
            for key,weight in weights.items():
                if weight>.00001: groups[key].add([v.index],weight/total,'REPLACE')
        # Remove unused groups to keep source and exporter readable.
        used={e.group for v in ob.data.vertices for e in v.groups}
        for g in reversed(list(ob.vertex_groups)):
            if g.index not in used: ob.vertex_groups.remove(g)
        mod=ob.modifiers.new('Deform | protagonist skeleton','ARMATURE'); mod.object=rig
        mod.use_deform_preserve_volume=False  # Match ordinary glTF linear skinning.
        ob.parent=rig; ob.matrix_parent_inverse=Matrix.Identity(4)
        deforming_meshes.append(ob.name)

    # Bone-parented sockets have world-aligned equipment axes in the rest pose.
    # This offset is deliberate: hand bones aim along fingers, props along -Y.
    bpy.context.view_layer.update()
    sockets=[]
    for s,label in [(1,'L'),(-1,'R')]:
        empty=bpy.data.objects.new('Grip_'+label,None)
        character.objects.link(empty)
        empty.empty_display_type='ARROWS'; empty.empty_display_size=.065
        empty.parent=rig; empty.parent_type='BONE'; empty.parent_bone='hand.'+label
        pb=rig.pose.bones['hand.'+label]
        parent_frame=pb.matrix@Matrix.Translation((0,pb.bone.length,0))
        empty.matrix_parent_inverse=parent_frame.inverted()
        # The common export yaw and this socket yaw cancel. In exported holds,
        # Grip_R / Grip_L axes match the character root: +Y up and -Z front.
        empty.matrix_basis=Matrix.Translation((s*.517,-.018,.940))@Matrix.Rotation(math.pi,4,'Z')
        empty['attachment_contract']='metres; exported +Y up / -Z forward; attach prop root at identity'
        sockets.append(empty)

    rest={b.name:b.matrix_local.copy() for b in data.bones}
    desired={}

    def fk(name,angles=(0,0,0)):
        b=data.bones[name]
        base=desired[b.parent.name]@rest[b.parent.name].inverted()@rest[name] if b.parent else rest[name]
        desired[name]=base@Euler(angles,'XYZ').to_matrix().to_4x4()
        return desired[name]

    def direction_matrix(name,head,tail):
        b=data.bones[name]
        q=(b.tail_local-b.head_local).rotation_difference(Vector(tail)-Vector(head))
        m=(q.to_matrix()@rest[name].to_3x3()).to_4x4()
        m.translation=head
        desired[name]=m

    def two_bone(first,second,start,target,pole):
        start=Vector(start); target=Vector(target); pole=Vector(pole)
        axis=(target-start).normalized()
        l1=data.bones[first].length; l2=data.bones[second].length
        d=min((target-start).length,l1+l2-.001)
        target=start+axis*d
        along=(l1*l1-l2*l2+d*d)/(2*d)
        bend=pole-start-axis*(pole-start).dot(axis)
        bend.normalize()
        elbow=start+axis*along+bend*math.sqrt(max(0,l1*l1-along*along))
        direction_matrix(first,start,elbow)
        direction_matrix(second,elbow,target)
        return target

    holds={
        'RingHold':{'R':(-.115,-.31,1.17),'L':(.130,-.44,1.17)},
        'FlashHold':{'R':(-.150,-.32,1.21),'L':(.150,-.36,1.21)},
        'ConeHold':{'R':(-.115,-.29,1.16),'L':(.115,-.44,1.19)},
        'ClockHold':{'R':(-.105,-.27,1.16),'L':(.105,-.29,1.16)},
    }
    scene=bpy.context.scene
    scene.render.fps=30
    rig.animation_data_create()
    for name,end,step in [('Idle',61,3),('Walk',31,1)]+[(n,31,30) for n in holds]:
        action=bpy.data.actions.new(name)
        action.use_fake_user=True
        action.use_frame_range=True
        action.frame_start=1; action.frame_end=end
        rig.animation_data.action=action
        for frame in range(1,end+1,step):
            phase=2*math.pi*(frame-1)/(end-1)
            walking=name=='Walk'; holding=name in holds
            desired.clear()
            bob=-.035+.006*math.sin(phase*2)**2 if walking else .0017*math.sin(phase)
            sway=.006*math.sin(phase) if walking else .001*math.sin(phase)
            desired['root']=Matrix.Translation((sway,0,bob))@rest['root']
            fk('pelvis',(0,.018*math.sin(phase) if walking else 0,.008*math.sin(phase)))
            fk('spine',(.013*math.sin(phase),0,0))
            fk('chest',(-.010*math.sin(phase),-.024*math.sin(phase) if walking else 0,0))
            fk('neck'); fk('head',(0,-.010*math.sin(phase),0))
            for s,label in [(1,'L'),(-1,'R')]:
                # In-place walk, with a planted stance and a lifted swing foot.
                legphase=phase+(math.pi if s<0 else 0)
                stride=-.190*math.sin(legphase) if walking else .009
                lift=.075*max(0,math.cos(legphase))**2 if walking else 0
                thigh='thigh.'+label; shin='shin.'+label; foot='foot.'+label
                parent=desired['pelvis']@rest['pelvis'].inverted()@rest[thigh]
                ankle=two_bone(thigh,shin,parent.translation,(s*.183,stride,.16+lift),(s*.15,-.40,.55))
                desired[foot]=rest[foot].copy(); desired[foot].translation=ankle
                fk('clavicle.'+label)
                upper='upper_arm.'+label; fore='forearm.'+label; hand='hand.'+label
                shoulder=desired['clavicle.'+label]@rest['clavicle.'+label].inverted()@rest[upper]
                if holding:
                    offset=Vector((s*.028,-.005,-.036))
                    wrist_target=Vector(holds[name][label])-offset
                else:
                    swing=.10*math.sin(legphase) if walking else .004*math.sin(phase)
                    wrist_target=Vector((s*.286,-.014+swing,.923+bob))
                wrist=two_bone(upper,fore,shoulder.translation,wrist_target,(s*.48,.10,1.14))
                if holding:
                    desired[hand]=rest[hand].copy(); desired[hand].translation=wrist
                else:
                    direction_matrix(hand,wrist,wrist+Vector((s*.008,-.004,-.080)))
            for b in data.bones:
                pb=rig.pose.bones[b.name]
                kwargs={}
                if b.parent:
                    kwargs={'parent_matrix':desired[b.parent.name],'parent_matrix_local':rest[b.parent.name]}
                pb.matrix_basis=b.convert_local_to_pose(desired[b.name],rest[b.name],invert=True,**kwargs)
                pb.keyframe_insert('location',frame=frame,group=b.name)
                pb.keyframe_insert('rotation_quaternion',frame=frame,group=b.name)
                pb.keyframe_insert('scale',frame=frame,group=b.name)
        for curve in action.fcurves:
            for k in curve.keyframe_points: k.interpolation='LINEAR'
        action['loop']=True
        action['purpose']='in-place locomotion' if walking else ('static equipment holding pose' if holding else 'subtle breathing idle')
    rig.animation_data.action=bpy.data.actions['Idle']
    scene.frame_start=1; scene.frame_end=61; scene.frame_set(1)
    bpy.context.view_layer.update()
    # Socket contract includes rest-local matrices and evaluated holding positions.
    poses={}
    for name in holds:
        rig.animation_data.action=bpy.data.actions[name]; scene.frame_set(1)
        bpy.context.view_layer.update()
        poses[name]={ob.name:{'position_blender_m':list(ob.matrix_world.translation),
                    'basis_blender':[[ob.matrix_world[i][j] for j in range(3)] for i in range(3)]} for ob in sockets}
    rig.animation_data.action=bpy.data.actions['Idle']; scene.frame_set(1)
    report={'bone_names':[b.name for b in data.bones],'deforming_bones':[b.name for b in data.bones if b.use_deform],
            'skinned_meshes':deforming_meshes,'unweighted_vertices':unweighted,
            'clips':{a.name:{'frames':list(a.frame_range),'duration_s':(a.frame_range[1]-a.frame_range[0])/30,
                     'loop':True} for a in bpy.data.actions},
            'sockets':{ob.name:{'bone':ob.parent_bone,'rest_local_matrix':
                [[v for v in row] for row in ob.matrix_parent_inverse@ob.matrix_basis]} for ob in sockets},
            'holding_poses':poses,'units':'metres','blender_axes':'+Z up, -Y front',
            'export_axes':'+Y up, -Z front (common rig yaw on glTF export)',
            'root_motion':False,'runtime_ik':False,'export_skinning':'linear blend; up to 3 influences'}
    (out/'rig-contract.json').write_text(json.dumps(report,indent=2)+'\n')
    make_standins(rig,character)
    return rig


def make_standins(rig,character):
    """Crude grip/space references, excluded from the character GLB."""
    collection=bpy.data.collections.new('REVIEW PROPS | stand-ins only')
    bpy.context.scene.collection.children.link(collection)
    grip=bpy.data.objects['Grip_R']
    metal=bpy.data.materials['07 | aged brass hardware']
    dark=bpy.data.materials['06 | boot soles and recesses']
    cloth=bpy.data.materials['04 | slate olive canvas']
    wood=bpy.data.materials['05 | oxhide leather']

    def part(name,vertices,faces,mat,parent,clip):
        data=bpy.data.meshes.new(name); data.from_pydata(vertices,[],faces); data.materials.append(mat)
        ob=bpy.data.objects.new(name,data); collection.objects.link(ob)
        ob.parent=parent; ob.hide_render=True; ob['hold_clip']=clip
        return ob

    def box(name,center,size,mat,parent,clip):
        c=Vector(center); h=Vector(size)/2
        verts=[c+Vector((a*h.x,b*h.y,d*h.z)) for a,b,d in
               [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
        return part(name,verts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat,parent,clip)

    def pipe(name,points,radius,mat,parent,clip):
        rows=[]; n=8
        for i,p in enumerate(points):
            p=Vector(p)
            t=(Vector(points[min(i+1,len(points)-1)])-Vector(points[max(i-1,0)])).normalized()
            u=t.cross(Vector((0,0,1))).normalized()
            if u.length<.1: u=t.cross(Vector((0,1,0))).normalized()
            v=t.cross(u).normalized()
            rows.append([p+radius*(u*math.cos(k*2*math.pi/n)+v*math.sin(k*2*math.pi/n)) for k in range(n)])
        faces=[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(len(rows)-1) for i in range(n)]
        faces+=[tuple(reversed(range(n))),tuple(range((len(rows)-1)*n,len(rows)*n))]
        return part(name,[v for r in rows for v in r],faces,mat,parent,clip)

    for clip in ['RingHold','FlashHold','ConeHold','ClockHold']:
        root=bpy.data.objects.new('Stand-in | '+clip,None); collection.objects.link(root)
        root.parent=grip; root.rotation_euler.z=math.pi
        root['hold_clip']=clip; root.hide_render=True
        box('Right grip', (0,0,-.015),(.031,.036,.10),wood,root,clip)
        if clip=='RingHold':
            pts=[(.122+.18*math.cos(a),-.14+.18*math.sin(a),.075) for a in [math.radians(-20+i*220/16) for i in range(17)]]
            pipe('Open ring frame',pts,.025,metal,root,clip)
            pts=[(.122+.095*math.cos(i*2*math.pi/24),-.14+.095*math.sin(i*2*math.pi/24),.077) for i in range(25)]
            pipe('Suspended ring',pts,.008,dark,root,clip)
            box('Support rest',(.245,-.13,.015),(.06,.075,.035),wood,root,clip)
        elif clip=='FlashHold':
            box('Camera body',(.15,-.055,.095),(.30,.16,.15),dark,root,clip)
            box('Camera bellows',(.15,-.16,.095),(.16,.09,.13),cloth,root,clip)
            pipe('Camera lens',[(.15,-.19,.095),(.15,-.25,.095)],.056,metal,root,clip)
            box('Flash',(.15,-.06,.22),(.09,.07,.07),metal,root,clip)
            box('Left grip',(.30,-.04,-.015),(.031,.036,.10),wood,root,clip)
        elif clip=='ConeHold':
            box('Bellows',(.105,-.10,.09),(.20,.20,.15),cloth,root,clip)
            box('Broad outlet',(.105,-.245,.09),(.17,.075,.14),metal,root,clip)
            box('Outlet recess',(.105,-.285,.09),(.13,.008,.10),dark,root,clip)
            box('Support grip',(.23,-.15,.025),(.04,.06,.065),wood,root,clip)
        else:
            box('Compact clock case',(.105,-.025,.065),(.21,.08,.14),wood,root,clip)
            pipe('Clock face',[(.105,-.07,.065),(.105,-.083,.065)],.058,metal,root,clip)
