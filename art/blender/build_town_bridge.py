"""从完好桥段导入网格，用布尔切割制作可跳越的专用断口。"""
import json
import sys
from pathlib import Path

import bpy
import bmesh

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_ruin_kit as kit
import ruin_modeling as modeling


def main():
    if bpy.app.version < (4, 0, 0):
        raise RuntimeError("需要 Blender 4.x。")
    output = Path("game/models/ruins").resolve()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(output / "bridge_span.glb"))
    parts = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and "colonly" not in obj.name]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = world
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    obj = bpy.context.object
    modeling.active(obj)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.00001)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    # 导入的桥段含相交砌块，先体素重拓扑，避免布尔运算把相交外壳误判为内腔。
    remesh = obj.modifiers.new("合并桥段砌块", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = .055
    remesh.use_smooth_shade = False
    bpy.ops.object.modifier_apply(modifier=remesh.name)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 4))
    cutter = bpy.context.object
    cutter.scale = (1.6, 8, 10)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    modeling.active(obj)
    modifier = obj.modifiers.new("一米六通行断口", "BOOLEAN")
    modifier.operation = "DIFFERENCE"
    modifier.solver = "EXACT"
    modifier.object = cutter
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    modeling.normals(obj)
    modeling.simplify(obj, 1800)
    for name, color in kit.COLORS.items():
        material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        material.diffuse_color = color
        material.use_nodes = False
        kit.MATERIALS[name] = material
    obj.data.materials.clear()
    obj.data.materials.append(kit.MATERIALS["stone"])
    modeling.preview("bridge_span_gap", [obj], output)
    kit.PARTS[:] = [obj]
    kit.COLLISIONS[:] = [{"kind": "box", "size": [5.2, 4, .6], "position": [sign * 3.4, 0, 5.7], "rotation": 0} for sign in (-1, 1)]
    record = kit.export_piece("bridge_span_gap", output)
    geometry = json.loads((output / "geometry.json").read_text(encoding="utf-8"))
    geometry["bridge_span_gap"] = record
    (output / "geometry.json").write_text(json.dumps(geometry, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print("已生成一米六断口桥跨", record["triangles"])


if __name__ == "__main__":
    main()
