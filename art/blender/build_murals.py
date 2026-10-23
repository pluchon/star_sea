"""在既有壁画石板上，以贝塞尔刻纹表达六幅神殿壁画。"""
import math,sys,json
from pathlib import Path
import bpy,bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).resolve().parent))
import ruin_modeling as modeling
OUTPUT=ROOT/'game/models/cave'
OUTPUT.mkdir(parents=True,exist_ok=True)

def line(points):
    curve=bpy.data.curves.new('浅浮雕刻线','CURVE')
    curve.dimensions='3D'
    curve.resolution_u=2
    curve.bevel_depth=.024
    curve.bevel_resolution=1
    s=curve.splines.new('BEZIER')
    s.bezier_points.add(len(points)-1)
    for b,(x,z) in zip(s.bezier_points,points):
        b.co=(x,.17,z)
        b.handle_left_type=b.handle_right_type='VECTOR'
    o=bpy.data.objects.new('刻线',curve)
    bpy.context.collection.objects.link(o)
    modeling.active(o)
    bpy.ops.object.convert(target='MESH')
    o=bpy.context.object
    o.data.materials.append(GLOW)
    return o

def ring(x,z,r):
    return line([(x+math.sin(a*math.tau/24)*r,z+math.cos(a*math.tau/24)*r) for a in range(25)])

def person(x,z,size=1):
    return [ring(x,z+.47*size,.1*size),line([(x,z+.35*size),(x,z)]),line([(x-.13*size,z+.13*size),(x,z+.35*size),(x+.13*size,z+.13*size)])]

records=[]
for index in range(6):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(ROOT/'game/models/ruins/mural_panel.glb'))
    base=next(o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('mural_panel'))
    for o in list(bpy.data.objects):
        if o!=base:bpy.data.objects.remove(o,do_unlink=True)
    bm=bmesh.new();bm.from_mesh(base.data)
    remove=[f for f in bm.faces if base.data.materials[f.material_index].name.lower().startswith('glyph')]
    bmesh.ops.delete(bm,geom=remove,context='FACES')
    bm.to_mesh(base.data);bm.free()
    stone=bpy.data.materials.new('stone')
    stone.diffuse_color=(.672,.571,.371,1)
    stone.roughness=.9
    base.data.materials.clear()
    base.data.materials.append(stone)
    for polygon in base.data.polygons:polygon.material_index=0
    GLOW=bpy.data.materials.new('glyph')
    GLOW.diffuse_color=(.89,.46,.10,1)
    GLOW.use_nodes=True
    bsdf=GLOW.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value=(.89,.46,.10,1)
    bsdf.inputs['Emission Color'].default_value=(.89,.46,.10,1)
    bsdf.inputs['Emission Strength'].default_value=.35
    parts=[base]
    if index==0:
        parts.append(line([(-1.5,.7),(-.8,.55),(0,.72),(.7,.55),(1.5,.72)]))
        for x in [-1.1,0,1.1]:
            parts.append(line([(x-.3,1),(x-.3,1.35),(x,1.6),(x+.3,1.35),(x+.3,1)]))
        parts+=person(-.6,1.8,.8)+person(.65,1.8,.8)
    elif index==1:
        parts += [ring(0,1.65,.42),line([(0,.45),(0,1.23)])]
        for x in [-1.2,-.65,.65,1.2]:parts+=person(x,.65)
    elif index==2:
        parts.append(line([(-.5,.5),(-.35,2.5),(.35,2.5),(.5,.5)]))
        for z in [.9,1.4,1.9,2.4]:parts.append(line([(-.45,z),(.45,z)]))
        parts+=person(-1,.5)+person(1,.8)
    elif index==3:
        parts += [ring(-.7,1.8,.6),line([(-1.55,1.4),(.15,2.1)]),line([(.35,1.05),(1.55,1.4),(1.15,1.8),(.35,1.05)])]
    elif index==4:
        parts.append(line([(-.3,.4),(-.3,2.6),(.3,2.6),(.3,.4)]))
        for i in range(4):parts+=person(-1.1+i*.58,.5+i*.44,.65)
    else:
        parts += [line([(-1.2,.5),(-1.2,1.8),(-.6,1.8),(-.6,.5)]),line([(-1.4,1.8),(-.4,1.8)]),line([(-1.05,1.9),(-.85,2.4),(-.65,1.9)])]
        parts+=person(.1,.7,.8)
        for i in range(5):parts.append(ring(.4+i*.24,1.4+i*.22,.055))
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:o.select_set(True)
    bpy.context.view_layer.objects.active=base
    bpy.ops.object.join()
    obj=bpy.context.object
    obj.name=f'mural_{index}'
    for attribute in list(obj.data.color_attributes):obj.data.color_attributes.remove(attribute)
    color=obj.data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
    for datum in color.data:datum.color=(1,1,1,1)
    modeling.normals(obj)
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT/f'mural_{index}.glb'),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_vertex_color='ACTIVE',export_active_vertex_color_when_no_material=True)
    obj.data.calc_loop_triangles()
    records.append({'name':obj.name,'triangles':len(obj.data.loop_triangles)})
    modeling.preview(obj.name,[obj],ROOT/'test-output/models')
(OUTPUT/'murals.json').write_text(json.dumps(records),encoding='utf-8')
