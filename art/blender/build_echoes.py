"""在既有蒙皮人形上制作动作，保留第四步的布料和网格。"""
import json
import math
from pathlib import Path
import sys
import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ruin_modeling

NAMES = ('stand', 'walk', 'kneel', 'sit', 'raise', 'carry', 'paint', 'child_run', 'old_walk', 'place')
ROOT = Path(__file__).resolve().parents[2]


def animate(rig, parts):
    rig.animation_data_clear()
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    for name in NAMES:
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        rig.animation_data_create()
        rig.animation_data.action = action
        for frame in (1, 7, 13, 19, 25, 31, 37, 43, 49):
            bpy.context.scene.frame_set(frame)
            t = (frame - 1) / 48
            phase = t * math.tau
            ease = t * t * (3 - 2 * t)
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
            elif name in ('sit', 'kneel'):
                # 根骨局部 Y 沿躯干向上，下降与屈膝共同形成坐姿。
                root.location.y = -.66 * ease if name == 'sit' else -.36 * ease
                for side, sign in (('.L', -1), ('.R', 1)):
                    rig.pose.bones['Thigh' + side].rotation_euler.x = 1.45 * ease
                    rig.pose.bones['Thigh' + side].rotation_euler.z = sign * .38 * ease if name == 'sit' else 0
                    rig.pose.bones['Shin' + side].rotation_euler.x = -2.05 * ease
                spine.rotation_euler.x = .08 * ease
            elif name in ('raise', 'paint'):
                rig.pose.bones['UpperArm.R'].rotation_euler.x = 2.25 * ease
                rig.pose.bones['UpperArm.R'].rotation_euler.z = .26 * math.sin(t * math.pi) if name == 'paint' else 0
                rig.pose.bones['Forearm.R'].rotation_euler.x = .35 * ease
                rig.pose.bones['Head'].rotation_euler.x = -.18 * ease
            elif name == 'place':
                spine.rotation_euler.x = -.78 * math.sin(t * math.pi / 2)
                rig.pose.bones['UpperArm.R'].rotation_euler.x = .72 * ease
                root.location.y = -.12 * ease
            if name in ('raise', 'paint'):
                # 以逆运动学解算手臂，再将结果烘焙为普通骨骼关键帧。
                target = bpy.data.objects.new('手臂目标', None)
                bpy.context.collection.objects.link(target)
                height = max(v.co.z for o in parts for v in o.data.vertices)
                target.location = Vector((.12, .22, 1.08)) * height if name == 'raise' else Vector((.10 + .10 * math.sin(t * math.pi), .34, .90 + .05 * math.cos(t * math.pi))) * height
                forearm = rig.pose.bones['Forearm.R']
                constraint = forearm.constraints.new('IK')
                constraint.target = target
                constraint.chain_count = 2
                constraint.influence = ease
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
            root.location.y -= low
            root.keyframe_insert('location', frame=frame, group=root.name)
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
                              export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True)
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
        bpy.context.scene.frame_set(25 if pose in ('walk', 'old_walk', 'carry') else 49)
        preview(name + '_' + pose, parts, path.parent)
    (path.parent / (name + '_animations.json')).write_text(json.dumps({'bones': len(rig.data.bones), 'animations': list(NAMES)}, indent=2), encoding='utf-8')
