"""探索者由蒙皮、细分、实体化布面及骨骼动画生成，攀爬物件使用曲线建模。"""

import argparse
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ruin_modeling as modeling

COLORS = {"cloth": (.72, .79, .67, 1), "dark": (.15, .25, .28, 1),
          "light": (.91, .86, .69, 1), "accent": (.74, .36, .19, 1),
          "glass": (.16, .40, .48, 1), "scarf": (.80, .30, .22, 1),
          "patina": (.369, .549, .518, 1)}
MATERIALS = {}
PARTS = []
BONES = {"Root": ((0, 0, .81), (0, 0, .95), None),
         "Spine": ((0, 0, .95), (0, 0, 1.16), "Root"),
         "Chest": ((0, 0, 1.16), (0, 0, 1.32), "Spine"),
         "Neck": ((0, 0, 1.32), (0, 0, 1.43), "Chest"),
         "Head": ((0, 0, 1.43), (0, 0, 1.73), "Neck")}
for side, sign in ((".L", -1), (".R", 1)):
    for name, head, tail, parent in (
        ("UpperArm", (sign * .25, 0, 1.27), (sign * .37, 0, 1.04), "Chest"),
        ("Forearm", (sign * .37, 0, 1.04), (sign * .40, .02, .84), "UpperArm" + side),
        ("Hand", (sign * .40, .02, .84), (sign * .40, .04, .76), "Forearm" + side),
        ("Thigh", (sign * .13, 0, .83), (sign * .14, 0, .46), "Root"),
        ("Shin", (sign * .14, 0, .46), (sign * .14, 0, .13), "Thigh" + side),
        ("Foot", (sign * .14, 0, .13), (sign * .14, .17, .07), "Shin" + side)):
        BONES[name + side] = (head, tail, parent)
for i in range(7):
    BONES[f"Scarf{i}"] = ((0, -.25 - i * .11, 1.35 - i * .025),
                            (0, -.36 - i * .11, 1.325 - i * .025), "Chest" if i == 0 else f"Scarf{i - 1}")
BONES["WingRoot"] = ((0, 0, 1.30), (0, -.25, 1.30), "Chest")
for side, sign in ((".L", -1), (".R", 1)):
    BONES["Wing" + side] = ((0, -.25, 1.30), (sign * 1.3, -.7, 1.3), "WingRoot")


def finish(obj, kind, smooth=True):
    modeling.normals(obj)
    obj.data.materials.append(MATERIALS[kind])
    for polygon in obj.data.polygons:
        polygon.use_smooth = smooth
    PARTS.append(obj)
    return obj


def sphere(name, location, scale, kind, segments=20):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=12, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    modeling.active(obj)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    return finish(obj, kind)


def rounded_box(name, location, scale, kind):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    modeling.active(obj)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    bevel = obj.modifiers.new("圆顺边缘", "BEVEL")
    bevel.width = min(scale) * .22
    bevel.segments = 3
    modeling.apply(obj, bevel)
    return finish(obj, kind)


def curve(name, points, radius, kind, cyclic=False):
    data = bpy.data.curves.new(name, "CURVE")
    data.dimensions = "3D"
    data.resolution_u = 3
    data.bevel_depth = radius
    data.bevel_resolution = 2
    spline = data.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, location in zip(spline.bezier_points, points):
        point.co = location
        point.handle_left_type = point.handle_right_type = "AUTO"
    spline.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    modeling.active(obj)
    bpy.ops.object.convert(target="MESH")
    return finish(bpy.context.object, kind)


def bind(obj, rig, bone=None, scarf=False, wing=False):
    groups = {name: obj.vertex_groups.new(name=name) for name in BONES}
    for vertex in obj.data.vertices:
        if bone:
            groups[bone].add([vertex.index], 1, "REPLACE")
            continue
        if scarf:
            selected = f"Scarf{min(6, max(0, int((-vertex.co.y - .25) / .11)))}"
            groups[selected].add([vertex.index], 1, "REPLACE")
            continue
        if wing:
            selected = "Wing.L" if vertex.co.x < 0 else "Wing.R"
            weight = min(1, abs(vertex.co.x) / .35)
            groups[selected].add([vertex.index], weight, "REPLACE")
            groups["WingRoot"].add([vertex.index], 1 - weight, "REPLACE")
            continue
        distances = []
        for name, (head, tail, _) in BONES.items():
            if name.startswith(("Scarf", "Wing")):
                continue
            a, b = Vector(head), Vector(tail)
            t = min(1, max(0, (vertex.co - a).dot(b - a) / (b - a).length_squared))
            distances.append(((vertex.co - a.lerp(b, t)).length, name))
        chosen = sorted(distances)[:2]
        weights = [1 / max(.02, distance) ** 4 for distance, _ in chosen]
        for (_, name), weight in zip(chosen, weights):
            groups[name].add([vertex.index], weight / sum(weights), "REPLACE")
    mod = obj.modifiers.new("骨骼变形", "ARMATURE")
    mod.object = rig
    obj.parent = rig


def body(rig):
    points = [(0, 0, .81), (0, 0, 1.04), (0, 0, 1.24), (0, 0, 1.40)]
    radii = [(.19, .13), (.19, .14), (.24, .14), (.105, .10)]
    edges = [(0, 1), (1, 2), (2, 3)]
    for sign in [-1, 1]:
        for parent, line, thickness in (
            (2, [(sign * .26, 0, 1.27), (sign * .37, 0, 1.04), (sign * .40, .02, .84), (sign * .40, .04, .77)], [.09, .075, .07, .065]),
            (0, [(sign * .13, 0, .81), (sign * .14, 0, .46), (sign * .14, 0, .13), (sign * .14, .15, .08)], [.105, .09, .085, .09])):
            start = len(points)
            points.extend(line)
            radii.extend([(r, r) for r in thickness])
            edges.extend([(parent, start)] + [(start + i, start + i + 1) for i in range(3)])
    data = bpy.data.meshes.new("探索者蒙皮中心线")
    data.from_pydata(points, edges, [])
    obj = bpy.data.objects.new("Suit", data)
    bpy.context.collection.objects.link(obj)
    skin = obj.modifiers.new("身体与衣袖连续蒙皮", "SKIN")
    for vertex, radius in zip(data.skin_vertices[0].data, radii):
        vertex.radius = radius
    data.skin_vertices[0].data[1].use_root = True
    modeling.apply(obj, skin)
    sub = obj.modifiers.new("衣服圆顺轮廓", "SUBSURF")
    sub.levels = 2
    modeling.apply(obj, sub)
    texture = bpy.data.textures.new("衣料松量", type="CLOUDS")
    texture.noise_scale = .08
    displacement = obj.modifiers.new("衣料褶皱", "DISPLACE")
    displacement.texture = texture
    displacement.strength = .008
    modeling.apply(obj, displacement)
    modeling.simplify(obj, 2500)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    # 靴口在同一高度切分面，避免按三角面中心染色形成锯齿边缘。
    bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                          plane_co=(0, 0, .26), plane_no=(0, 0, 1), clear_inner=False, clear_outer=False)
    bm.to_mesh(obj.data)
    bm.free()
    finish(obj, "cloth")
    obj.data.materials.append(MATERIALS["dark"])
    for face in obj.data.polygons:
        center = face.center
        face.material_index = 1 if center.z < .26 or (abs(center.x) > .35 and center.z < .91) else 0
    bind(obj, rig)
    jacket = bpy.data.objects.new("JacketCloth", obj.data.copy())
    bpy.context.collection.objects.link(jacket)
    jacket.data.materials.clear()
    modeling.cut(jacket, (0, 0, 1.35), (0, 0, 1))
    modeling.cut(jacket, (0, 0, .82), (0, 0, -1))
    offset = jacket.modifiers.new("外衣与内层分离", "DISPLACE")
    offset.strength = .015
    offset.mid_level = 0
    modeling.apply(jacket, offset)
    thickness = jacket.modifiers.new("外衣厚度与袖口", "SOLIDIFY")
    thickness.thickness = .008
    thickness.offset = -1
    modeling.apply(jacket, thickness)
    modeling.simplify(jacket, 850)
    finish(jacket, "cloth")
    bind(jacket, rig)
    for obj, bone in [
        (sphere("HelmetShell", (0, 0, 1.54), (.225, .21, .21), "light"), "Head"),
        (sphere("VisorRim", (0, .179, 1.56), (.178, .055, .137), "dark"), "Head"),
        (sphere("Faceplate", (0, .215, 1.57), (.155, .038, .112), "glass"), "Head"),
        (rounded_box("Backpack", (0, -.22, 1.12), (.34, .22, .42), "dark"), "Chest"),
        (rounded_box("BackpackFlap", (0, -.345, 1.16), (.26, .05, .22), "cloth"), "Chest")]:
        bind(obj, rig, bone)
    for sign in [-1, 1]:
        strap = curve("ShoulderStrap", [(sign * .15, -.24, .99), (sign * .18, -.16, 1.35), (sign * .18, .14, 1.28), (sign * .13, .14, .96)], .018, "accent")
        bind(strap, rig, "Chest")
    collar = curve("ScarfCollar", [(math.cos(t * math.tau / 16) * .14, math.sin(t * math.tau / 16) * .13, 1.36) for t in range(16)], .045, "scarf", True)
    bind(collar, rig, "Neck")
    lamp = rounded_box("Lantern", (.23, .08, .87), (.10, .10, .17), "accent")
    bind(lamp, rig, "Root")
    lens = sphere("LanternGlass", (.23, .136, .88), (.035, .018, .05), "glass", 12)
    bind(lens, rig, "Root")
    handle = curve("LanternHandle", [(.19, .08, .96), (.19, .08, 1.015), (.27, .08, 1.015), (.27, .08, .96)], .009, "dark")
    bind(handle, rig, "Root")


def cloth(rig, wing=False):
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=21 if wing else 3, y_subdivisions=13, size=2)
    obj = bpy.context.object
    obj.name = "SoftWing" if wing else "ScarfCloth"
    for vertex in obj.data.vertices:
        x, y = vertex.co.x, vertex.co.y
        vertex.co = (x * (1.3 if wing else .075), -.58 + y * (.68 if wing else .38),
                     1.32 + (.13 * (1 - x * x) + .03 * math.cos(y * 4) if wing else y * .10))
    if wing:
        modeling.cut(obj, (0, .18, 1.32), (1, .96, 0))
        modeling.cut(obj, (0, .18, 1.32), (-1, .96, 0))
    solid = obj.modifiers.new("布面厚度", "SOLIDIFY")
    solid.thickness = .003
    modeling.apply(obj, solid)
    finish(obj, "scarf")
    bind(obj, rig, scarf=not wing, wing=wing)


def animations(rig):
    names = ["idle", "walk", "run", "jump", "fall", "land_stumble", "glide", "climb", "climb_rope", "mantle"]
    for name in names:
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        rig.animation_data_create()
        rig.animation_data.action = action
        frames = [1, 7, 13, 19, 25]
        for frame in frames:
            phase = (frame - 1) / 24 * math.tau
            for bone in rig.pose.bones:
                bone.rotation_mode = "XYZ"
                bone.rotation_euler = (0, 0, 0)
                bone.location = (0, 0, 0)
                bone.scale = (1, 1, 1)
            rig.pose.bones["WingRoot"].scale = (1, 1, 1) if name == "glide" else (.035, .3, .7)
            for side, sign in ((".L", -1), (".R", 1)):
                swing = math.sin(phase) * sign
                upper, lower = rig.pose.bones["UpperArm" + side], rig.pose.bones["Forearm" + side]
                thigh, shin = rig.pose.bones["Thigh" + side], rig.pose.bones["Shin" + side]
                if name in ("walk", "run"):
                    amplitude = .45 if name == "walk" else .78
                    upper.rotation_euler.x = -swing * amplitude
                    thigh.rotation_euler.x = swing * amplitude
                    shin.rotation_euler.x = max(0, -swing) * amplitude
                elif name in ("climb", "climb_rope"):
                    upper.rotation_euler.x = -1.9 + swing * .45
                    lower.rotation_euler.x = -.6
                    thigh.rotation_euler.x = -.5 + swing * .4
                    shin.rotation_euler.x = .6 - swing * .3
                elif name == "glide":
                    upper.rotation_euler.z = -sign * 1.15
                    upper.rotation_euler.x = -.7
                    thigh.rotation_euler.x = .35
                    shin.rotation_euler.x = .55
                elif name in ("jump", "fall"):
                    upper.rotation_euler.z = sign * .25
                    thigh.rotation_euler.x = -.4
                    shin.rotation_euler.x = .5
                elif name == "mantle":
                    upper.rotation_euler.x = -1.7 * (1 - (frame - 1) / 24)
                    thigh.rotation_euler.x = -.9 * (1 if sign < 0 else .25)
                    shin.rotation_euler.x = .8
                elif name == "land_stumble":
                    thigh.rotation_euler.x = -.35 * abs(math.sin(phase / 2))
                    shin.rotation_euler.x = .8 * abs(math.sin(phase / 2))
            rig.pose.bones["Spine"].rotation_euler.x = -.52 if name == "glide" else (-.2 if name == "land_stumble" else .018 * math.sin(phase))
            for bone in rig.pose.bones:
                bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
                bone.keyframe_insert("location", frame=frame, group=bone.name)
                bone.keyframe_insert("scale", frame=frame, group=bone.name)
    rig.animation_data.action = bpy.data.actions["idle"]
    bpy.context.scene.frame_set(1)
    return names


def export(name, output, rig=None):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in PARTS + ([rig] if rig else []):
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(output / f"{name}.glb"), use_selection=True,
                              export_format="GLB", export_yup=True, export_animations=bool(rig),
                              export_animation_mode="ACTIONS", export_force_sampling=True)
    triangles = 0
    for obj in PARTS:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
    return triangles


def props(output):
    PARTS.clear()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for strand in range(3):
        points = []
        for i in range(97):
            angle = i / 96 * math.tau * 12 + strand * math.tau / 3
            points.append((.022 * math.cos(angle), .022 * math.sin(angle), i / 96 * 1.2))
        curve("TwistedRope", points, .018, "light")
    curve("RopeKnot", [(.045 * math.cos(i * math.tau / 16), .045 * math.sin(i * math.tau / 16), .04 + .012 * math.sin(i * math.tau / 8)) for i in range(16)], .018, "light", True)
    for obj in PARTS:
        modeling.simplify(obj, 220 if obj.name.startswith("TwistedRope") else 100)
    modeling.preview("climb_rope", PARTS, output)
    rope_count = export("climb_rope", output)
    PARTS.clear()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    curve("AnchorRing", [(.07 * math.cos(i * math.tau / 20), 0, .07 * math.sin(i * math.tau / 20)) for i in range(20)], .014, "patina", True)
    modeling.preview("climb_anchor", PARTS, output)
    anchor_count = export("climb_anchor", output)
    PARTS.clear()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    rounded_box("FootHold", (0, 0, 0), (.22, .13, .09), "dark")
    curve("CopperPeg", [(0, -.06, .02), (0, -.14, .05), (0, -.16, .14)], .018, "accent")
    curve("RingAndPath", [(.055 * math.cos(i * math.tau / 20), -.165, .16 + .055 * math.sin(i * math.tau / 20)) for i in range(20)], .006, "light", True)
    curve("RingPath", [(0, -.165, .02), (0, -.165, .105)], .006, "light")
    for obj in PARTS:
        modeling.simplify(obj, 180)
    modeling.preview("climb_peg", PARTS, output)
    return {"climb_rope": rope_count, "climb_anchor": anchor_count, "climb_peg": export("climb_peg", output)}


def main():
    if bpy.app.version < (4, 0, 0):
        raise RuntimeError("需要 Blender 4.x 或更新版本。")
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("game/models/explorer"))
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    args.out.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for name, color in COLORS.items():
        material = bpy.data.materials.new("explorer_" + name)
        material.diffuse_color = color
        material.roughness = .88
        MATERIALS[name] = material
    data = bpy.data.armatures.new("ExplorerSkeleton")
    rig = bpy.data.objects.new("ExplorerRig", data)
    bpy.context.collection.objects.link(rig)
    modeling.active(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (head, tail, parent) in BONES.items():
        bone = data.edit_bones.new(name)
        bone.head, bone.tail = head, tail
        if parent:
            bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    body(rig)
    cloth(rig)
    cloth(rig, True)
    names = animations(rig)
    # 预算检查在导出前完成，避免导出一个超预算版本。
    for obj in PARTS:
        modeling.simplify(obj, 1800 if obj.name.startswith(("Helmet", "Face", "Visor")) else 2500)
    modeling.preview("explorer", [obj for obj in PARTS if obj.name != "SoftWing"], args.out)
    rig.animation_data.action = bpy.data.actions["glide"]
    bpy.context.scene.frame_set(13)
    for obj in PARTS:
        obj.hide_render = False
    modeling.preview("explorer_glide", PARTS, args.out)
    rig.animation_data.action = bpy.data.actions["idle"]
    bpy.context.scene.frame_set(1)
    triangles = export("explorer", args.out, rig)
    if triangles > 8000:
        raise RuntimeError(f"探索者面数超预算：{triangles}")
    counts = props(args.out)
    (args.out / "model.json").write_text(json.dumps({"triangles": triangles, "bones": list(BONES), "animations": names, "props": counts}, ensure_ascii=False), encoding="utf-8")
    print("探索者与攀爬模型已生成", triangles)


if __name__ == "__main__":
    main()
