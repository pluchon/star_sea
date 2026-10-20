"""第二轮模型：用蒙皮、布料、曲线、几何节点和刚体生成形状。"""

import math
import random
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

RIGS = []
REVISED = {"statue", "statue_kneel", "statue_broken", "statue_kneel_broken",
           "statue_arm", "statue_arm_broken", "echo_figure", "echo_child",
           "vines", "vines_1", "vine_wall", "rubble", "rubble_1", "rubble_2"}
BONES = {"Root": ((0, 0, 0), (0, 0, .45), None),
         "Spine": ((0, 0, .45), (0, 0, .65), "Root"),
         "Chest": ((0, 0, .65), (0, 0, .81), "Spine"),
         "Neck": ((0, 0, .81), (0, 0, .88), "Chest"),
         "Head": ((0, 0, .88), (0, 0, 1), "Neck"),
         **{name + side: (head, tail, parent + side if parent in ("UpperArm", "Forearm", "Thigh", "Shin") else parent)
            for side, sign in ((".L", -1), (".R", 1))
            for name, head, tail, parent in (
                ("UpperArm", (sign * .085, 0, .80), (sign * .13, .025, .69), "Chest"),
                ("Forearm", (sign * .13, .025, .69), (sign * .065, .15, .72), "UpperArm"),
                ("Hand", (sign * .065, .15, .72), (sign * .035, .18, .72), "Forearm"),
                ("Thigh", (sign * .055, 0, .47), (sign * .055, 0, .25), "Root"),
                ("Shin", (sign * .055, 0, .25), (sign * .055, 0, .045), "Thigh"),
                ("Foot", (sign * .055, 0, .045), (sign * .055, .08, .025), "Shin"))}}


def active(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply(obj, modifier):
    active(obj)
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def normals(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    loose = [vertex for vertex in bm.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()


def simplify(obj, triangles):
    obj.data.calc_loop_triangles()
    count = len(obj.data.loop_triangles)
    if count > triangles:
        mod = obj.modifiers.new("保留大轮廓的减面", "DECIMATE")
        mod.ratio = triangles / count * .98
        apply(obj, mod)
    normals(obj)


def cut(obj, point, normal, fill=False):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    result = bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                                    plane_co=point, plane_no=normal, clear_outer=True, dist=.00001)
    edges = [edge for edge in result["geom_cut"] if isinstance(edge, bmesh.types.BMEdge) and edge.is_boundary]
    if fill and edges:
        bmesh.ops.holes_fill(bm, edges=edges)
    bm.to_mesh(obj.data)
    bm.free()
    normals(obj)


def rig(height):
    data = bpy.data.armatures.new("远行者骨架")
    obj = bpy.data.objects.new("TravelerRig", data)
    bpy.context.collection.objects.link(obj)
    active(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (head, tail, parent) in BONES.items():
        bone = data.edit_bones.new(name)
        bone.head = Vector(head) * height
        bone.tail = Vector(tail) * height
        if parent:
            bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def weight(obj, skeleton, height, hood=False):
    groups = {name: obj.vertex_groups.new(name=name) for name in BONES}
    for vertex in obj.data.vertices:
        point = vertex.co / height
        if hood:
            groups["Head"].add([vertex.index], 1, "REPLACE")
            continue
        # 最近骨段的平滑权重保留袍身连续性，袖子随前臂，裙摆随腿。
        distances = []
        for name, (head, tail, _) in BONES.items():
            if name in ("Root", "Head", "Neck"):
                continue
            a, b = Vector(head), Vector(tail)
            t = max(0, min(1, (point - a).dot(b - a) / (b - a).length_squared))
            distance = (point - a.lerp(b, t)).length
            if point.z < .40 and name.startswith(("UpperArm", "Forearm", "Hand", "Chest")):
                distance += 1
            distances.append((distance, name))
        chosen = sorted(distances)[:3]
        values = [1 / max(distance, .015) ** 4 for distance, _ in chosen]
        total = sum(values)
        for (_, name), value in zip(chosen, values):
            groups[name].add([vertex.index], value / total, "REPLACE")
    mod = obj.modifiers.new("骨骼蒙皮", "ARMATURE")
    mod.object = skeleton
    obj.parent = skeleton


def figure(api, name):
    child = name == "echo_child"
    kneel = name == "statue_kneel"
    echo = name.startswith("echo_")
    height = 1.3 if child else (2.1 if echo else (2.8 if kneel else 4.6))
    # 这里只定义 Skin 的中心线；所有可见面由蒙皮及细分修改器生成。
    points = [(0, 0, -.08), (0, 0, .05), (0, 0, .34), (0, 0, .58),
              (0, 0, .75), (0, 0, .81), (0, 0, .875)]
    edges = [(i, i + 1) for i in range(6)]
    radii = [(.18, .125), (.17, .12), (.13, .105), (.09, .07),
             (.102, .07), (.085, .062), (.045, .045)]
    if kneel:
        points[1] = (0, -.06, .04)
        points[2] = (-.025, .10, .30)
        radii[1], radii[2] = (.22, .17), (.22, .22)
    for sign in (-1, 1):
        start = len(points)
        points.extend([(sign * .13, .018, .76), (sign * .14, .05, .69),
                       (sign * .065, .16, .72), (sign * .035, .185, .735)])
        radii.extend([(.045, .05), (.045, .055), (.063, .066), (.067, .069)])
        edges.extend([(5, start), (start, start + 1), (start + 1, start + 2), (start + 2, start + 3)])
    data = bpy.data.meshes.new("长袍蒙皮中心线")
    data.from_pydata([tuple(Vector(point) * height) for point in points], edges, [])
    robe = bpy.data.objects.new("Robe", data)
    bpy.context.collection.objects.link(robe)
    skin = robe.modifiers.new("连续肩部与袖子的蒙皮", "SKIN")
    for vertex, radius in zip(data.skin_vertices[0].data, radii):
        vertex.radius = Vector(radius) * height
    data.skin_vertices[0].data[4].use_root = True
    apply(robe, skin)
    sub = robe.modifiers.new("圆顺肩部", "SUBSURF")
    sub.levels = 2
    apply(robe, sub)
    cut(robe, (0, 0, .015 * height), (0, 0, -1))
    # 只移去袖口末端的面，不能用穿过全身的平面误切到跪姿膝部。
    bm = bmesh.new()
    bm.from_mesh(robe.data)
    end_faces = [face for face in bm.faces if face.calc_center_median().y > height * .168
                 and height * .60 < face.calc_center_median().z < height * .83]
    bmesh.ops.delete(bm, geom=end_faces, context="FACES")
    bm.to_mesh(robe.data)
    bm.free()
    normals(robe)
    pins = robe.vertex_groups.new(name="固定肩颈")
    pins.add([v.index for v in robe.data.vertices if v.co.z > height * .75], 1, "REPLACE")
    # 以低频位移给布料初始松量，褶皱随后由模拟形成。
    texture = bpy.data.textures.new("袍布初始松量", type="CLOUDS")
    texture.noise_scale = height * .14
    displace = robe.modifiers.new("低频布料松量", "DISPLACE")
    displace.texture = texture
    displace.strength = height * .009
    apply(robe, displace)
    bpy.ops.mesh.primitive_plane_add(size=height * 5)
    ground = bpy.context.object
    ground.modifiers.new("布料地面", "COLLISION")
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, location=(0, 0, height * (.36 if kneel else .52)))
    body = bpy.context.object
    body.scale = (height * .09, height * .065, height * (.32 if kneel else .34))
    if kneel:
        body.location.y = height * .05
        body.scale.y = height * .15
    active(body)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    body.modifiers.new("布料人体碰撞", "COLLISION")
    cloth = robe.modifiers.new("长袍垂坠模拟80帧", "CLOTH")
    cloth.settings.quality = 6
    cloth.settings.mass = .35
    cloth.settings.tension_stiffness = 18
    cloth.settings.compression_stiffness = 18
    cloth.settings.shear_stiffness = 12
    cloth.settings.bending_stiffness = .6
    cloth.settings.vertex_group_mass = "固定肩颈"
    cloth.collision_settings.distance_min = .006
    cloth.collision_settings.use_self_collision = True
    cloth.collision_settings.self_distance_min = .004
    cloth.point_cache.frame_start = 1
    cloth.point_cache.frame_end = 80
    scene = bpy.context.scene
    scene.frame_set(1)
    for frame in range(1, 81):
        scene.frame_set(frame)
    apply(robe, cloth)
    bpy.data.objects.remove(ground, do_unlink=True)
    bpy.data.objects.remove(body, do_unlink=True)
    scene.frame_set(1)
    thick = robe.modifiers.new("敞口布料厚度", "SOLIDIFY")
    thick.thickness = height * .003
    apply(robe, thick)
    simplify(robe, 1750 if echo else 2750)
    api.finish(robe)
    # 开口球壳加实体化形成有厚度的帽檐及深腔。
    hood_height = height * (.17 if child else .13)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=1,
                                       location=(0, 0, height - hood_height * .5))
    hood = bpy.context.object
    hood.name = "HoodShell"
    hood.scale = (hood_height * .48, hood_height * .55, hood_height * .5)
    active(hood)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    cut(hood, (0, hood_height * .25, 0), (0, 1, 0))
    mod = hood.modifiers.new("帽檐外翻的厚度", "SOLIDIFY")
    mod.thickness = height * .008
    mod.offset = -1
    apply(hood, mod)
    normals(hood)
    hood.data.transform(Matrix.Translation((0, 0, -height * .04)))
    shade = hood.data.attributes.new("shade", "FLOAT", "POINT")
    for vertex in hood.data.vertices:
        shade.data[vertex.index].value = .15 if vertex.co.y < hood_height * .10 else .8
    api.finish(hood)
    if not echo:
        api.ring((0, height * .17, height * .70), height * .065, height * .0098, upright=True, steps=24)
    # 规格尺寸在模拟后统一归一，避免不同布料落地帧改变拼装尺度。
    bpy.context.view_layer.update()
    vertices = [obj.matrix_world @ v.co for obj in api.PARTS for v in obj.data.vertices]
    low = Vector(tuple(min(v[i] for v in vertices) for i in range(3)))
    high = Vector(tuple(max(v[i] for v in vertices) for i in range(3)))
    target = Vector((1.6, 1.2, 4.6)) * (height / 4.6)
    target.z = height
    if kneel:
        target.x, target.y = 1.6, 1.2
    for obj in api.PARTS:
        obj.data.transform(obj.matrix_world)
        obj.matrix_world = Matrix.Identity(4)
        for vertex in obj.data.vertices:
            center = Vector(((low.x + high.x) / 2, (low.y + high.y) / 2, low.z))
            vertex.co = Vector((vertex.co[i] - center[i]) * target[i] / (high[i] - low[i]) for i in range(3))
    if echo:
        skeleton = rig(height)
        weight(robe, skeleton, height)
        weight(hood, skeleton, height, hood=True)
        RIGS.append(skeleton)
    else:
        api.COLLISIONS.append({"kind": "box", "size": [target.x * .85, target.y * .85, height], "position": [0, 0, height / 2], "rotation": 0})
    if name == "statue_arm":
        # 切割体通过布尔差集移去一段袖子，保留不规则断缘。
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=.38, location=(.58, .43, 3.30))
        cutter = bpy.context.object
        noise = bpy.data.textures.new("断臂切割噪声", type="CLOUDS")
        noise.noise_scale = .22
        disp = cutter.modifiers.new("破损切割面", "DISPLACE")
        disp.texture, disp.strength = noise, .15
        apply(cutter, disp)
        mod = robe.modifiers.new("缺臂布尔差集", "BOOLEAN")
        mod.operation, mod.object = "DIFFERENCE", cutter
        apply(robe, mod)
        bpy.data.objects.remove(cutter, do_unlink=True)
        for obj in api.PARTS:
            if obj.data.materials[0].name == "patina":
                center = sum((v.co for v in obj.data.vertices), Vector()) / len(obj.data.vertices)
                obj.data.transform(Matrix.Translation(-center))
                obj.location = (1.05, .1, .12)
                obj.rotation_euler.x = math.pi / 2


def vines(api, name, seed):
    rng = random.Random(seed)
    width, height = {"vines": (2, 1.8), "vines_1": (1.2, 2.6), "vine_wall": (3, 6)}[name]
    # 叶片用圆面挤压、比例变形和弯曲工具建模，不手写三角形。
    bpy.ops.mesh.primitive_circle_add(vertices=6, radius=1, fill_type="NGON")
    leaf = bpy.context.object
    leaf.name = "心形叶片原型"
    for vertex in leaf.data.vertices:
        vertex.co.x *= .085
        vertex.co.y *= .14
        vertex.co.z = .025 * (1 - abs(vertex.co.x) / .085)
        if vertex.co.y < -.10:
            vertex.co.y *= .55
    leaf.rotation_euler.x = math.pi / 2
    active(leaf)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    leaf.data.materials.append(api.MATERIALS["cloth"])
    for index in range(5 if name == "vine_wall" else 3):
        curve = bpy.data.curves.new("贴墙生长曲线", "CURVE")
        curve.dimensions = "3D"
        curve.resolution_u = 1
        curve.bevel_depth = .04 if name == "vine_wall" and index < 2 else .016
        curve.bevel_resolution = 0
        spline = curve.splines.new("BEZIER")
        spline.bezier_points.add(5)
        for j, point in enumerate(spline.bezier_points):
            t = j / 5
            point.co = ((index / (4 if name == "vine_wall" else 2) - .5) * width * .68 + math.sin(t * 7 + index) * width * .14,
                        .06 if name == "vine_wall" and index < 2 else .035,
                        height * (1 - t if name == "vines_1" else t))
            point.radius = 1 - t * .7
            point.handle_left_type = point.handle_right_type = "AUTO"
        obj = bpy.data.objects.new("主藤", curve)
        bpy.context.collection.objects.link(obj)
        curve.materials.append(api.MATERIALS["cloth"])
        active(obj)
        bpy.ops.object.convert(target="MESH")
        api.finish(bpy.context.object, "cloth")
        # 几何节点沿相同路径取点、实例化叶片，再实现实例后导出。
        carrier_data = curve.copy()
        carrier_data.bevel_depth = 0
        carrier = bpy.data.objects.new("几何节点叶簇", carrier_data)
        bpy.context.collection.objects.link(carrier)
        tree = bpy.data.node_groups.new("沿藤分布叶片", "GeometryNodeTree")
        tree.interface.new_socket(name="Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
        tree.interface.new_socket(name="Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
        nodes, links = tree.nodes, tree.links
        entry, output = nodes.new("NodeGroupInput"), nodes.new("NodeGroupOutput")
        sample = nodes.new("GeometryNodeCurveToPoints")
        sample.mode = "COUNT"
        sample.inputs["Count"].default_value = int(height / .045)
        info = nodes.new("GeometryNodeObjectInfo")
        info.inputs["Object"].default_value = leaf
        instance = nodes.new("GeometryNodeInstanceOnPoints")
        rotation = nodes.new("FunctionNodeRandomValue")
        rotation.data_type = "FLOAT_VECTOR"
        rotation.inputs["Min"].default_value = (-.25, -1.0, -.25)
        rotation.inputs["Max"].default_value = (.25, 1.0, .25)
        rotation.inputs["Seed"].default_value = seed % 100000 + index
        scale = nodes.new("FunctionNodeRandomValue")
        scale.data_type = "FLOAT"
        scale.inputs["Min"].default_value = .7
        scale.inputs["Max"].default_value = 1.3
        scale.inputs["Seed"].default_value = seed % 10000 + index
        realize = nodes.new("GeometryNodeRealizeInstances")
        offset = nodes.new("GeometryNodeSetPosition")
        jitter = nodes.new("FunctionNodeRandomValue")
        jitter.data_type = "FLOAT_VECTOR"
        jitter.inputs["Min"].default_value = (-.085, 0, -.03)
        jitter.inputs["Max"].default_value = (.085, 0, .03)
        jitter.inputs["Seed"].default_value = seed % 10000 + index
        links.new(entry.outputs["Geometry"], sample.inputs["Curve"])
        links.new(sample.outputs["Points"], offset.inputs["Geometry"])
        links.new(jitter.outputs["Value"], offset.inputs["Offset"])
        links.new(offset.outputs["Geometry"], instance.inputs["Points"])
        links.new(info.outputs["Geometry"], instance.inputs["Instance"])
        links.new(rotation.outputs["Value"], instance.inputs["Rotation"])
        links.new(scale.outputs["Value"], instance.inputs["Scale"])
        links.new(instance.outputs["Instances"], realize.inputs["Geometry"])
        links.new(realize.outputs["Geometry"], output.inputs["Geometry"])
        modifier = carrier.modifiers.new("叶片实例化", "NODES")
        modifier.node_group = tree
        active(carrier)
        bpy.ops.object.convert(target="MESH")
        leaves = bpy.context.object
        # 开放叶面的法线统一朝墙外；圆截面藤条保留径向法线。
        bm = bmesh.new()
        bm.from_mesh(leaves.data)
        for face in bm.faces:
            if face.normal.y < 0:
                face.normal_flip()
        bm.to_mesh(leaves.data)
        bm.free()
        api.finish(leaves, "cloth")
    bpy.data.objects.remove(leaf, do_unlink=True)
    # 归一范围，保留背面至少一厘米间隙。
    verts = [v for obj in api.PARTS for v in obj.data.vertices]
    low, high = [min(v.co[i] for v in verts) for i in range(3)], [max(v.co[i] for v in verts) for i in range(3)]
    for vertex in verts:
        vertex.co.x = (vertex.co.x - (low[0] + high[0]) / 2) * width / (high[0] - low[0])
        vertex.co.z = (vertex.co.z - low[2]) * height / (high[2] - low[2])
        vertex.co.y = .015 + (vertex.co.y - low[1]) * (.095 if name == "vine_wall" else .07) / (high[1] - low[1])


def rubble(api, seed):
    rng = random.Random(seed)
    scene = bpy.context.scene
    scene.frame_set(1)
    bpy.ops.mesh.primitive_plane_add(size=12)
    ground = bpy.context.object
    bpy.ops.rigidbody.object_add()
    ground.rigid_body.type = "PASSIVE"
    stones = []
    for index in range(16):
        radius = .46 if index < 3 else (.29 if index < 7 else .14)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius,
                                           location=(rng.uniform(-.9, .9), rng.uniform(-.7, .7), 1 + index * .25))
        obj = bpy.context.object
        obj.name = "建筑残石" if index < 3 else "自然碎石"
        obj.scale = (rng.uniform(.8, 1.4), rng.uniform(.6, 1.1), rng.uniform(.65, 1.1))
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        remesh = obj.modifiers.new("体素重建岩石", "REMESH")
        remesh.mode = "VOXEL"
        remesh.voxel_size = radius * .22
        apply(obj, remesh)
        texture = bpy.data.textures.new("岩石低频噪声", type="VORONOI")
        texture.noise_scale = radius * .9
        disp = obj.modifiers.new("岩石轮廓位移", "DISPLACE")
        disp.texture, disp.strength = texture, radius * .25
        apply(obj, disp)
        if index < 3:
            cut(obj, (radius * .4, 0, 0), (1, 0, 0), fill=True)
        simplify(obj, 60 if index < 7 else 32)
        obj.rotation_euler = (rng.random(), rng.random(), rng.random() * math.tau)
        active(obj)
        bpy.ops.rigidbody.object_add()
        obj.rigid_body.mass = radius * 10
        obj.rigid_body.friction = .85
        obj.rigid_body.use_margin = True
        obj.rigid_body.collision_margin = .002
        obj.rigid_body.linear_damping = .7
        obj.rigid_body.angular_damping = .8
        api.finish(obj)
        stones.append(obj)
    scene.rigidbody_world.substeps_per_frame = 8
    scene.rigidbody_world.solver_iterations = 20
    scene.rigidbody_world.point_cache.frame_end = 180
    for frame in range(1, 181):
        scene.frame_set(frame)
    matrices = [obj.matrix_world.copy() for obj in stones]
    for index, (obj, transform) in enumerate(zip(stones, matrices)):
        active(obj)
        bpy.ops.rigidbody.object_remove()
        obj.matrix_world = transform
        obj.data.transform(obj.matrix_world)
        obj.matrix_world = Matrix.Identity(4)
        if index < 7:
            bm = bmesh.new()
            bm.from_mesh(obj.data)
            bmesh.ops.convex_hull(bm, input=list(bm.verts))
            points = [list(v.co) for v in bm.verts if v.link_faces]
            bm.free()
            # 先减面后的石块至多32个顶点，满足凸包碰撞预算。
            api.COLLISIONS.append({"kind": "convex", "points": points[:32]})
    bpy.data.objects.remove(ground, do_unlink=True)
    scene.frame_set(1)
    minimum = min(v.co.z for obj in stones for v in obj.data.vertices)
    for obj in stones:
        for vertex in obj.data.vertices:
            vertex.co.z -= minimum
    for record in api.COLLISIONS:
        for point in record["points"]:
            point[2] -= minimum


def is_revised(name):
    return name in REVISED


def build(api, name):
    if name not in REVISED:
        return False
    seed = 20261021 + sum((index + 1) * byte for index, byte in enumerate(name.encode()))
    if name.startswith("rubble"):
        rubble(api, seed)
    elif name.startswith("vines") or name == "vine_wall":
        vines(api, name, seed)
    else:
        figure(api, name)
    return True


def preview(name, parts, output):
    """四个固定机位先在 EEVEE 中检查，保留原始 blend 供追溯。"""
    directory = Path("test-output/models")
    directory.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 384
    scene.render.resolution_y = 512
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.world.color = (.22, .22, .22)
    for obj in parts:
        if obj.data.materials[0].name == "cloth":
            obj.data.materials[0].diffuse_color = (.06, .22, .045, 1)
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    points = [obj.matrix_world @ v.co for obj in parts for v in obj.data.vertices]
    low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    target = (low + high) / 2
    size = max(high.z - low.z, high.x - low.x, 1)
    bpy.ops.object.light_add(type="SUN", rotation=(.45, -.6, -.4))
    bpy.context.object.data.energy = 2.2
    for obj in list(scene.objects):
        if obj.type == "MESH" and obj not in parts:
            obj.hide_render = True
    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = size * 1.45
    scene.camera = camera
    canvas = bpy.data.images.new(name + "四视图", width=1536, height=512)
    pixels = [0.0] * (1536 * 512 * 4)
    bpy.ops.wm.save_as_mainfile(filepath=str((directory / (name + ".blend")).resolve()))
    for index, direction in enumerate(((0, 1, .1), (1, 0, .1), (0, -1, .1), (.8, 1, .2))):
        camera.location = target + Vector(direction).normalized() * size * 3
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str((directory / (name + "-" + str(index) + ".png")).resolve())
        bpy.ops.render.render(write_still=True)
        image = bpy.data.images.load(scene.render.filepath, check_existing=False)
        source = list(image.pixels)
        for row in range(512):
            start = (row * 1536 + index * 384) * 4
            pixels[start:start + 384 * 4] = source[row * 384 * 4:(row + 1) * 384 * 4]
        bpy.data.images.remove(image)
    canvas.pixels = pixels
    canvas.filepath_raw = str((directory / (name + ".png")).resolve())
    canvas.file_format = "PNG"
    canvas.save()
    bpy.data.images.remove(canvas)
