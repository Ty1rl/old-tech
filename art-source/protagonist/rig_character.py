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
        x,y,z=v.x,v.y,v.z
        if z>.72:
            t=ease(.74,.95,z)
            # Soften the inner-thigh/crotch seam near x=0 so wide Run/Walk strides never step or tear.
            crotch=(1-ease(.012,.068,abs(x)))*ease(.70,.83,z)
            t=max(t,crotch)
            return {'thigh.'+label:1-t,'pelvis':t}
        if z<.29:
            # Blend lower trouser hem smoothly with the ankle so it moves with the boot collar.
            a=(1-ease(.19,.28,z))*.22
            return {'shin.'+label:1-a,'foot.'+label:a}
        # Knee joint sits at z=0.55. Keep z<0.50 on shin so the upper shin never balloons forward in swing,
        # while blending smoothly across the patella and lower thigh (0.50..0.65).
        t=ease(.50,.65,z)
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
                # Match the lower trouser leg weighting so the cuff never shears or crushes against the shin.
                a=(1-ease(.19,.28,z))*.22
                weights={'shin.'+label:1-a,'foot.'+label:a}
            elif name.startswith('Boot sole'):
                weights={'foot.'+label:1}
            elif name.startswith('Boot'):
                # Rigid foot/sole at the bottom, blending smoothly into the shin up the boot collar.
                t=ease(.16,.27,z)*.72
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

    def foot_pose(foot_name,ankle_pos,pitch_rad):
        # Negative world-X rotation lifts the toe (-Y) upward (+Z) for heel strike;
        # positive world-X rotation points the toe downward (-Z) for push-off.
        m=(Matrix.Rotation(-pitch_rad,3,'X')@rest[foot_name].to_3x3()).to_4x4()
        m.translation=Vector(ankle_pos)
        desired[foot_name]=m

    holds={
        'RingHold':{'R':(-.115,-.31,1.17),'L':(.130,-.44,1.17)},
        'FlashHold':{'R':(-.150,-.32,1.21),'L':(.150,-.36,1.21)},
        'ConeHold':{'R':(-.115,-.29,1.16),'L':(.115,-.44,1.19)},
        'ClockHold':{'R':(-.105,-.27,1.16),'L':(.105,-.29,1.16)},
    }
    gait_metrics={
        'Walk':{
            'stride_length_unscaled_m':1.12,
            'stride_length_scaled_1_3x_m':1.456,
            'duration_s':1.0,
            'base_speed_scaled_1_3x_mps':1.456,
            'recommended_playback_rate_walk':1.35,
            'notes':'In-place walk cycle with planted stance contact and 0.56 m per-foot excursion (1.12 m full cycle unscaled, 1.456 m at 1.3x visual scale).'
        },
        'Run':{
            'stride_length_unscaled_m':1.52,
            'stride_length_scaled_1_3x_m':1.976,
            'duration_s':0.6667,
            'base_speed_scaled_1_3x_mps':2.964,
            'recommended_playback_rate_at_6mps':2.0,
            'notes':'In-place run cycle with forward torso lean, high swing knee/heel recovery, and 0.76 m per-foot excursion (1.52 m full cycle unscaled, 1.976 m at 1.3x visual scale; plays at ~2.0x for 6 m/s gameplay speed).'
        },
        'BackWalk':{
            'stride_length_unscaled_m':0.96,
            'stride_length_scaled_1_3x_m':1.248,
            'duration_s':1.0,
            'base_speed_scaled_1_3x_mps':1.248,
            'recommended_playback_rate_backwalk':1.5,
            'notes':'Dedicated backward walk cycle with rear toe-first reach and grounded draw-back stance.'
        }
    }
    scene=bpy.context.scene
    scene.render.fps=30
    rig.animation_data_create()
    clip_specs=[('Idle',61,3),('Walk',31,1),('Run',21,1),('BackWalk',31,1)]+[(n,31,30) for n in holds]
    for name,end,step in clip_specs:
        action=bpy.data.actions.new(name)
        action.use_fake_user=True
        action.use_frame_range=True
        action.frame_start=1; action.frame_end=end
        rig.animation_data.action=action
        for frame in range(1,end+1,step):
            phase=2*math.pi*(frame-1)/(end-1)
            walking=name=='Walk'
            running=name=='Run'
            backwalking=name=='BackWalk'
            locomotion=walking or running or backwalking
            holding=name in holds
            desired.clear()
            if running:
                # Lowest at full-stride contact/push-off (cos(phase*2)==1) so the 0.784m leg chain reaches ground,
                # highest as the stance leg drives upward through mid-pass (cos(phase*2)==-1).
                bob=-.058-.022*math.cos(phase*2)
                sway=.011*math.sin(phase)
                pelvis_rot=(.045,.028*math.sin(phase),-.042*math.cos(phase))
                spine_rot=(.085-.014*math.cos(phase*2),-.016*math.sin(phase),.026*math.cos(phase))
                chest_rot=(.060-.010*math.cos(phase*2),-.030*math.sin(phase),.038*math.cos(phase))
                head_rot=(-.110,-.010*math.sin(phase),-.018*math.cos(phase))
            elif walking:
                # Lowest at double-support passing, highest as planted leg vaults over mid-stance.
                bob=-.026-.012*math.cos(phase*2)
                sway=.008*math.sin(phase)
                pelvis_rot=(.012,.022*math.sin(phase),-.028*math.cos(phase))
                spine_rot=(.018-.006*math.cos(phase*2),-.010*math.sin(phase),.016*math.cos(phase))
                chest_rot=(.012,-.022*math.sin(phase),.024*math.cos(phase))
                head_rot=(-.018,-.008*math.sin(phase),-.010*math.cos(phase))
            elif backwalking:
                bob=-.028-.009*math.cos(phase*2)
                sway=.007*math.sin(phase)
                pelvis_rot=(.020,-.018*math.sin(phase),.022*math.cos(phase))
                spine_rot=(.030-.005*math.cos(phase*2),.008*math.sin(phase),-.014*math.cos(phase))
                chest_rot=(.022,.016*math.sin(phase),-.020*math.cos(phase))
                head_rot=(-.032,-.006*math.sin(phase),.008*math.cos(phase))
            else:
                bob=.0017*math.sin(phase)
                sway=.001*math.sin(phase)
                pelvis_rot=(0,0,.008*math.sin(phase))
                spine_rot=(.013*math.sin(phase),0,0)
                chest_rot=(-.010*math.sin(phase),0,0)
                head_rot=(0,-.010*math.sin(phase),0)
            desired['root']=Matrix.Translation((sway,0,bob))@rest['root']
            fk('pelvis',pelvis_rot)
            fk('spine',spine_rot)
            fk('chest',chest_rot)
            fk('neck'); fk('head',head_rot)
            for s,label in [(1,'L'),(-1,'R')]:
                legphase=phase+(math.pi if s<0 else 0)
                c=math.cos(legphase)
                sn=math.sin(legphase)
                if running:
                    # legphase=0: front strike (-Y); pi/2: mid-stance; pi: rear toe push-off (+Y); 3pi/2: high swing recovery.
                    stride=-.380*c
                    swing_Bell=max(0,-sn)
                    # pitch_rad > 0 lifts toe for front heel strike; < 0 points toe down on push-off & swing recovery.
                    foot_pitch=.14*max(0,c)*(1-.4*swing_Bell)-.32*max(0,-c)-.22*(swing_Bell**1.2)
                    lift=.155*(swing_Bell**1.35)+.13*max(0,-foot_pitch)*(1-.3*swing_Bell)
                elif walking:
                    # legphase=0: front heel contact (-Y); pi/2: flat planted mid-stance; pi: rear push-off (+Y); 3pi/2: swing lift.
                    stride=-.280*c
                    swing_Bell=max(0,-sn)
                    foot_pitch=.15*max(0,c)*(1-.5*swing_Bell)-.22*max(0,-c)-.06*swing_Bell
                    lift=.082*(swing_Bell**1.5)+.13*max(0,-foot_pitch)*(1-.4*swing_Bell)
                elif backwalking:
                    # Reverse travel: swing reaches back (+Y) when sn<0, planted stance draws from +Y to -Y when sn>0.
                    stride=.240*c
                    swing_Bell=max(0,-sn)
                    foot_pitch=-.16*max(0,c)-.08*swing_Bell+.10*max(0,-c)
                    lift=.062*(swing_Bell**1.5)+.12*max(0,-foot_pitch)
                else:
                    stride=.009
                    lift=0
                    foot_pitch=0
                thigh='thigh.'+label; shin='shin.'+label; foot='foot.'+label
                parent=desired['pelvis']@rest['pelvis'].inverted()@rest[thigh]
                ankle_x=s*(.174 if locomotion else .183)
                ankle=two_bone(thigh,shin,parent.translation,(ankle_x,stride,.16+lift),(s*.165,-.45,.55))
                foot_pose(foot,ankle,foot_pitch)
                fk('clavicle.'+label)
                upper='upper_arm.'+label; fore='forearm.'+label; hand='hand.'+label
                shoulder=desired['clavicle.'+label]@rest['clavicle.'+label].inverted()@rest[upper]
                if holding:
                    offset=Vector((s*.028,-.005,-.036))
                    wrist_target=Vector(holds[name][label])-offset
                    arm_pole=(s*.48,.10,1.14)
                elif running:
                    # When c < 0 (leg back +Y), same-side arm swings forward (-Y) and slightly up;
                    # when c > 0 (leg forward -Y), same-side arm swings back (+Y) and stays low.
                    arm_drive=.18*c
                    arm_lift=.065*max(0,-c)+.015*max(0,c)
                    wrist_target=Vector((s*.262,-.095+arm_drive,.965+arm_lift+bob))
                    arm_pole=(s*.35,.28,1.02)
                elif walking:
                    arm_swing=.13*c
                    wrist_target=Vector((s*.268,-.030+arm_swing,.910+.025*max(0,-c)+bob))
                    arm_pole=(s*.36,.24,1.06)
                elif backwalking:
                    arm_swing=-.11*c
                    wrist_target=Vector((s*.268,-.025+arm_swing,.915+.020*max(0,c)+bob))
                    arm_pole=(s*.36,.24,1.06)
                else:
                    swing=.004*math.sin(phase)
                    wrist_target=Vector((s*.286,-.014+swing,.923+bob))
                    arm_pole=(s*.48,.10,1.14)
                wrist=two_bone(upper,fore,shoulder.translation,wrist_target,arm_pole)
                if holding:
                    desired[hand]=rest[hand].copy(); desired[hand].translation=wrist
                elif running:
                    direction_matrix(hand,wrist,wrist+Vector((s*-.010,-.055,-.050)))
                else:
                    direction_matrix(hand,wrist,wrist+Vector((s*.008,-.018,-.078)))
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
        action['purpose']='in-place locomotion' if locomotion else ('static equipment holding pose' if holding else 'subtle breathing idle')
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
            'clips':{a.name:{'frames':list(a.frame_range),'duration_s':round((a.frame_range[1]-a.frame_range[0])/30,4),
                     'loop':True} for a in bpy.data.actions},
            'gait_metrics':gait_metrics,
            'runtime_scale_reference':{'visual_scale':1.3,'gameplay_move_speed_mps':6.0,
                     'unscaled_model_speed_at_6mps':round(6.0/1.3,4)},
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
