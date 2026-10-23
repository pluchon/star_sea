"""在既有蒙皮人形上制作动作，保留第四步的布料和网格。"""
import json
import math
from pathlib import Path
import sys
import bpy
import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ruin_modeling

NAMES = ('stand', 'walk', 'kneel', 'sit', 'raise', 'carry', 'paint', 'child_run', 'old_walk', 'place', 'look_up', 'kneel_look', 'lamp_carry', 'lamp_raise', 'lamp_place')
ROOT = Path(__file__).resolve().parents[2]


def drape_correction(rig, parts, name):
    """用晶格修正宽袍的坐跪轮廓，再逆蒙皮烘焙形态键，保留骨骼动画。"""
    for part in parts:
        if not any(part.vertex_groups[group.group].name.startswith('Thigh') and group.weight > .01 for vertex in part.data.vertices for group in vertex.groups):
            continue
        if part.data.shape_keys is None:
            part.shape_key_add(name='Basis')
        for key in list(part.data.shape_keys.key_blocks)[1:]:
            key.value = 0
        height = max(vertex.co.z for obj in parts for vertex in obj.data.vertices)
        bpy.context.view_layer.update()
        graph = bpy.context.evaluated_depsgraph_get()
        posed = [vertex.co.copy() for vertex in part.evaluated_get(graph).data.vertices]
        # 晶格作用于原布料的连续裙摆，不把左右腿的弯折直接传到宽袍中央。
        proxy = bpy.data.objects.new('衣摆晶格代理', part.data.copy())
        bpy.context.collection.objects.link(proxy)
        proxy.shape_key_clear()
        lattice_data = bpy.data.lattices.new('坐跪垂褶晶格')
        lattice_data.points_u = 3
        lattice_data.points_v = 3
        lattice_data.points_w = 5
        cage = bpy.data.objects.new('衣摆晶格', lattice_data)
        bpy.context.collection.objects.link(cage)
        cage.location = (0, 0, height * .5)
        cage.scale = (height * .6, height * .5, height)
        root_drop = rig.pose.bones['Root'].head.z
        for control in lattice_data.points:
            z = control.co_deform.z + .5
            if z <= .5:
                ratio = .40 if name == 'sit' else .58
                control.co_deform.z = z * ratio - .5
                control.co_deform.x *= 1.65 if name == 'sit' else 1.15
                control.co_deform.y *= 1.6 if name == 'sit' else 1.1
                if name == 'kneel':
                    control.co_deform.y += max(0, control.co_deform.x) * .65 * (1 - z * 2)
            else:
                control.co_deform.z += root_drop / height
        lattice = proxy.modifiers.new('宽袍坐跪轮廓', 'LATTICE')
        lattice.object = cage
        bpy.context.view_layer.update()
        skirt = [vertex.co.copy() for vertex in proxy.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.vertices]
        bpy.data.objects.remove(proxy, do_unlink=True)
        bpy.data.objects.remove(cage, do_unlink=True)
        points = []
        for vertex, original, relaxed in zip(part.data.vertices, posed, skirt):
            amount = max(0, min(1, (.60 - vertex.co.z / height) / .13))
            amount = amount * amount * (3 - 2 * amount)
            points.append(original.lerp(relaxed, amount))
        key = part.shape_key_add(name='Drape_' + name)
        matrices = {bone.name: rig.pose.bones[bone.name].matrix @ bone.matrix_local.inverted() for bone in rig.data.bones}
        for vertex, point in zip(part.data.vertices, points):
            skin = Matrix(((0, 0, 0, 0),) * 4)
            total = 0
            for group in vertex.groups:
                bone_name = part.vertex_groups[group.group].name
                if bone_name in matrices:
                    skin += matrices[bone_name] * group.weight
                    total += group.weight
            if total > .99:
                key.data[vertex.index].co = skin.inverted_safe() @ point


def animate(rig, parts):
    rig.animation_data_clear()
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    for name in NAMES:
        base_pose = {'look_up': 'sit', 'kneel_look': 'kneel', 'lamp_place': 'kneel'}.get(name, name)
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        rig.animation_data_create()
        rig.animation_data.action = action
        for frame in (1, 7, 13, 19, 25, 31, 37, 43, 49):
            bpy.context.scene.frame_set(frame)
            t = (frame - 1) / 48
            phase = t * math.tau
            ease = t * t * (3 - 2 * t)
            body_ease = 1 if name in ('look_up', 'kneel_look') else ease
            for bone in rig.pose.bones:
                bone.rotation_mode = 'XYZ'
                bone.rotation_euler = (0, 0, 0)
                bone.location = (0, 0, 0)
            root = rig.pose.bones['Root']
            spine = rig.pose.bones['Spine']
            if name in ('walk', 'carry', 'child_run', 'old_walk'):
                amplitude = .32 if name != 'child_run' else .53
                if name == 'old_walk':
                    amplitude = .13
                    spine.rotation_euler.x = .19
                root.location.y = abs(math.sin(phase)) * .012
                for side, sign in (('.L', -1), ('.R', 1)):
                    swing = math.sin(phase) * sign
                    rig.pose.bones['Thigh' + side].rotation_euler.x = amplitude * swing
                    rig.pose.bones['Shin' + side].rotation_euler.x = -.3 * max(0, -swing)
                    rig.pose.bones['UpperArm' + side].rotation_euler.x = -.22 * swing
                    if name == 'carry':
                        rig.pose.bones['UpperArm' + side].rotation_euler.x = -.45
                        rig.pose.bones['Forearm' + side].rotation_euler.x = -.5
            elif base_pose in ('sit', 'kneel'):
                # 根骨局部 Y 沿躯干向上，下降与屈膝共同形成坐姿。
                root.location.y = -.62 * body_ease if base_pose == 'sit' else -.43 * body_ease
                for side, sign in (('.L', -1), ('.R', 1)):
                    rig.pose.bones['Thigh' + side].rotation_euler.x = (1.30 if base_pose == 'sit' else (1.12 if side == '.L' else -.12)) * body_ease
                    rig.pose.bones['Thigh' + side].rotation_euler.z = sign * .90 * body_ease if base_pose == 'sit' else 0
                    rig.pose.bones['Shin' + side].rotation_euler.x = (-2.35 if base_pose == 'sit' else (-1.50 if side == '.L' else -2.05)) * body_ease
                spine.rotation_euler.x = (-.90 if name == 'lamp_place' else .08) * body_ease
            elif name in ('raise', 'paint', 'lamp_carry', 'lamp_raise'):
                rig.pose.bones['UpperArm.R'].rotation_euler.x = 2.25 * ease
                rig.pose.bones['UpperArm.R'].rotation_euler.z = .26 * math.sin(t * math.pi) if name == 'paint' else 0
                rig.pose.bones['Forearm.R'].rotation_euler.x = .35 * ease
                rig.pose.bones['Head'].rotation_euler.x = -.18 * ease
            elif name in ('place', 'lamp_place'):
                spine.rotation_euler.x = -.78 * math.sin(t * math.pi / 2)
                rig.pose.bones['UpperArm.R'].rotation_euler.x = .72 * ease
                root.location.y = -.12 * ease
            if name in ('look_up', 'kneel_look'):
                rig.pose.bones['Head'].rotation_euler.x = -.32 * ease
                rig.pose.bones['Chest'].rotation_euler.x = -.08 * ease
            if name in ('raise', 'paint', 'lamp_carry', 'lamp_raise', 'place', 'lamp_place', 'old_walk'):
                # 以逆运动学解算手臂，再将结果烘焙为普通骨骼关键帧。
                target = bpy.data.objects.new('手臂目标', None)
                bpy.context.collection.objects.link(target)
                height = max(v.co.z for o in parts for v in o.data.vertices)
                if name in ('raise', 'lamp_raise'):
                    target.location = Vector((.12, .22, 1.08)) * height
                elif name in ('lamp_carry', 'old_walk'):
                    target.location = Vector((.16, .23, .57)) * height
                elif name in ('place', 'lamp_place'):
                    target.location = Vector((.13, .32, .15)) * height
                else:
                    # 圆环后接直线，手端和壁画刻纹采用同一段动作进度。
                    angle = min(t / .72, 1) * math.tau
                    ring = Vector((.10 + .16 * math.sin(angle), .34, .79 + .16 * math.cos(angle)))
                    line = Vector((.10, .34, .63 - .30 * max(0, (t - .72) / .28)))
                    target.location = (ring if t < .72 else line) * height
                forearm = rig.pose.bones['Forearm.R']
                constraint = forearm.constraints.new('IK')
                constraint.target = target
                constraint.chain_count = 2
                constraint.influence = 1 if name == 'paint' else ease
                bpy.context.view_layer.update()
                matrices = {n: rig.pose.bones[n].matrix.copy() for n in ('UpperArm.R', 'Forearm.R')}
                forearm.constraints.remove(constraint)
                for n in ('UpperArm.R', 'Forearm.R'):
                    rig.pose.bones[n].matrix = matrices[n]
                bpy.data.objects.remove(target, do_unlink=True)
            rig.pose.bones['Chest'].rotation_euler.z += .008 * math.sin(phase)
            for bone in rig.pose.bones:
                bone.keyframe_insert('rotation_euler', frame=frame, group=bone.name)
                bone.keyframe_insert('location', frame=frame, group=bone.name)
        # 所有关键帧建立后再逐帧贴地，避免读取仍处在上一个动作的依赖图。
        for frame in (1, 7, 13, 19, 25, 31, 37, 43, 49):
            bpy.context.scene.frame_set(frame)
            bpy.context.view_layer.update()
            graph = bpy.context.evaluated_depsgraph_get()
            low = min((o.matrix_world @ v.co).z for o in parts for v in o.evaluated_get(graph).data.vertices)
            root = rig.pose.bones['Root']
            if base_pose not in ('sit', 'kneel'):
                root.location.y -= low
            root.keyframe_insert('location', frame=frame, group=root.name)
        if name in ('sit', 'kneel'):
            drape_correction(rig, parts, name)
    # 修正形态键与骨骼动作放入同名轨道，导出后仍是同一个动画片段。
    for part in parts:
        if part.data.shape_keys is None:
            continue
        keys = part.data.shape_keys
        keys.animation_data_create()
        for name in NAMES:
            base_pose = {'look_up': 'sit', 'kneel_look': 'kneel', 'lamp_place': 'kneel'}.get(name, name)
            action = bpy.data.actions.new('Cloth_' + name)
            keys.animation_data.action = action
            for frame in (1, 7, 13, 19, 25, 31, 37, 43, 49):
                amount = (frame - 1) / 48
                for key in list(keys.key_blocks)[1:]:
                    key.value = (1 if name in ('look_up', 'kneel_look') else amount * amount * (3 - 2 * amount)) if key.name == 'Drape_' + base_pose else 0
                    key.keyframe_insert('value', frame=frame)
            track = keys.animation_data.nla_tracks.new()
            track.name = name
            track.strips.new(name, 1, action)
            track.mute = True
        keys.animation_data.action = None
        for key in list(keys.key_blocks)[1:]:
            key.value = 0
    for name in NAMES:
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, 1, bpy.data.actions[name])
        track.mute = True
    rig.animation_data.action = bpy.data.actions['stand']
    bpy.context.scene.frame_set(1)


def preview(name, parts, output):
    for obj in list(bpy.context.scene.objects):
        if obj.type in ('LIGHT', 'CAMERA'):
            bpy.data.objects.remove(obj, do_unlink=True)
    graph = bpy.context.evaluated_depsgraph_get()
    baked = []
    for part in parts:
        mesh = bpy.data.meshes.new_from_object(part.evaluated_get(graph))
        obj = bpy.data.objects.new('姿势预览', mesh)
        obj.matrix_world = part.matrix_world
        bpy.context.collection.objects.link(obj)
        baked.append(obj)
    ruin_modeling.preview(name, baked, output)
    for obj in baked:
        bpy.data.objects.remove(obj, do_unlink=True)


for name in ('echo_figure', 'echo_child'):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    path = ROOT / 'game/models/ruins' / (name + '.glb')
    bpy.ops.import_scene.gltf(filepath=str(path))
    bpy.context.scene.world = bpy.data.worlds.new('回声预览背景')
    # glTF 导入器另建骨骼显示用二十面体；它不属于蒙皮，不能当成人体导出。
    parts = [o for o in bpy.context.scene.objects if o.type == 'MESH' and any(m.type == 'ARMATURE' for m in o.modifiers)]
    for obj in list(bpy.context.scene.objects):
        if obj.type == 'MESH' and obj not in parts:
            bpy.data.objects.remove(obj, do_unlink=True)
    for obj in parts:
        # GLB 的硬法线会拆开共点顶点；先焊接，否则平滑会把每个孤立三角形缩成小点。
        obj.shape_key_clear()
        data = bmesh.new()
        data.from_mesh(obj.data)
        bmesh.ops.remove_doubles(data, verts=list(data.verts), dist=.000001)
        bmesh.ops.recalc_face_normals(data, faces=list(data.faces))
        data.to_mesh(obj.data)
        data.free()
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        if not obj.data.materials:
            material = bpy.data.materials.new('琥珀预览')
            material.diffuse_color = (.949, .706, .353, 1)
            obj.data.materials.append(material)
    rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    animate(rig, parts)
    bpy.context.scene.render.fps = 24
    bpy.ops.object.select_all(action='DESELECT')
    for obj in parts + [rig]:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
                              export_animations=True, export_animation_mode='ACTIONS', export_merge_animation='NLA_TRACK', export_force_sampling=True)
    # 预览使用统一琥珀材质，游戏由回声着色器覆盖所有表面。
    material = bpy.data.materials.new('琥珀人影')
    material.diffuse_color = (.949, .706, .353, 1)
    for obj in parts:
        obj.data.materials.clear()
        obj.data.materials.append(material)
        for polygon in obj.data.polygons:
            polygon.material_index = 0
    preview(name + '_animated', parts, path.parent)
    # 每个姿势保留四视图，检查关节、衣摆和脚底。
    for pose in ('walk', 'kneel', 'sit', 'raise', 'carry', 'paint', 'old_walk', 'place'):
        rig.animation_data.action = bpy.data.actions[pose]
        for part in parts:
            if part.data.shape_keys is not None:
                for key in list(part.data.shape_keys.key_blocks)[1:]:
                    key.value = 1 if key.name == 'Drape_' + pose else 0
        bpy.context.scene.frame_set(25 if pose in ('walk', 'old_walk', 'carry') else 49)
        preview(name + '_' + pose, parts, path.parent)
    (path.parent / (name + '_animations.json')).write_text(json.dumps({'bones': len(rig.data.bones), 'animations': list(NAMES)}, indent=2), encoding='utf-8')
