"""峡谷岩石通过曲线、体素重建和位移建模；形状不依赖手写顶点。"""

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_ruin_kit as kit
import ruin_modeling as modeling


def rock(name, variant, arch):
    if arch:
        bpy.ops.mesh.primitive_torus_add(major_segments=40, minor_segments=8,
                                        major_radius=25 + variant * 4, minor_radius=5.8 + variant * .6)
        obj = bpy.context.object
        obj.rotation_euler.x = math.pi / 2
        modeling.active(obj)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        modeling.cut(obj, (0, 0, 0), (0, 0, -1), fill=True)
    else:
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1)
        obj = bpy.context.object
        obj.scale = (4.0 + variant * .6, 5.0 + variant * .3, 20.0 + variant * 2.0)
        obj.location.z = obj.scale.z
        modeling.active(obj)
        bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    obj.name = name
    remesh = obj.modifiers.new("天然岩石体素重建", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = 1.2
    modeling.apply(obj, remesh)
    texture = bpy.data.textures.new("峡谷岩石轮廓" + name, type="CLOUDS")
    texture.noise_scale = 5.0
    texture.noise_depth = 2
    displace = obj.modifiers.new("风化位移", "DISPLACE")
    displace.texture = texture
    displace.texture_coords = "GLOBAL"
    displace.strength = 2.3
    modeling.apply(obj, displace)
    modeling.simplify(obj, 2600 if arch else 1400)
    if not arch:
        height = max(v.co.z for v in obj.data.vertices)
        modeling.cut(obj, (0, 0, height * .18), (0, 0, -1), fill=True)
    low = min(v.co.z for v in obj.data.vertices)
    obj.data.transform(Matrix.Translation((0, 0, -low)))
    kit.finish(obj)
    # 顶部草皮取自已有岩石面，向外偏移，保留完整石材封闭面。
    grass = obj.copy()
    grass.data = obj.data.copy()
    bpy.context.collection.objects.link(grass)
    modeling.active(grass)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(grass.data)
    bm.normal_update()
    upper = max(v.co.z for v in bm.verts) * .72
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.normal.z < .65 or f.calc_center_median().z < upper], context="FACES")
    for vertex in bm.verts:
        vertex.co.z += .08
    bm.to_mesh(grass.data)
    bm.free()
    grass.data.materials.clear()
    modeling.normals(grass)
    kit.finish(grass, "cloth")
    if arch:
        low = [min(v.co[i] for v in obj.data.vertices) for i in range(3)]
        high = [max(v.co[i] for v in obj.data.vertices) for i in range(3)]
        kit.COLLISIONS.append({"kind": "arch", "width": high[0] - low[0], "depth": high[1] - low[1], "height": high[2], "thickness": 9 + variant, "broken": False})
    else:
        # 简化柱身碰撞与模型同高，不把顶部之外的空间挡住。
        height = max(v.co.z for v in obj.data.vertices)
        kit.COLLISIONS.append({"kind": "box", "size": [7 + variant, 7 + variant * .5, height], "position": [0, 0, height / 2], "rotation": 0})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("game/models/landforms"))
    parser.add_argument("--only", default="")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    args.out.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for name, color in kit.COLORS.items():
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = (.17, .30, .07, 1) if name == "cloth" else color
        kit.MATERIALS[name] = mat
    selected = set(args.only.split(",")) if args.only else None
    records = json.loads((args.out / "geometry.json").read_text(encoding="utf-8")) if selected else {}
    for arch, count in ((True, 3), (False, 7)):
        for variant in range(count):
            name = ("canyon_arch_" if arch else "canyon_pillar_") + str(variant)
            if selected is not None and name not in selected:
                continue
            rock(name, variant, arch)
            modeling.preview(name, kit.PARTS, args.out)
            records[name] = kit.export_piece(name, args.out)
    (args.out / "geometry.json").write_text(json.dumps(records, separators=(",", ":")), encoding="utf-8")
    print("峡谷岩石已生成：", len(records))


if __name__ == "__main__":
    main()
