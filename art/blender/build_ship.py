"""确定性生成探索船；输出 glb 和程序化路线共用的三角形数据。"""

import argparse
import json
import math
from pathlib import Path
import sys

import bpy


def build(output: Path) -> None:
    if bpy.app.version < (4, 0, 0):
        raise RuntimeError("需要 Blender 4.x")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    colors = {"hull": (0.82, 0.78, 0.69, 1), "panel": (0.045, 0.055, 0.065, 1),
              "stripe": (0.58, 0.075, 0.045, 1), "glass": (0.065, 0.48, 0.56, 1),
              "engine": (1, 0.45, 0.12, 1)}
    materials = {}
    for name, color in colors.items():
        material = bpy.data.materials.new(name)
        material.diffuse_color = color
        materials[name] = material
    pieces = []

    def finish(obj, name, material):
        obj.name = name
        obj.data.materials.append(materials[material])
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        bevel = obj.modifiers.new("边缘倒角", "BEVEL")
        bevel.width = 0.035
        bevel.segments = 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=bevel.name)
        pieces.append(obj)
        return obj

    def ellipsoid(name, position, size, material):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, location=position)
        obj = bpy.context.object
        obj.scale = tuple(value / 2 for value in size)
        return finish(obj, name, material)

    def box(name, position, size, material):
        bpy.ops.mesh.primitive_cube_add(size=1, location=position)
        obj = bpy.context.object
        obj.scale = size
        return finish(obj, name, material)

    # Blender 的前方为 +Y，导出后为 Godot 的 -Z；底面为零。
    ellipsoid("Hull", (0, 0, 1.35), (3.15, 8.5, 1.9), "hull")
    ellipsoid("Cockpit", (0, 1.45, 2.0), (2.0, 2.9, 1.2), "glass")
    box("Spine", (0, -0.65, 2.1), (0.18, 3.7, 0.18), "stripe")
    for side in (-1, 1):
        verts = [(side * x, y, z) for x, y, z in
                 [(0.8, 0.8, 1.3), (3.2, -2.45, 1.0), (3.0, -3.0, 1.0),
                  (0.8, -2.1, 1.3), (0.8, 0.8, 1.15), (3.2, -2.45, 0.85),
                  (3.0, -3.0, 0.85), (0.8, -2.1, 1.15)]]
        faces = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2),
                 (2, 6, 7, 3), (3, 7, 4, 0)]
        if side < 0:
            faces = [tuple(reversed(face)) for face in faces]
        mesh = bpy.data.meshes.new("Wing")
        mesh.from_pydata(verts, [], faces)
        obj = bpy.data.objects.new("Wing", mesh)
        bpy.context.collection.objects.link(obj)
        finish(obj, f"Wing{side}", "hull")
        box(f"WingStripe{side}", (side * 1.8, -1.5, 1.22), (0.35, 1.8, 0.035), "stripe")
        ellipsoid(f"Nacelle{side}", (side * 0.98, -2.8, 1.25), (0.8, 2.5, 0.85), "panel")
        ellipsoid(f"Exhaust{side}", (side * 0.98, -3.95, 1.25), (0.54, 0.16, 0.54), "engine")
    for index, (x, y) in enumerate([(-1.3, -1.5), (1.3, -1.5), (0, 2.3)]):
        box(f"Strut{index}", (x, y, 0.4), (0.18, 0.22, 0.7), "panel")
        box(f"Foot{index}", (x, y, 0.065), (0.65, 0.8, 0.13), "panel")
    box("Hatch", (-1.48, 0.1, 1.3), (0.05, 1.25, 0.9), "panel")
    ramp = box("Ramp", (-2.1, 0.1, 0.43), (1.5, 1.0, 0.12), "panel")
    ramp.rotation_euler.y = -0.45
    output.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in pieces:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(output / "ship.glb"), use_selection=True,
                              export_format="GLB", export_yup=True, export_apply=True)
    # 从同一份确定性模型导出数组，程序化路线不需要 Blender 或 glb 导入器。
    records = []
    for obj in pieces:
        mesh = obj.data
        mesh.calc_loop_triangles()
        vertices = []
        for triangle in mesh.loop_triangles:
            for vertex_index in triangle.vertices:
                point = obj.matrix_world @ mesh.vertices[vertex_index].co
                vertices.append([round(point.x, 6), round(point.z, 6), round(-point.y, 6)])
        records.append({"name": obj.name, "material": obj.data.materials[0].name, "vertices": vertices})
    (output / "ship_geometry.json").write_text(json.dumps(records, separators=(",", ":")), encoding="utf-8")
    print(f"探索船已生成：{sum(len(item['vertices']) // 3 for item in records)} 个三角形")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("game/models/ship"))
    build(parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []).out.resolve())
