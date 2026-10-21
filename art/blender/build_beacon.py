"""从已确认的烽火塔构件组合并减面，导出两公里外使用的轮廓。"""
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ruin_modeling as modeling


def imported(name, height, angle=0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / "game/models/ruins" / f"{name}.glb"))
    parts = []
    placement = Matrix.Translation((0, 0, height)) @ Matrix.Rotation(angle, 4, "Z")
    if name == "tower_crown_broken":
        placement = placement @ Matrix.Diagonal((.85, .85, 1, 1))
    for obj in set(bpy.data.objects) - before:
        if obj.type == "MESH" and (obj.name == name or obj.name.startswith(name + ".")):
            obj.matrix_world = placement @ obj.matrix_world
            parts.append(obj)
        else:
            bpy.data.objects.remove(obj, do_unlink=True)
    return parts


def merge(parts, budget):
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if budget == 128:
        # 先合并相接的塔身与环箍，防止极低面数减面把各段独立挤成细片。
        remesh = obj.modifiers.new("塔身体素合并", "REMESH")
        remesh.mode = "VOXEL"
        remesh.voxel_size = .20
        modeling.apply(obj, remesh)
    modeling.simplify(obj, budget)
    modeling.normals(obj)
    return obj


ROOT = Path(__file__).resolve().parents[2]
if bpy.app.version < (4, 0, 0):
    raise RuntimeError("需要 Blender 4.x。")
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
groups = [([], 128), (imported("tower_crown_broken", 17.5, -3 * math.pi / 4), 36), (imported("brazier", 18), 32)]
for index in range(6):
    groups[0][0].extend(imported("tower_drum", index * 3))
models = [merge(parts, budget) for parts, budget in groups]
obj = merge(models, 196)
obj.name = "tower_far"
stone = bpy.data.materials.new("stone")
stone.diffuse_color = (.67, .57, .38, 1)
obj.data.materials.clear()
obj.data.materials.append(stone)
for polygon in obj.data.polygons:
    polygon.material_index = 0
obj.data.calc_loop_triangles()
count = len(obj.data.loop_triangles)
if count > 200:
    raise RuntimeError(f"塔远景超过两百个三角形：{count}")
output = ROOT / "game/models/beacons"
output.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="DESELECT")
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.export_scene.gltf(filepath=str(output / "tower_far.glb"), export_format="GLB", use_selection=True, export_yup=True, export_apply=True)
(output / "tower_far.json").write_text(json.dumps({"triangles": count, "height_m": obj.dimensions.z}), encoding="utf-8")
modeling.preview("tower_far", [obj], ROOT / "test-output/models")
