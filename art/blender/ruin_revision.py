"""构件修订的几何算法；由 build_ruin_kit 注入共用的材质、导出与碰撞约定。"""

import math
import random

import bpy
import bmesh
from mathutils import Vector, Matrix


def mesh(api, name, vertices, faces, kind="stone", ao=None):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    if ao is not None:
        attr = data.attributes.new("shade", "FLOAT", "POINT")
        for value in attr.data:
            value.value = ao
    return api.finish(obj, kind)


def origin(obj, point):
    point = Vector(point)
    obj.data.transform(Matrix.Translation(-point))
    obj.location = point


def occlude(obj):
    """连续内芯在砌缝处显露，保持一厘米凹槽，不留下贯穿墙体的孔隙。"""
    attr = obj.data.attributes.new("shade", "FLOAT", "POINT")
    for value in attr.data:
        value.value = .6
    return obj


def sweep(api, name, centers, radii, kind="stone", sides=10, hollow=False):
    vertices, faces = [], []
    for row, (center, radius) in enumerate(zip(centers, radii)):
        center = Vector(center)
        tangent = Vector(centers[min(row + 1, len(centers) - 1)]) - Vector(centers[max(row - 1, 0)])
        tangent.normalize()
        right = tangent.cross(Vector((0, 1, 0))).normalized()
        across = tangent.cross(right).normalized()
        for col in range(sides):
            angle = col * math.tau / sides
            vertices.append(center + radius * (right * math.cos(angle) + across * math.sin(angle)))
        if row:
            for col in range(sides):
                a, b = (row - 1) * sides + col, (row - 1) * sides + (col + 1) % sides
                faces.append((a, b, b + sides, a + sides))
    faces.append(tuple(reversed(range(sides))))
    if hollow:
        # 袖口有厚度和向内延伸的腔体，不用圆盘封住开口。
        outer = len(vertices) - sides
        center = Vector(centers[-1])
        tangent = (center - Vector(centers[-2])).normalized()
        for index in range(sides):
            vertices.append(center + (vertices[outer + index] - center) * .77)
        for index in range(sides):
            vertices.append(vertices[outer + sides + index] - tangent * radii[-1] * .8)
        for index in range(sides):
            next_index = (index + 1) % sides
            faces.append((outer + index, outer + next_index, outer + sides + next_index, outer + sides + index))
            faces.append((outer + sides + index, outer + sides + next_index, outer + 2 * sides + next_index, outer + 2 * sides + index))
        faces.append(tuple(range(outer + 2 * sides, outer + 3 * sides)))
    else:
        faces.append(tuple(range(len(vertices) - sides, len(vertices))))
    return mesh(api, name, vertices, faces, kind)


def figure(api, height, kneel=False, echo=False, child=False, missing_arm=False):
    scale = height / (2.8 if kneel else 4.6)
    h = 2.8 if kneel else 4.6
    hood_size = h / (6 if child else (5.2 if kneel else 8.5))
    neck = h - hood_size * .95
    shoulders = neck + hood_size * .12
    vertices, faces = [], []
    # 截面同时控制肩、腰、裙摆；五道大褶逐渐向下放宽。
    profiles = [(0, .80), (.07, .76), (.35, .70), (.8, .61), (1.4, .48),
                (2.1, .36), (2.8, .33), (3.45, .41), (3.85, .46), (4.13, .24)]
    for row, (z, radius) in enumerate(profiles):
        if kneel:
            z *= (shoulders + .08) / 4.13
        elif child:
            z *= (shoulders + .08) / 4.13
        for col in range(32):
            angle = col * math.tau / 32
            fold = .035 * (1 - z / h * .7) * math.cos(angle * 5 + .3)
            r = radius + fold
            x, y = r * math.cos(angle), r * .75 * math.sin(angle)
            if kneel:
                # 一膝立起、一膝后移，长袍连续覆盖膝部。
                y += .18 * z / h + .32 * max(0, math.cos(angle)) * max(0, 1 - z / 1.6)
                x *= 1.0 - .14 * z / h
                y += .48 * math.exp(-((z - .75) / .43) ** 2) * max(0, math.sin(angle)) * max(0, math.cos(angle) + .35)
            base = .15 if child and row == 0 else z
            vertices.append((x * scale, y * scale, (base + (.018 * (1 + math.cos(angle * 6)) if row == 0 and not child else 0)) * scale))
        if row:
            for col in range(32):
                a = (row - 1) * 32 + col
                b = (row - 1) * 32 + (col + 1) % 32
                faces.append((a, b, b + 32, a + 32))
    faces.extend([tuple(reversed(range(32))), tuple(range(len(vertices) - 32, len(vertices)))])
    robe = mesh(api, "Robe", vertices, faces)
    origin(robe, (0, .08 * scale if kneel else 0, h * .48 * scale))
    # 开口兜帽从圆润后脑向前伸出，内层向后收拢成深腔，没有面部。
    vertices, faces, shades = [], [], []
    center = h - hood_size * .5
    for row, (depth, radius, shade) in enumerate([(-.34, .08, .9), (-.22, .78, .9), (0, 1, .9),
                                               (.32, .94, .9), (.42, .97, .95), (.43, .76, .6),
                                               (.32, .72, .15), (.06, .56, .15), (-.02, .03, .15)]):
        for col in range(24):
            angle = col * math.tau / 24
            x = math.cos(angle) * hood_size * .49 * radius * (.9 + .1 * math.sin(angle))
            z = center + math.sin(angle) * hood_size * .5 * radius
            if not child:
                z += .07 * max(math.sin(angle), 0) ** 8 * radius
            y = depth * hood_size / .54 + (.19 if kneel else 0)
            vertices.append((x * scale, y * scale, min(h, z) * scale))
            shades.append(shade)
        if row:
            for col in range(24):
                a, b = (row - 1) * 24 + col, (row - 1) * 24 + (col + 1) % 24
                faces.append((a, a + 24, b + 24, b))
    hood = mesh(api, "Head", vertices, faces)
    attr = hood.data.attributes.new("shade", "FLOAT", "POINT")
    for item, shade in zip(attr.data, shades):
        item.value = shade
    origin(hood, (0, (.19 if kneel else 0) * scale, neck * scale))
    if kneel:
        hood.rotation_euler.x = -.16
    for side in (-1, 1):
        points = [(side * .40, .02, shoulders), (side * .52, .06, shoulders - .25),
                  (side * .58, .14, shoulders - .57), (side * .44, .38, shoulders - .67),
                  (side * .27, .49, shoulders - .62)]
        if missing_arm and side == 1:
            points = points[:3]
        obj = sweep(api, "ArmLeft" if side < 0 else "ArmRight",
                    [tuple(value * scale for value in point) for point in points],
                    [radius * scale for radius in [.16, .17, .18, .22, .256][:len(points)]], sides=14, hollow=not (missing_arm and side == 1))
        origin(obj, tuple(value * scale for value in points[0]))
        if missing_arm and side == 1:
            attr = obj.data.attributes.new("shade", "FLOAT", "POINT")
            for vertex in obj.data.vertices[-14:]:
                vertex.co.z += scale * (.035 * math.sin(vertex.co.x * 51) + .025 * math.sin(vertex.co.y * 47))
                attr.data[vertex.index].value = 1.08
    if child:
        for side in (-1, 1):
            api.box((side * .22 * scale, .03 * scale, .075 * scale), (.23 * scale, .36 * scale, .15 * scale), collision=False)
            extra = api.PARTS.pop()
            # 足部并入长袍节点，使动作节点数量保持四个。
            bpy.ops.object.select_all(action="DESELECT")
            robe.select_set(True)
            extra.select_set(True)
            bpy.context.view_layer.objects.active = robe
            bpy.ops.object.join()
    if not echo:
        api.ring((1.05, .10, .055) if missing_arm else (0, .46 * scale, (shoulders - .80) * scale), .30 * scale, .045 * scale, upright=not missing_arm, steps=24)
    if not echo:
        api.COLLISIONS.append({"kind": "box", "size": [1.4 * scale, 1.1 * scale, height], "position": [0, 0, height / 2], "rotation": 0})
    if missing_arm:
        for index in range(4):
            rock(api, ((index - 1.5) * .28, -.35, .10), (.28, .24, .20), 101 + index, collision=True)
    for obj in api.PARTS:
        for vertex in obj.data.vertices:
            vertex.co.y *= .9
        obj.location.y *= .9


def rock(api, position, size, seed, collision=True, detailed=False, scattered=False):
    rng = random.Random(seed)
    bpy.ops.mesh.primitive_cube_add(size=1, location=position)
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for index in range(3 if detailed else rng.randint(3, 6)):
        sign = Vector(tuple(rng.choice((-1, 1)) for _ in range(3)))
        corner = Vector(tuple(sign[i] * size[i] * .5 for i in range(3)))
        normal = Vector(tuple(sign[i] / size[i] for i in range(3))).normalized()
        cut = corner - normal * min(size) * rng.uniform(.10, .35)
        result = bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                                       plane_co=cut, plane_no=normal, clear_outer=True, dist=.00001)
        edges = [edge for edge in result["geom_cut"] if isinstance(edge, bmesh.types.BMEdge) and edge.is_boundary]
        if edges:
            bmesh.ops.holes_fill(bm, edges=edges)
    if scattered:
        obj.rotation_euler = (rng.uniform(-.22, .22), rng.uniform(-.22, .22), rng.uniform(0, math.tau))
        bpy.context.view_layer.update()
    collision_points = [list(obj.matrix_world @ vertex.co) for vertex in bm.verts]
    if detailed:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(size) * .04, segments=1, affect="EDGES")
    if scattered:
        # 倾斜后按实际倒角轮廓贴地，不能按原始盒子的高度放置。
        minimum = min((obj.matrix_world @ vertex.co).z for vertex in bm.verts)
        obj.location.z -= minimum
        for point in collision_points:
            point[2] -= minimum
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    api.finish(obj)
    if collision:
        api.COLLISIONS.append({"kind": "convex", "points": collision_points})
    return obj


def rubble(api, seed):
    rng = random.Random(seed)
    for index in range(16):
        if index < 2:
            length = rng.uniform(.8, 1.25)
            x, y = ((-.42, .05), (.43, .32))[index]
        else:
            length = rng.uniform(.3, .65) if index < 6 else rng.uniform(.10, .24)
            angle = index * 2.399
            distance = rng.uniform(.65, 1.45)
            x, y = math.cos(angle) * distance, math.sin(angle) * distance
        size = (length, length * rng.uniform(.65, .9), length * rng.uniform(.5, .8))
        rock(api, (x, y, size[2] * .5), size, seed + index * 19, collision=index < 6, detailed=index < 2, scattered=True)


def vines(api, name, seed):
    rng = random.Random(seed)
    width, height = {"vines": (2, 1.8), "vines_1": (1.2, 2.6), "vine_wall": (3, 6)}[name]
    hanging = name == "vines_1"
    vertices, faces = [], []

    def ribbon(points, thickness):
        start = len(vertices)
        for index, point in enumerate(points):
            taper = 1 - index / max(1, len(points) - 1) * .8
            vertices.extend([(point[0] - thickness * taper * .5, point[1], point[2]),
                             (point[0] + thickness * taper * .5, point[1], point[2])])
            if index:
                a = start + index * 2 - 2
                faces.append((a, a + 1, a + 3, a + 2))

    for stem in range(4):
        maximum = height * (1 if stem == 1 else rng.uniform(.70, .94))
        count = round(maximum / .15)
        points = []
        for index in range(count + 1):
            t = index / count
            x = (stem / 3 - .5) * width * .57 + math.sin(t * 7 + stem) * width * .07
            z = maximum * t
            points.append((x, .015, height - z if hanging else z))
        ribbon(points, .06 if name != "vine_wall" else .08)
        if name == "vine_wall":
            sweep(api, "攀爬粗藤", [(x, .10, z) for x, y, z in points[::3]], [.02] * len(points[::3]), "cloth", sides=6)
        for index in range(2, len(points) - 2, 3):
            x, y, z = points[index]
            direction = rng.choice((-1, 1))
            branch = min(width * .22, rng.uniform(.2, .6))
            ribbon([(x, y, z), (x + branch * direction * .6, y, z + .08), (x + branch * direction, y, z + .13)], .025)
            # 下部叶簇更密；菱形叶沿侧藤向外翘起。
            leaves = 5 if index < len(points) * .55 else 3
            for leaf in range(leaves):
                cx = x + direction * branch * (leaf + 1) / (leaves + 1)
                cz = z + .1 + (leaf % 2 - .5) * .13
                length = rng.uniform(.13, .22)
                start = len(vertices)
                tip = direction * (1 if leaf % 2 else -1)
                vertices.extend([(cx, .018, cz - length * .3), (cx + length * .42, .04, cz),
                                 (cx + tip * length * .4, .018 + length * .35, cz + length), (cx - length * .42, .04, cz)])
                faces.append(tuple(range(start, start + 4)))
    # 最外两片叶给出约定宽度，平铺边界不依赖随机结果。
    for side in (-1, 1):
        start = len(vertices)
        vertices.extend([(side * width * .5, .025, height * .22), (side * (width * .5 - .12), .06, height * .22 + .1),
                         (side * (width * .5 - .25), .02, height * .22)])
        faces.append((start, start + 1, start + 2))
    for index, (x, y, z) in enumerate(vertices):
        vertices[index] = (max(-width / 2, min(width / 2, x)), y, max(0, min(height, z)))
    mesh(api, name, vertices, faces, "cloth")


def masonry(api, width, depth, height, arc=False, low=False):
    rows = max(1, round((height - .3) / .75))
    api.box((0, 0, .15), (width, depth, .3), collision=False)
    core = occlude(api.box((0, 0, (.3 + height - .15) / 2), (width - .03, depth - .12, height - .45), collision=False))
    for vertex in core.data.vertices:
        if vertex.co.y > 0:
            vertex.co.y += .05 - .10 * (vertex.co.z + core.location.z) / height
    for row in range(rows):
        bottom = .3 + row * (height - .45) / rows
        top = .3 + (row + 1) * (height - .45) / rows
        edges = [-width / 2]
        x = -width / 2 + (.65 if row % 2 else 1.05)
        while x < width / 2 - .15:
            edges.append(x)
            x += .95
        edges.append(width / 2)
        for left, right in zip(edges, edges[1:]):
            obj = api.box(((left + right) / 2, 0, (bottom + top) / 2), (right - left - .015, depth - .10, top - bottom - .015), collision=False)
            for vertex in obj.data.vertices:
                z = vertex.co.z + obj.location.z
                # 内侧保持竖直，外侧从底部到顶部收分十厘米。
                if vertex.co.y > 0:
                    vertex.co.y += .05 - .10 * z / height
    api.box((0, 0, height - .075), (width, depth - .06, .15), collision=False)
    if arc:
        for obj in api.PARTS:
            for vertex in obj.data.vertices:
                p = obj.matrix_world @ vertex.co
                angle = p.x / 5
                q = Vector(((5 + p.y) * math.sin(angle), (5 + p.y) * math.cos(angle) - 5, p.z))
                vertex.co = obj.matrix_world.inverted() @ q
    api.COLLISIONS.append({"kind": "box", "size": [width, depth, height], "position": [0, 0, height / 2], "rotation": 0})


def fracture(api, seed, fraction=.78):
    """先斜切再细分断面，沿共享边扰动；边缘崩缺和碎块使用固定种子。"""
    rng = random.Random(seed)
    bpy.context.view_layer.update()
    points = [obj.matrix_world @ vertex.co for obj in api.PARTS for vertex in obj.data.vertices]
    low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    size = high - low
    angle = rng.uniform(0, math.tau)
    slope = math.tan(math.radians(rng.uniform(15, 40)))
    normal = Vector((math.cos(angle) * slope, math.sin(angle) * slope, 1)).normalized()
    plane = Vector((0, 0, low.z + size.z * fraction))
    amplitude = min(size.y, size.x, size.z) * .17
    for obj in list(api.PARTS):
        if obj.data.materials[0].name == "glyph":
            # 光纹跟随承载表面的缺失，不允许留在断口上。
            if any((obj.matrix_world @ v.co - plane).dot(normal) > -.06 for v in obj.data.vertices):
                api.PARTS.remove(obj)
                bpy.data.objects.remove(obj, do_unlink=True)
            continue
        obj.data.transform(obj.matrix_world)
        obj.matrix_world = Matrix.Identity(4)
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        if all((v.co - plane).dot(normal) > 0 for v in bm.verts):
            bm.free()
            api.PARTS.remove(obj)
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        cut = bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), plane_co=plane, plane_no=normal, clear_outer=True, dist=.00001)
        edges = [edge for edge in cut["geom_cut"] if isinstance(edge, bmesh.types.BMEdge) and edge.is_boundary]
        if edges:
            cap = bmesh.ops.holes_fill(bm, edges=edges)["faces"]
            cap_edges = sorted({edge for face in cap for edge in face.edges}, key=lambda edge: tuple(sorted(tuple(round(value, 6) for value in vertex.co) for vertex in edge.verts)))
            bmesh.ops.subdivide_edges(bm, edges=cap_edges, cuts=2, use_grid_fill=True)
            shade = bm.verts.layers.float.get("shade") or bm.verts.layers.float.new("shade")
            for v in bm.verts:
                if abs((v.co - plane).dot(normal)) < .0001:
                    wave = math.sin(v.co.x * 8 + seed) * .55 + math.sin(v.co.y * 13 + v.co.x * 4) * .35 + math.sin(v.co.x * 39 + v.co.y * 23) * .10
                    v.co.z = max(low.z + .02, min(high.z, v.co.z + wave * amplitude))
                    v[shade] = 1.08
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(obj.data)
        bm.free()
    # 保留门洞、桥洞的分段碰撞，同时裁去断面以上的碰撞。
    existing = api.export_collisions("断面")
    api.COLLISIONS.clear()
    for obj in existing:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        for vertex in bm.verts:
            vertex.co = obj.matrix_world @ vertex.co
        bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), plane_co=plane, plane_no=normal, clear_outer=True, dist=.00001)
        if len(bm.verts) >= 4:
            if obj.name.endswith("-colonly"):
                bmesh.ops.triangulate(bm, faces=list(bm.faces))
                points = [list(v.co) for face in bm.faces for v in face.verts]
                for start in range(0, len(points), 64 * 3):
                    api.COLLISIONS.append({"kind": "faces", "points": points[start:start + 64 * 3]})
            else:
                points = [list(v.co) for v in bm.verts]
                if len(points) > 32:
                    # 最远点采样保留凸包轮廓，三维凸包最多 2V-4 个三角形。
                    selected = [points[0]]
                    while len(selected) < 32:
                        point = max(points, key=lambda p: min((Vector(p) - Vector(q)).length_squared for q in selected))
                        selected.append(point)
                    points = selected
                api.COLLISIONS.append({"kind": "convex", "points": points})
        bm.free()
        bpy.data.objects.remove(obj, do_unlink=True)
    debris_count = rng.randint(2, 5)
    length = (max(.0001, size.x * size.y * size.z * (1 - fraction) * .3 / debris_count) / .56) ** (1 / 3)
    for index in range(debris_count):
        extent = Vector((min(size.x * .5, length), min(size.y * .75, length * .8), min(size.z * .4, length * .7)))
        x = (low.x + high.x) * .5 + rng.uniform(-1, 1) * max(0, size.x * .6 - extent.x * .5)
        y = (low.y + high.y) * .5 + rng.uniform(-1, 1) * max(0, size.y * .6 - extent.y * .5)
        rock(api, (x, y, extent.z * .5), tuple(extent), seed + index, collision=max(extent) > .22)


def revise(api, name):
    seed = 20261020 + sum((index + 1) * byte for index, byte in enumerate(name.encode()))
    if name in ("statue", "statue_kneel", "echo_figure", "echo_child", "statue_arm"):
        figure(api, 2.8 if name == "statue_kneel" else (1.3 if name == "echo_child" else (2.1 if name == "echo_figure" else 4.6)),
               kneel=name == "statue_kneel", echo=name.startswith("echo"), child=name == "echo_child", missing_arm=name == "statue_arm")
    elif name.startswith("rubble"):
        rubble(api, seed)
    elif name in ("vines", "vines_1", "vine_wall"):
        vines(api, name, seed)
    elif name in ("wall", "wall_arc", "wall_low"):
        masonry(api, 2.6 if name == "wall_arc" else 2, .5 if name == "wall_low" else .6, 1 if name == "wall_low" else 3.6, arc=name == "wall_arc")
    elif name == "plinth":
        masonry(api, 8, 8, 1.2)
    elif name == "plinth_round":
        api.cylinder((0, 0, .15), 5, .3, sides=32)
        for row in range(2):
            for col in range(16):
                begin = col * math.tau / 16 + (row % 2) * math.pi / 16
                api.ring((0, 0, .3 + (row + .5) * .45), 4.72, .22, "stone", start=begin + .0015, end=begin + math.tau / 16 - .0015, steps=2)
        occlude(api.cylinder((0, 0, .75), 4.93, .9, collision=False, sides=32))
    elif name == "column_fallen":
        for index in range(3):
            obj = api.cylinder(((index - 1) * 1.43, 0, .31), .29, 1.28, collision=False, sides=16)
            for v in obj.data.vertices:
                if abs(v.co.z) > .5:
                    v.co.z += .08 * math.sin(v.co.x * 35 + index) + .04 * math.sin(v.co.y * 59)
            obj.rotation_euler.y = math.pi / 2
            bpy.context.view_layer.update()
            api.COLLISIONS.append({"kind": "convex", "points": [list(obj.matrix_world @ v.co) for v in obj.data.vertices]})
    elif name == "column":
        api.cylinder((0, 0, .10), .35, .20)
        api.cylinder((0, 0, .28), .30, .16)
        centers = [(0, 0, .36 + index * 3.48 / 8) for index in range(9)]
        sweep(api, "卷杀柱身", centers, [.222 * (1 + .03 * math.sin(index * math.pi / 8)) for index in range(9)], sides=16)
        api.COLLISIONS.append({"kind": "cylinder", "radius": .23, "height": 3.48, "position": [0, 0, 2.1]})
        api.ring((0, 0, 3.91), .247, .053, "stone")
        api.box((0, 0, 4.11), (.7, .7, .18))
    else:
        return False
    return True


def refine_fractures(api, target):
    """只细分断面，不能用不可见底面凑足残破件的面数。"""
    for obj in api.PARTS:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        bm.to_mesh(obj.data)
        bm.free()
    count = sum(len(obj.data.polygons) for obj in api.PARTS)
    for attempt in range(8):
        if count >= target:
            return
        previous = count
        for obj in api.PARTS:
            if count >= target:
                return
            bm = bmesh.new()
            bm.from_mesh(obj.data)
            shade = bm.verts.layers.float.get("shade")
            candidates = [face for face in bm.faces if shade and any(v[shade] > 1.02 for v in face.verts)]
            chosen = candidates[:max(0, math.ceil((target - count) / 2))]
            if chosen:
                result = bmesh.ops.poke(bm, faces=chosen)
                for vertex in result["verts"]:
                    vertex.co.z -= .003 * (1 + math.sin(vertex.co.x * 41 + vertex.co.y * 37))
                bm.to_mesh(obj.data)
            bm.free()
            count = sum(len(part.data.polygons) for part in api.PARTS)
        if count == previous:
            break
    if count < target:
        raise RuntimeError("断面细分不足，不能满足残破构件的几何检查")
