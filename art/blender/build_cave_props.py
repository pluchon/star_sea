"""使用曲线倒角和实体化网罩制作腰间提灯，并保留四视图。"""
import json, math, sys
from pathlib import Path
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).resolve().parent))
import ruin_modeling as modeling
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bronze=bpy.data.materials.new('古铜框')
bronze.diffuse_color=(.14,.29,.25,1)
bronze.metallic=.55
bronze.roughness=.65
glass=bpy.data.materials.new('琥珀灯芯')
glass.diffuse_color=(1,.63,.22,1)
glass.use_nodes=True
bsdf=glass.node_tree.nodes.get('Principled BSDF')
bsdf.inputs['Base Color'].default_value=(1,.63,.22,1)
bsdf.inputs['Emission Color'].default_value=(1,.45,.09,1)
bsdf.inputs['Emission Strength'].default_value=1.5
parts=[]
# 旋转体底座、灯罩从圆截面编辑成形；框线使用贝塞尔曲线倒角。
for name,radius,depth,z,material in [('底座',.075,.035,.02,bronze),('灯芯',.055,.15,.11,glass),('檐盖',.085,.04,.205,bronze)]:
    bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=radius,depth=depth,location=(0,0,z))
    obj=bpy.context.object
    obj.name=name
    mod=obj.modifiers.new('圆润边缘','BEVEL')
    mod.width=.008
    mod.segments=2
    modeling.apply(obj,mod)
    obj.data.materials.append(material)
    parts.append(obj)
paths=[]
for i in range(4):
    angle=i*math.tau/4
    x,y=math.cos(angle)*.067,math.sin(angle)*.067
    paths.append([(x,y,.03),(x*1.04,y*1.04,.11),(x,y,.20)])
paths.append([(-.055,0,.22),(-.05,0,.28),(0,0,.31),(.05,0,.28),(.055,0,.22)])
for path in paths:
    curve=bpy.data.curves.new('弧形框线','CURVE')
    curve.dimensions='3D'
    curve.resolution_u=3
    curve.bevel_depth=.007
    curve.bevel_resolution=1
    spline=curve.splines.new('BEZIER')
    spline.bezier_points.add(len(path)-1)
    for point,position in zip(spline.bezier_points,path):
        point.co=position
        point.handle_left_type=point.handle_right_type='AUTO'
    obj=bpy.data.objects.new('铜框与提环',curve)
    bpy.context.collection.objects.link(obj)
    modeling.active(obj)
    bpy.ops.object.convert(target='MESH')
    obj=bpy.context.object
    obj.data.materials.append(bronze)
    parts.append(obj)
for obj in parts:
    modeling.normals(obj)
bpy.ops.object.select_all(action='DESELECT')
for obj in parts: obj.select_set(True)
bpy.context.view_layer.objects.active=parts[0]
bpy.ops.object.join()
obj=bpy.context.object
obj.name='lantern'
modeling.simplify(obj,600)
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
output=ROOT/'game/models/cave'
output.mkdir(parents=True,exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(output/'lantern.glb'),export_format='GLB',use_selection=True,export_yup=True,export_apply=True)
obj.data.calc_loop_triangles()
(output/'lantern.json').write_text(json.dumps({'triangles':len(obj.data.loop_triangles),'height_m':obj.dimensions.z}),encoding='utf-8')
modeling.preview('lantern',[obj],ROOT/'test-output/models')
