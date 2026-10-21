"""天梯近景：编辑环带截面、曲线倒角与破损壳体，导出模型和四视图。"""
import json, math, random, sys
from pathlib import Path
import bpy
from mathutils import Vector
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import ruin_modeling as modeling
OUT = ROOT / 'game/models/sky_ladder'
OUT.mkdir(parents=True, exist_ok=True)
only = set(sys.argv[sys.argv.index('--')+1:]) if '--' in sys.argv else set()
record = json.loads((OUT/'geometry.json').read_text(encoding='utf-8')) if only and (OUT/'geometry.json').exists() else {}
stone = bpy.data.materials.new('Stone')
stone.diffuse_color = (.72, .67, .54, 1)
bronze = bpy.data.materials.new('Patina')
bronze.diffuse_color = (.19, .34, .29, 1)
glyph = bpy.data.materials.new('Glyph')
glyph.diffuse_color = (1, .68, .27, 1)

def reset():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

def mesh(name, vertices, faces, material=stone, bevel=0):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    modeling.normals(obj)
    if bevel:
        mod = obj.modifiers.new('磨损的边缘', 'BEVEL')
        mod.width, mod.segments = bevel, 2
        modeling.apply(obj, mod)
    return obj

def ring(name, inner, outer, height=.6, start=0, end=math.tau, segments=96, material=stone):
    vertices, faces = [], []
    closed = abs(end-start-math.tau)<1e-6
    if closed and inner == 0:
        vertices=[(0,0,-height),(0,0,0)]
        for i in range(segments):
            a=start+i*math.tau/segments
            vertices.extend([(outer*math.sin(a),outer*math.cos(a),-height),(outer*math.sin(a),outer*math.cos(a),0)])
        for i in range(segments):
            a,b=2+i*2,2+((i+1)%segments)*2
            faces.extend([(0,a,b),(1,b+1,a+1),(a,a+1,b+1,b)])
        return mesh(name,vertices,faces,material,.05)
    for i in range(segments if closed else segments+1):
        a = start + (end-start)*i/segments
        for radius, z in [(inner,-height),(outer,-height),(outer,0),(inner,0)]:
            vertices.append((radius*math.sin(a),radius*math.cos(a),z))
    for i in range(segments):
        next_ring=(i+1)%segments if closed else i+1
        for j in range(4):
            a,b = i*4+j,i*4+(j+1)%4
            faces.append((a,b,next_ring*4+(j+1)%4,next_ring*4+j))
    if not closed:
        faces += [(3,2,1,0),(segments*4,segments*4+1,segments*4+2,segments*4+3)]
    return mesh(name,vertices,faces,material,.05)

def curve(name, points, radius, material=bronze, resolution=2, sides=1):
    data=bpy.data.curves.new(name,'CURVE')
    data.dimensions='3D'
    data.resolution_u=resolution
    data.bevel_depth=radius
    data.bevel_resolution=sides
    path=data.splines.new('BEZIER')
    path.bezier_points.add(len(points)-1)
    for point, xyz in zip(path.bezier_points,points):
        point.co=xyz
        point.handle_left_type=point.handle_right_type='AUTO'
    obj=bpy.data.objects.new(name,data)
    bpy.context.collection.objects.link(obj)
    modeling.active(obj)
    bpy.ops.object.convert(target='MESH')
    obj=bpy.context.object
    obj.data.materials.append(material)
    return obj

def plate(name,width,length,thickness=.65):
    # 平台由平面实体化并倒角，顶面保持在零，碰撞使用导出的同一网格。
    obj=mesh(name,[(-width/2,-length/2,0),(width/2,-length/2,0),(width/2,length/2,0),(-width/2,length/2,0)],[(0,1,2,3)])
    mod=obj.modifiers.new('石板厚度','SOLIDIFY')
    mod.thickness=thickness
    mod.offset=-1
    modeling.apply(obj,mod)
    mod=obj.modifiers.new('磨圆石板边缘','BEVEL')
    mod.width,mod.segments=.08,2
    modeling.apply(obj,mod)
    return obj

def export(name, parts, budget=16000):
    if only and name not in only:
        return
    bpy.ops.object.select_all(action='DESELECT')
    for obj in parts:obj.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join()
    obj=bpy.context.object
    obj.name=name
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    modeling.simplify(obj,budget)
    bpy.context.view_layer.update()
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_apply=True)
    obj.data.calc_loop_triangles()
    bounds=[max(v.co[i] for v in obj.data.vertices)-min(v.co[i] for v in obj.data.vertices) for i in range(3)]
    record[name]={'triangles':len(obj.data.loop_triangles),'bounds':bounds}
    # 预览助手的默认相机裁剪与横向范围面向普通构件；巨型缆索先等比缩小，长桥旋转到横轴。
    if name == 'broken_top':
        obj.scale *= .05
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if name == 'gangway':
        obj.rotation_euler.z = math.pi/2
        bpy.ops.object.transform_apply(location=False,rotation=True,scale=False)
    modeling.preview('ladder_'+name,[obj],ROOT/'test-output/models')

reset()
parts=[ring('升降圆盘',0,6,.7,segments=64)]
parts.append(ring('铜框边缘',5.65,6.05,.16,segments=64,material=bronze))
parts.append(curve('环与径',[(2.2*math.cos(a),2.2*math.sin(a),.025) for a in [i*math.tau/48 for i in range(49)]],.045,glyph))
parts.append(curve('径',[(0,-2.2,.025),(0,-4.5,.025)],.045,glyph))
export('lift',parts,5000)
reset()
parts=[ring('观景石环',30,42,.8)]
for start,end in [(.12,2.7),(3.3,5.65)]:
    points=[(41.5*math.sin(a),41.5*math.cos(a),1.2) for a in [start+(end-start)*i/60 for i in range(61)]]
    parts.append(curve('残存扶手',points,.15))
    for i in range(0,61,5):
        x,y,z=points[i]
        parts.append(curve('支柱',[(x,y,0),(x,y,z)],.13))
parts.append(plate('升降台出口',12,8))
parts[-1].location.y=31
export('balcony',parts)
reset()
parts=[ring('断口石环',22,44,1.2)]
parts.append(curve('残存扶手',[(43.4*math.sin(a),43.4*math.cos(a),1.15) for a in [i*math.tau/60 for i in range(41)]],.14))
for i in range(40):
    a=i*math.tau/60
    parts.append(curve('残缺护栏',[(43.4*math.sin(a),43.4*math.cos(a),0),(43.4*math.sin(a),43.4*math.cos(a),1.15)],.18))
parts.append(plate('停泊石台',36,24,1.2))
parts[-1].location.y=-54
parts.append(curve('停泊环',[(6*math.cos(a),-54+6*math.sin(a),.03) for a in [i*math.tau/64 for i in range(65)]],.12,glyph))
parts.append(curve('停泊径',[(0,-60,.03),(0,-65,.03)],.12,glyph))
export('break_platform',parts)
reset()
parts=[plate('栈桥',4,28,1)]
parts[0].location.y=14
parts.append(ring('尽头圆台',0,4,.8,segments=48))
parts[-1].location.y=30
export('gangway',parts,4500)
reset()
parts=[]
# 从连续拱形带面挤出门框，内轮廓二十四米高，保留完整门洞。
path=[(-9,0),(-9,14)]+[(9*math.cos(math.pi-i*math.pi/24),14+10*math.sin(math.pi-i*math.pi/24)) for i in range(25)]+[(9,0)]
vertices=[]
for x,z in path:
    outward=Vector((x,z-14)).normalized() if z>14 else Vector((-1 if x<0 else 1,0))
    for y,extra in [(-2,0),(2,0),(2,3),(-2,3)]:vertices.append((x+outward.x*extra,y,z+outward.y*extra))
faces=[]
for i in range(len(path)-1):
    for j in range(4):faces.append((i*4+j,i*4+(j+1)%4,(i+1)*4+(j+1)%4,(i+1)*4+j))
faces += [(3,2,1,0),(len(vertices)-4,len(vertices)-3,len(vertices)-2,len(vertices)-1)]
parts.append(mesh('主门',vertices,faces,stone,.18))
parts.append(curve('门楣环',[(3*math.cos(a),-2.16,26+3*math.sin(a)) for a in [i*math.tau/48 for i in range(49)]],.15,glyph))
parts.append(curve('门楣径',[(0,-2.16,23),(0,-2.16,20)],.15,glyph))
export('gate',parts,6500)
reset()
rng=random.Random(20261021)
vertices=[]
for ring_index in range(4):
    for i in range(32):
        a=i*math.tau/32
        radius=22+(1.8 if ring_index in [1,2] else 0)
        z=[-8,0,0,-8][ring_index]+(rng.uniform(-5,5) if ring_index in [1,2] else 0)
        vertices.append((radius*math.sin(a),radius*math.cos(a),z))
faces=[]
for j in range(3):
    for i in range(32):faces.append((j*32+i,j*32+(i+1)%32,(j+1)*32+(i+1)%32,(j+1)*32+i))
parts=[mesh('撕裂断口',vertices,faces)]
for i in range(5):
    a=i*math.tau/5+.2
    length=300+i*125
    parts.append(curve('垂落缆索',[(23*math.sin(a),23*math.cos(a),0),(25*math.sin(a),26*math.cos(a),-length*.35),(23*math.sin(a)+8,28*math.cos(a),-length*.7),(24*math.sin(a)+4,23*math.cos(a),-length)],.6,bronze,3,0))
export('broken_top',parts,2400)
# 守望者灯沿用已验证的曲线铜框，放大至便于栈桥近景辨认的高度。
reset()
bpy.ops.import_scene.gltf(filepath=str(ROOT/'game/models/cave/lantern.glb'))
parts=[o for o in bpy.context.scene.objects if o.type=='MESH']
for obj in parts:obj.scale*=3
export('watcher_lamp',parts,1500)
(OUT/'geometry.json').write_text(json.dumps(record,ensure_ascii=False),encoding='utf-8')
