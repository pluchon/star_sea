"""生成远行者构件与同源程序化网格数据；所有尺寸以米为单位。"""

import argparse
import json
import math
from pathlib import Path
import random
import struct
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
import ruin_revision as revision
import ruin_modeling as modeling

import bpy
import bmesh
from mathutils import Vector

COLORS = {"stone": (0.67, .57, .37, 1), "patina": (.11, .26, .23, 1),
          "glyph": (.89, .46, .10, 1), "cloth": (.46, .13, .07, 1)}
MATERIALS = {}
PARTS = []
COLLISIONS = []


def repair_vertex_colors(path, samples):
    """根据最终顶点位置校正导出文件中的 RGBA 通道，避免黑斑。"""
    payload = bytearray(path.read_bytes())
    json_size = struct.unpack_from("<I", payload, 12)[0]
    document = json.loads(payload[20:20 + json_size])
    binary_start = 28 + json_size
    buckets = {}
    for point, rgba in (samples or {}).items():
        key = tuple(round(value * 1000) for value in point)
        buckets.setdefault(key, []).append((point, rgba))

    def nearest_color(point):
        exact = (samples or {}).get(tuple(round(value, 5) for value in point))
        if exact is not None:
            return exact
        key = tuple(round(value * 1000) for value in point)
        candidates = [item for x in (-1, 0, 1) for y in (-1, 0, 1) for z in (-1, 0, 1)
                      for item in buckets.get((key[0] + x, key[1] + y, key[2] + z), [])]
        if not candidates:
            raise ValueError("导出顶点没有对应颜色：" + str(point))
        return min(candidates, key=lambda item: sum((a - b) ** 2 for a, b in zip(point, item[0])))[1]

    def layout(index):
        accessor = document["accessors"][index]
        view = document["bufferViews"][accessor["bufferView"]]
        return accessor, view, binary_start + view.get("byteOffset", 0) + accessor.get("byteOffset", 0)

    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            attributes = primitive["attributes"]
            if "COLOR_0" not in attributes:
                continue
            positions, position_view, position_start = layout(attributes["POSITION"])
            colors, color_view, color_start = layout(attributes["COLOR_0"])
            if positions["componentType"] != 5126 or positions["count"] != colors["count"]:
                raise ValueError("顶点位置与颜色数量不一致：" + str(path))
            code, maximum = {5121: ("B", 255), 5123: ("H", 65535), 5126: ("f", 1)}[colors["componentType"]]
            color_size = struct.calcsize("<4" + code)
            for index in range(positions["count"]):
                point = struct.unpack_from("<3f", payload, position_start + index * position_view.get("byteStride", 12))
                rgba = nearest_color(point)
                values = rgba if code == "f" else tuple(round(value * maximum) for value in rgba)
                struct.pack_into("<4" + code, payload, color_start + index * color_view.get("byteStride", color_size), *values)
    path.write_bytes(payload)


def finish(obj, kind="stone"):
    obj.data.materials.append(MATERIALS[kind])
    PARTS.append(obj)
    return obj


def box(position, size, kind="stone", rotation=0, collision=True):
    bpy.ops.mesh.primitive_cube_add(size=1, location=position, rotation=(0, 0, rotation))
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if collision:
        COLLISIONS.append({"kind": "box", "size": list(size), "position": list(position), "rotation": rotation})
    # 短倒角形成石材断面，不靠照片纹理表现细节。
    bevel = obj.modifiers.new("石材倒角", "BEVEL")
    bevel.width = min(.03, min(size) * .12)
    bevel.segments = 1
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return finish(obj, kind)


def cylinder(position, radius, depth, kind="stone", top=None, collision=True, sides=12):
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=radius, radius2=radius if top is None else top,
                                  depth=depth, location=position)
    if collision:
        COLLISIONS.append({"kind": "cylinder", "radius": radius, "height": depth, "position": list(position)})
    return finish(bpy.context.object, kind)


def sphere(position, size, kind="stone"):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, location=position)
    obj = bpy.context.object
    obj.scale = tuple(value / 2 for value in size)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, kind)


def ring(position, radius, tube, kind="patina", upright=False, start=0, end=math.tau, steps=24):
    # 环段由封闭四边截面扫掠，残破版本可直接缺失一个角度区间。
    vertices = []
    faces = []
    for index in range(steps + 1):
        angle = start + (end - start) * index / steps
        for radial, height in [(-tube, -tube), (tube, -tube), (tube, tube), (-tube, tube)]:
            x, y, z = (radius + radial) * math.cos(angle), (radius + radial) * math.sin(angle), height
            if upright:
                y, z = z, y
            vertices.append((x + position[0], y + position[1], z + position[2]))
    for index in range(steps):
        for side in range(4):
            faces.append((index * 4 + side, index * 4 + (side + 1) % 4,
                          (index + 1) * 4 + (side + 1) % 4, (index + 1) * 4 + side))
    faces.extend([(3, 2, 1, 0), tuple(range(steps * 4, steps * 4 + 4))])
    mesh = bpy.data.meshes.new("环段")
    mesh.from_pydata(vertices, [], faces)
    obj = bpy.data.objects.new("环段", mesh)
    bpy.context.collection.objects.link(obj)
    finish(obj, kind)


def glyph(position, radius=.32):
    ring_and_path(position, (0, 1, 0), radius * 2)


def ring_and_path(position, normal, diameter, path_length=None, width=None):
    """用共用比例生成凹槽和槽底光纹，石面减去相同轮廓，避免光纹埋在石内。"""
    normal = Vector(normal).normalized()
    center = Vector(position)
    upward = Vector((0, -1, 0)) if normal.z > .9 else Vector((0, 0, 1))
    right = normal.cross(upward).normalized()
    upward = right.cross(normal).normalized()
    radius = diameter * .5
    stroke = width or min(.06, diameter * .065)
    length = diameter * 1.2 if path_length is None else path_length
    vertices, faces = [], []
    steps = 8 if diameter <= .3 else (12 if diameter <= .8 else 24)
    for index in range(steps + 1):
        angle = index * math.tau / steps
        for r in (radius - stroke * .5, radius + stroke * .5):
            vertices.append(center + (right * math.cos(angle) + upward * math.sin(angle)) * r)
        if index:
            a = (index - 1) * 2
            faces.append((a, a + 1, a + 3, a + 2))
    base = len(vertices)
    for x, z in [(-stroke / 2, -radius), (stroke / 2, -radius), (stroke / 2, -radius - length), (-stroke / 2, -radius - length)]:
        vertices.append(center + right * x + upward * z)
    faces.append(tuple(range(base, base + 4)))
    obj = revision.mesh(sys.modules[__name__], "环与径", vertices, faces, "glyph")
    # 凹槽先刻进承载物，光纹放在低于原表面一厘米的槽底。
    cutter_vertices, cutter_faces = [], []
    for index in range(steps):
        angle = index * math.tau / steps
        for r, depth in [(radius - stroke / 2, -.03), (radius + stroke / 2, -.03), (radius + stroke / 2, .03), (radius - stroke / 2, .03)]:
            cutter_vertices.append(center + (right * math.cos(angle) + upward * math.sin(angle)) * r + normal * depth)
        for side in range(4):
            a, b = index * 4 + side, index * 4 + (side + 1) % 4
            cutter_faces.append((a, b, ((index + 1) % steps) * 4 + (side + 1) % 4, ((index + 1) % steps) * 4 + side))
    base = len(cutter_vertices)
    for depth in (-.03, .03):
        for x, z in [(-stroke / 2, -radius), (stroke / 2, -radius), (stroke / 2, -radius - length), (-stroke / 2, -radius - length)]:
            cutter_vertices.append(center + right * x + upward * z + normal * depth)
    for face in [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]:
        cutter_faces.append(tuple(base + index for index in face))
    cutter = revision.mesh(sys.modules[__name__], "刻纹切割体", cutter_vertices, cutter_faces)
    PARTS.remove(cutter)
    bm = bmesh.new()
    bm.from_mesh(cutter.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(cutter.data)
    bm.free()
    bpy.context.view_layer.update()
    for target in PARTS[:-1]:
        if target.data.materials[0].name not in ("stone", "patina"):
            continue
        modifier = target.modifiers.new("环与径凹槽", "BOOLEAN")
        modifier.operation = "DIFFERENCE"
        modifier.object = cutter
        modifier.use_self = True
        bpy.context.view_layer.objects.active = target
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    for vertex in obj.data.vertices:
        vertex.co -= normal * .012


def arch(width, depth, height, broken=False, thickness=None, count=12, coursed=False):
    radius = width / 2
    thickness = width * .13 if thickness is None else thickness
    rise = min(radius, height * .55)
    leg = height - rise
    for side in (-1, 1):
        if coursed:
            rows = max(1, round(leg / .75))
            for row in range(rows):
                box((side * (radius - thickness / 2), 0, (row + .5) * leg / rows), (thickness, depth, leg / rows - .015), collision=False)
            box((side * (radius - thickness / 2 + .025), 0, .15), (thickness + .05, depth + .04, .3), collision=False)
            revision.occlude(box((side * (radius - thickness / 2), 0, leg / 2), (thickness - .02, depth - .02, leg), collision=False))
        else:
            box((side * (radius - thickness / 2), 0, leg / 2), (thickness, depth, leg))
    # 上部拱石独立分块，断口保持不规则。
    for index in range(count):
        if broken and index in (5, 6):
            continue
        angle = math.pi * (index + .5) / count
        obj = box(((radius - thickness / 2) * math.cos(angle), 0,
                   leg + (rise - thickness / 2) * math.sin(angle)),
                  (math.pi * radius / count * .98, depth, thickness), collision=False)
        obj.rotation_euler.y = math.pi / 2 - angle
    COLLISIONS.extend([{"kind": "arch", "width": width, "depth": depth, "height": height, "broken": broken, "thickness": thickness}])


def piece(name, broken=False):
    rng = random.Random(20261020 + sum(name.encode()) + broken)
    if modeling.build(sys.modules[__name__], name):
        return
    if revision.revise(sys.modules[__name__], name):
        return
    if name in ("floor_slab", "plinth", "lintel", "wall", "wall_low", "bridge_pier", "aqueduct_pier", "road_stone", "stele", "standing_stone", "mural_panel"):
        sizes = {"floor_slab": (2, 2, .4), "plinth": (8, 8, 1.2), "lintel": (4, .6, .6),
                 "wall": (2, .6, 3.6), "wall_low": (2, .5, 1), "bridge_pier": (2, 4, 6),
                 "aqueduct_pier": (1.4, 1.4, 4), "road_stone": (2, 1, .2), "stele": (1.2, .4, 3),
                 "standing_stone": (.6, .4, 2.2), "mural_panel": (4, .3, 3)}
        width, depth, height = sizes[name]
        if broken:
            # 逐块高低不同的断面，避免残破仅靠等比缩短。
            for index in range(3):
                h = height * rng.uniform(.3, .78)
                box(((index - 1) * width / 3, 0, h / 2), (width / 3, depth, h))
        else:
            box((0, 0, height / 2), (width, depth, height))
        if name in ("stele", "mural_panel") and not broken:
            ring_and_path((0 if name == "stele" else 1.55, depth / 2, 2.6 if name == "stele" else .68), (0, 1, 0), .7 if name == "stele" else .25)
    elif name in ("plaza_ring", "plinth_round"):
        radius, height = (3, .5) if name == "plaza_ring" else (5, 1.2)
        stone = cylinder((0, 0, height / 2), radius, height, sides=24)
        if broken:
            for vertex in stone.data.vertices:
                if vertex.co.z > 0:
                    vertex.co.z -= height * .3 * max(math.sin(math.atan2(vertex.co.y, vertex.co.x) * 3), 0)
        if name == "plaza_ring":
            ring_and_path((0, 0, height), (0, 0, 1), 3, path_length=1.48, width=.3)
    elif name == "steps":
        for index in range(6 if not broken else 5):
            box((0, -1.8 + (index + .5) * .6, (index + 1) * .125), (4, .6, (index + 1) * .25), collision=False)
        COLLISIONS.append({"kind": "ramp", "size": [4, 3.6, 1.5], "position": [0, 0, 0]})
    elif name == "wall_arc":
        for index in range(8):
            angle = (-15 + (index + .5) * 30 / 8) * math.pi / 180
            height = 3.6 * (rng.uniform(.4, .9) if broken else 1)
            box((5 * math.sin(angle), 5 * math.cos(angle) - 5, height / 2), (.33, .6, height), rotation=-angle)
    elif name == "wall_window":
        for side in (-1, 1):
            core = revision.occlude(box((side * .65, -.025, 1.8), (.67, .53, 3.6), collision=False))
            for vertex in core.data.vertices:
                if vertex.co.y > 0:
                    vertex.co.y += .05 - (vertex.co.z + core.location.z) / 3.6 * .1
            for row in range(5):
                obj = box((side * .65, -.025, (row + .5) * .69 + .075), (.7, .55, .675))
                for vertex in obj.data.vertices:
                    if vertex.co.y > 0:
                        vertex.co.y += .05 - (vertex.co.z + obj.location.z) / 3.6 * .1
            box((side * .65, 0, .15), (.7, .6, .3))
        box((0, 0, 3.525), (2, .58, .15))
        box((0, 0, .45), (.6, .6, .9))
        box((0, 0, 3.05), (.6, .6, 1.1 if not broken else .5))
        for index in range(8):
            x = -.3 + (index + .5) * .075
            bottom = 2.2 + math.sqrt(max(0, .09 - x*x))
            box((x, 0, (bottom + 2.5) / 2), (.075, .6, 2.5-bottom))
    elif name in ("door", "arch", "temple_gate", "cave_mouth"):
        width, depth, height = {"door": (2.4, .8, 4.2), "arch": (4, .8, 5), "temple_gate": (6, 2, 8), "cave_mouth": (10, 4, 8)}[name]
        if name == "door":
            # 净空宽 1.6 米、高 3.2 米，上方保留厚实的门楣。
            arch(width, depth, 3.6, broken, thickness=.4, coursed=True)
            if not broken:
                box((0, 0, 3.9), (2.4, .8, .6))
        else:
            arch(width, depth, height, broken, count=7 if name == "temple_gate" else 12)
        if name != "cave_mouth" and not broken:
            if name == "door":
                ring_and_path((0, depth / 2, 3.97), (0, 1, 0), .4)
            elif name == "temple_gate":
                ring_and_path((0, depth / 2, 7.59), (0, 1, 0), .65)
                for side in (-1, 1):
                    for row in range(5):
                        ring_and_path((side * 2.58, depth / 2, 1.2 + row * 1.05), (0, 1, 0), .3)
    elif name in ("column", "column_fallen"):
        if name == "column":
            cylinder((0, 0, .12), .35, .24)
            cylinder((0, 0, 1.44 if broken else 2.08), .23, 2.4 if broken else 3.68)
            if not broken:
                cylinder((0, 0, 4.08), .35, .24)
        else:
            for index in range(3):
                obj = cylinder(((index - 1) * 1.43, .08 * math.sin(index), .3), .29, 1.28, collision=False)
                obj.rotation_euler.y = math.pi / 2 + index * .06
            COLLISIONS.append({"kind": "box", "size": [4.2, .7, .65], "position": [0, 0, .325], "rotation": 0})
    elif name == "dome":
        # 内外双层壳面；保留室内空间，碰撞不填满整个穹顶。
        for inner in (False, True):
            vertices, faces = [], []
            for row in range(7):
                phi = row / 6 * math.pi / 2
                for column in range(25):
                    theta = column / 24 * math.tau
                    radius = (3 - (.4 if inner else 0)) * math.cos(phi)
                    vertices.append((radius * math.cos(theta), radius * math.sin(theta), (1.2 if inner else 1.6) * math.sin(phi)))
            for row in range(6):
                for column in range(24 if not broken else 16):
                    a = row * 25 + column
                    face = (a, a + 1, a + 26, a + 25)
                    faces.append(tuple(reversed(face)) if inner else face)
            mesh = bpy.data.meshes.new("穹顶壳")
            mesh.from_pydata(vertices, [], faces)
            obj = bpy.data.objects.new("穹顶壳", mesh)
            bpy.context.collection.objects.link(obj)
            finish(obj)
        COLLISIONS.extend([{"kind": "dome", "radius": radius, "height": height, "broken": broken, "inner": inner}
                           for radius, height, inner in [(3, 1.6, False), (2.6, 1.2, True)]])
    elif name == "bridge_span":
        for index in range(12):
            if broken and index in (5, 6):
                continue
            box((-5.5 + index, 0, 5.7), (.98, 4, .6), collision=False)
        for side in (-1, 1):
            arch(12, .45, 5.7, broken)
            for obj in PARTS[-14:]:
                obj.location.y += side * 1.77
        COLLISIONS.clear()
        for x, length in ((-3.25, 5.5), (3.25, 5.5)) if broken else ((0, 12),):
            COLLISIONS.append({"kind": "box", "size": [length, 4, .6], "position": [x, 0, 5.7], "rotation": 0})
    elif name == "aqueduct_channel":
        box((0, 0, .2), (8, 1.4, .4))
        for side in (-1, 1):
            box((0, side * .6, .8), (8 if not broken else 5.6, .2, .8))
    elif name in ("lamp_post", "brazier", "ring_monument"):
        if name == "lamp_post":
            box((0, 0, .1), (.4, .4, .2))
            cylinder((0, 0, .8 if broken else 1.05), .12, 1.6 if broken else 2.1)
            if not broken:
                ring((0, 0, 2.38), .16, .04, upright=True, steps=12)
                ring_and_path((0, .045, 2.45), (0, 1, 0), .14, width=.018)
        elif name == "brazier":
            for index in range(3):
                angle = index * math.tau / 3
                cylinder((.65 * math.cos(angle), .65 * math.sin(angle), .35), .1, .7, "patina")
            cylinder((0, 0, .9), .7, .5, "patina", top=1.2)
            ring((0, 0, 1.3), 1.1, .1, end=5.4 if broken else math.tau)
            for index in range(3):
                angle = index * math.tau / 3
                ring_and_path((math.cos(angle) * 1.08, math.sin(angle) * 1.08, 1.05), (math.cos(angle), math.sin(angle), 0), .3)
        else:
            box((0, 0, .5), (3, 2, 1))
            ring((0, 0, 3.5), 2.25, .25, upright=True, end=5.7 if broken else math.tau)
            ring_and_path((0, 1, .81), (0, 1, 0), .35)
            COLLISIONS.append({"kind": "ring", "radius": 2.25, "tube": .25, "height": 3.5, "end": 5.7 if broken else math.tau})
    elif name == "sand_drift":
        sphere((0, 0, .5), (3, 1.3, 1.0))
    elif name == "tower_drum":
        cylinder((0, 0, 1.2 if broken else 1.5), 3.2, 2.4 if broken else 3, sides=24)
        for z in (.6, 2.4):
            ring((0, 0, z), 3.14, .04, "patina")
    elif name == "tower_crown":
        cylinder((0, 0, .25), 4, .5, sides=24)
        for index in range(18 if broken else 24):
            angle = index * math.tau / 24
            box((3.75 * math.cos(angle), 3.75 * math.sin(angle), 1.25), (.8, .4, 1.5), rotation=angle + math.pi / 2)
    elif name == "tower_stair":
        for index in range(12):
            if broken and index in (5, 6):
                continue
            angle = (index + .5) / 12 * math.pi / 2
            obj = box((3.9 * math.cos(angle), 3.9 * math.sin(angle), (index + 1) / 4 - .125), (.5, 1.4, .25), rotation=angle + math.pi / 2, collision=False)
            box((4.55 * math.cos(angle), 4.55 * math.sin(angle), (index + 1) / 4 + .4), (.5, .2, .8), rotation=angle + math.pi / 2)
        COLLISIONS.append({"kind": "stair_arc", "broken": broken})
    else:
        raise ValueError(name)


def export_collisions(name):
    result = []

    def convex(points):
        mesh = bpy.data.meshes.new("简化凸体")
        bm = bmesh.new()
        verts = [bm.verts.new(point) for point in points]
        bmesh.ops.convex_hull(bm, input=verts)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(f"{name}_{len(result)}-convcolonly", mesh)
        bpy.context.collection.objects.link(obj)
        result.append(obj)

    def block(position, size, rotation=0, tilted=0):
        bpy.ops.mesh.primitive_cube_add(size=1, location=position, rotation=(0, tilted, rotation))
        obj = bpy.context.object
        obj.scale = size
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        obj.name = f"{name}_{len(result)}-convcolonly"
        result.append(obj)

    for record in COLLISIONS:
        kind = record["kind"]
        if kind == "box":
            block(record["position"], record["size"], record["rotation"])
        elif kind == "convex":
            convex(record["points"])
        elif kind == "faces":
            mesh = bpy.data.meshes.new("简化断面壳")
            mesh.from_pydata(record["points"], [], [tuple(range(index, index + 3)) for index in range(0, len(record["points"]), 3)])
            obj = bpy.data.objects.new(f"{name}_{len(result)}-colonly", mesh)
            bpy.context.collection.objects.link(obj)
            result.append(obj)
        elif kind == "cylinder":
            points = [(record["position"][0] + math.cos(index * math.tau / 12) * record["radius"],
                       record["position"][1] + math.sin(index * math.tau / 12) * record["radius"],
                       record["position"][2] + sign * record["height"] / 2)
                      for index in range(12) for sign in (-1, 1)]
            convex(points)
        elif kind == "ramp":
            w, d, h = record["size"]
            convex([(-w/2, -d/2, 0), (w/2, -d/2, 0), (-w/2, d/2, 0), (w/2, d/2, 0), (-w/2, d/2, h), (w/2, d/2, h)])
        elif kind == "arch":
            w, h, d = record["width"], record["height"], record["depth"]
            thickness, rise = record["thickness"], min(w/2, h * .55)
            for side in (-1, 1):
                block((side * (w-thickness)/2, 0, (h-rise)/2), (thickness, d, h-rise))
            for index in range(8):
                if record["broken"] and index in (3, 4):
                    continue
                angle = math.pi * (index + .5) / 8
                block(((w-thickness)/2 * math.cos(angle), 0, h-rise+(rise-thickness/2)*math.sin(angle)),
                      (math.pi*w/16, d, thickness), tilted=math.pi/2-angle)
        elif kind == "dome":
            vertices, faces = [], []
            for index in range(12 if record["broken"] else 16):
                for row in range(2):
                    start = len(vertices)
                    for col, step in ((0, 0), (1, 0), (0, 1), (1, 1)):
                        angle, phi = (index+col)*math.tau/16, (row+step)*math.pi/4
                        vertices.append((math.cos(angle)*math.cos(phi)*record["radius"], math.sin(angle)*math.cos(phi)*record["radius"], math.sin(phi)*record["height"]))
                    quads = [(start, start+2, start+1), (start+1, start+2, start+3)]
                    faces.extend(tuple(reversed(face)) if record["inner"] else face for face in quads)
            mesh = bpy.data.meshes.new("穹顶简化壳")
            mesh.from_pydata(vertices, [], faces)
            obj = bpy.data.objects.new(f"{name}_{len(result)}-colonly", mesh)
            bpy.context.collection.objects.link(obj)
            result.append(obj)
        elif kind == "stair_arc":
            for index in range(6):
                if record["broken"] and index == 2:
                    continue
                convex([(math.cos((index+step)*math.pi/12)*radius, math.sin((index+step)*math.pi/12)*radius, (index+step)*.5+offset)
                        for step in range(2) for radius in (3.2, 4.6) for offset in (-.25, 0)])
        elif kind == "ring":
            for index in range(24):
                angle = (index + .5) * record["end"] / 24
                block((record["radius"] * math.cos(angle), 0, record["height"] + record["radius"] * math.sin(angle)),
                      (record["radius"] * record["end"] / 24, record["tube"] * 2, record["tube"] * 2), tilted=math.pi/2-angle)
    return result


def export_piece(name, output):
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    surfaces = {kind: [] for kind in COLORS}
    surface_colors = {kind: [] for kind in COLORS}
    samples = {}
    vines = name.startswith("vines") or name == "vine_wall"
    for obj in PARTS:
        obj.data.update()
        obj.data.calc_loop_triangles()
        kind = obj.data.materials[0].name
        vertices = surfaces[kind]
        shade = obj.data.attributes.get("shade")
        uv = obj.data.uv_layers.get("UVMap") or obj.data.uv_layers.new(name="UVMap")
        color = obj.data.color_attributes.get("Color") or obj.data.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
        # 新建属性会改变 CustomData 布局，必须重新取得已有属性，避免读写到顶点缓冲。
        uv = obj.data.uv_layers["UVMap"]
        color = obj.data.color_attributes["Color"]
        shade = obj.data.attributes.get("shade")
        loop_colors = {}
        for polygon in obj.data.polygons:
            for loop in polygon.loop_indices:
                index = obj.data.loops[loop].vertex_index
                point = obj.matrix_world @ obj.data.vertices[index].co
                ao = .65 + .25 * min(max(point.z / 3, 0), 1)
                if shade and shade.data[index].value > .01:
                    value = shade.data[index].value
                    ao = ao * 1.08 if value > 1.02 else value
                if ao >= .6:
                    ao *= 1 + .025 * abs(polygon.normal.z)
                rgba = (min(ao, 1.0), 0 if vines else min(max(point.z / 2, 0), 1), float(vines), 1)
                color.data[loop].color = rgba
                loop_colors[loop] = rgba
                axis = max(range(3), key=lambda value: abs(polygon.normal[value]))
                uv.data[loop].uv = (point.y, point.z) if axis == 0 else ((point.x, point.z) if axis == 1 else (point.x, point.y))
                # 独立动作节点的 POSITION 是局部坐标，按最终导出坐标修复颜色。
                local = obj.data.vertices[index].co
                sample = local if name.startswith("echo_") else point
                samples[tuple(round(value, 5) for value in (sample.x, sample.z, -sample.y))] = rgba
        for triangle in obj.data.loop_triangles:
            corners = [obj.matrix_world @ obj.data.vertices[index].co for index in triangle.vertices]
            if (corners[1] - corners[0]).cross(corners[2] - corners[0]).length_squared < 1e-12:
                continue
            for point, loop in zip(corners, triangle.loops):
                vertices.append([round(point.x, 6), round(point.z, 6), round(-point.y, 6)])
                surface_colors[kind].append(list(loop_colors[loop]))
    # Blender 可能并行计算三角形；固定顺序后，同源数据可逐字节重复生成。
    for kind in COLORS:
        entries = []
        for start in range(0, len(surfaces[kind]), 3):
            points = surfaces[kind][start:start + 3]
            rgba = surface_colors[kind][start:start + 3]
            first = min(range(3), key=lambda index: tuple(points[index]))
            order = [(first + index) % 3 for index in range(3)]
            entries.append(([points[index] for index in order], [rgba[index] for index in order]))
        entries.sort(key=lambda item: (item[0], item[1]))
        surfaces[kind] = [point for points, rgba in entries for point in points]
        surface_colors[kind] = [color for points, rgba in entries for color in rgba]
    # 合并为单网格，glb 与程序化路线按同一组材质分面。
    vertices, triangles, kinds, colors = [], [], [], []
    for kind, points in surfaces.items():
        for index in range(0, len(points), 3):
            base = len(vertices)
            vertices.extend((p[0], -p[2], p[1]) for p in points[index:index + 3])
            triangles.append((base, base + 1, base + 2))
            kinds.append(list(COLORS).index(kind))
            colors.extend(surface_colors[kind][index:index + 3])
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], triangles)
    for material in MATERIALS.values():
        mesh.materials.append(material)
    for polygon, kind in zip(mesh.polygons, kinds):
        polygon.material_index = kind
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    # UV 使用米制投影；顶点色 R 为简化环境遮蔽，G 为布料摆动权重。
    uv = mesh.uv_layers.new(name="UVMap")
    color = mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
    uv = mesh.uv_layers["UVMap"]
    color = mesh.color_attributes["Color"]
    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            point = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            axis = max(range(3), key=lambda value: abs(polygon.normal[value]))
            uv.data[loop_index].uv = (point.y, point.z) if axis == 0 else ((point.x, point.z) if axis == 1 else (point.x, point.y))
            color.data[loop_index].color = colors[mesh.loops[loop_index].vertex_index]
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    colliders = export_collisions(name)
    bpy.ops.object.select_all(action="DESELECT")
    for exported in (PARTS + modeling.RIGS if name.startswith("echo_") else [obj]) + colliders:
        exported.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(output / f"{name}.glb"), use_selection=True, export_format="GLB", export_yup=True, export_apply=True, export_vertex_color="ACTIVE", export_active_vertex_color_when_no_material=True)
    repair_vertex_colors(output / f"{name}.glb", samples)
    if modeling.is_revised(name):
        modeling.preview(name, PARTS, output)
    minimum = [min(point[axis] for points in surfaces.values() for point in points) for axis in range(3)]
    maximum = [max(point[axis] for points in surfaces.values() for point in points) for axis in range(3)]
    result = {"surfaces": surfaces, "colors": surface_colors, "collisions": list(COLLISIONS), "bounds_min": minimum, "bounds_size": [b - a for a, b in zip(minimum, maximum)], "triangles": len(triangles)}
    for item in list(bpy.context.scene.objects):
        bpy.data.objects.remove(item, do_unlink=True)
    PARTS.clear()
    COLLISIONS.clear()
    modeling.RIGS.clear()
    return result


def main():
    if bpy.app.version < (4, 0, 0):
        raise RuntimeError("需要 Blender 4.x")
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("game/models/ruins"))
    parser.add_argument("--only", default="", help="只更新逗号分隔的构件，其余模型及同源记录保持不变")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    output = args.out.resolve()
    output.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for name, color in COLORS.items():
        material = bpy.data.materials.new(name)
        material.diffuse_color = color
        MATERIALS[name] = material
    names = ["floor_slab", "plaza_ring", "plinth", "plinth_round", "steps", "wall", "wall_arc", "wall_window", "door", "wall_low", "column", "column_fallen", "lintel", "arch", "dome", "bridge_span", "bridge_pier", "aqueduct_channel", "aqueduct_pier", "road_stone", "stele", "standing_stone", "lamp_post", "brazier", "ring_monument", "statue", "statue_kneel", "cave_mouth", "temple_gate", "mural_panel", "rubble", "rubble_1", "rubble_2", "sand_drift", "vines", "vines_1", "tower_drum", "tower_stair", "tower_crown", "echo_figure", "echo_child", "vine_wall", "statue_arm"]
    selected = set(args.only.split(",")) if args.only else None
    records = json.loads((output / "geometry.json").read_text(encoding="utf-8")) if selected else {}
    for name in names:
        for broken in ((True,) if name == "statue_arm" else ((False, True) if name not in ("rubble", "rubble_1", "rubble_2", "sand_drift", "vines", "vines_1", "echo_figure", "echo_child", "vine_wall", "column_fallen") else (False,))):
            key = name + ("_broken" if broken else "")
            if selected is not None and key not in selected:
                continue
            piece(name)
            if broken and name != "statue_arm":
                seed = 20261020 + sum((index + 1) * byte for index, byte in enumerate(name.encode()))
                if name == "statue":
                    head = next(obj for obj in PARTS if obj.name.startswith(("Head", "HoodShell")))
                    PARTS.remove(head)
                    bpy.data.objects.remove(head, do_unlink=True)
                    retained = [obj for obj in PARTS if obj.name != "Robe"]
                    PARTS[:] = [obj for obj in PARTS if obj.name == "Robe"]
                    revision.fracture(sys.modules[__name__], seed, fraction=.97)
                    PARTS.extend(retained)
                else:
                    revision.fracture(sys.modules[__name__], seed)
                # 为断面周边补足真实几何细分，残破件的细节预算高于完好件。
                reference = records.get(name, records.get("statue", {})).get("triangles", 0)
                target = int(reference * 1.04) + 8
                revision.refine_fractures(sys.modules[__name__], target)
            if name == "statue_arm":
                # 缺臂布尔断口也参与断面细分，不能依赖旧节点名称。
                for part in PARTS:
                    if part.name.startswith("Robe"):
                        attribute = part.data.attributes.get("shade") or part.data.attributes.new("shade", "FLOAT", "POINT")
                        for vertex in part.data.vertices:
                            if vertex.co.x > .3 and vertex.co.z > 2.5:
                                attribute.data[vertex.index].value = 1.08
                revision.refine_fractures(sys.modules[__name__], int(records["statue"]["triangles"] * 1.04) + 8)
            records[key] = export_piece(key, output)
    (output / "geometry.json").write_text(json.dumps(records, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"已生成 {len(records)} 个构件。最大面数 {max(item['triangles'] for item in records.values())}")


if __name__ == "__main__":
    main()
