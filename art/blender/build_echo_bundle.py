"""用细分布袋和贝塞尔束绳制作回声队伍的行囊。"""
from pathlib import Path
import math
import sys
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ruin_modeling as modeling

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.world = bpy.data.worlds.new('行囊背景')
material = bpy.data.materials.new('褪色织物')
material.diffuse_color = (.71, .39, .27, 1)
parts = []
bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8)
bag = bpy.context.object
bag.name = '软布行囊'
bag.scale = (.29, .15, .35)
modeling.active(bag)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
for vertex in bag.data.vertices:
    vertex.co.x *= .90 + .10 * math.sin(vertex.co.z * 13)
    vertex.co.y *= .90 + .10 * math.sin(vertex.co.x * 27)
subdivision = bag.modifiers.new('圆顺布面', 'SUBSURF')
subdivision.levels = 1
modeling.apply(bag, subdivision)
modeling.simplify(bag, 700)
parts.append(bag)
for axis in range(2):
    curve = bpy.data.curves.new('束带', 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = .018
    curve.bevel_resolution = 1
    spline = curve.splines.new('BEZIER')
    spline.bezier_points.add(11)
    for i, point in enumerate(spline.bezier_points):
        a = i / 12 * math.tau
        point.co = (.29 * math.sin(a), .16 * math.cos(a), 0) if axis == 0 else (0, .16 * math.cos(a), .35 * math.sin(a))
        point.handle_left_type = point.handle_right_type = 'AUTO'
    spline.use_cyclic_u = True
    obj = bpy.data.objects.new('绳结', curve)
    bpy.context.collection.objects.link(obj)
    modeling.active(obj)
    bpy.ops.object.convert(target='MESH')
    parts.append(bpy.context.object)
for obj in parts:
    obj.data.materials.append(material)
bpy.ops.object.select_all(action='DESELECT')
for obj in parts:
    obj.select_set(True)
output = Path('game/models/ruins/echo_bundle.glb').resolve()
bpy.ops.export_scene.gltf(filepath=str(output), use_selection=True, export_format='GLB')
modeling.preview('echo_bundle', parts, output.parent)
