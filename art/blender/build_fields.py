"""用贝塞尔曲线与细分籽粒生成成簇稻秆，保留四视图和模型面数。"""
import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ruin_modeling as modeling


def main():
    if bpy.app.version < (4, 0, 0):
        raise RuntimeError("需要 Blender 4.x 或更新版本。")
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("game/models/vegetation"))
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    args.out.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    material = bpy.data.materials.new("field_stalks")
    material.diffuse_color = (.45, .34, .14, 1)
    material.roughness = 1
    material.use_nodes = True
    color_node = material.node_tree.nodes.new("ShaderNodeVertexColor")
    color_node.layer_name = "Color"
    material.node_tree.links.new(color_node.outputs["Color"], material.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
    parts = []
    for index in range(4):
        angle = index * math.tau / 4 + .3
        side = Vector((math.cos(angle), math.sin(angle), 0))
        root = side * .035
        height = .51 + index * .02
        paths = [[root, root + side * .01 + Vector((0, 0, height * .5)),
                  root + side * .035 + Vector((0, 0, height))]]
        for sign in (-1, 1):
            paths.append([root + Vector((0, 0, height * .45)),
                          root + side * sign * .07 + Vector((0, 0, height * .64)),
                          root + side * sign * .14 + Vector((0, 0, height * .52))])
        for path_index, path in enumerate(paths):
            curve = bpy.data.curves.new("干秆与卷叶", "CURVE")
            curve.dimensions = "3D"
            curve.resolution_u = 3
            curve.bevel_depth = .003 if path_index == 0 else .002
            curve.bevel_resolution = 0
            spline = curve.splines.new("BEZIER")
            spline.bezier_points.add(len(path) - 1)
            for point, position in zip(spline.bezier_points, path):
                point.co = position
                point.handle_left_type = point.handle_right_type = "AUTO"
            obj = bpy.data.objects.new("稻秆", curve)
            bpy.context.collection.objects.link(obj)
            modeling.active(obj)
            bpy.ops.object.convert(target="MESH")
            obj = bpy.context.object
            obj.data.materials.append(material)
            parts.append(obj)
        for seed in range(3):
            position = root + side * (.035 + seed * .012) + Vector((0, 0, height - seed * .022))
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1, location=position)
            obj = bpy.context.object
            obj.name = "干燥穗粒"
            obj.scale = (.010, .007, .022)
            modeling.active(obj)
            bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
            obj.data.materials.append(material)
            parts.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = "FieldStalks"
    modeling.normals(obj)
    modeling.simplify(obj, 320)
    while obj.data.uv_layers:
        obj.data.uv_layers.remove(obj.data.uv_layers[0])
    uv = obj.data.uv_layers.new(name="UVMap")
    wind = obj.data.uv_layers.new(name="Wind")
    obj.data.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
    colors = obj.data.color_attributes["Color"]
    uv = obj.data.uv_layers["UVMap"]
    wind = obj.data.uv_layers["Wind"]
    for loop in obj.data.loops:
        point = obj.matrix_world @ obj.data.vertices[loop.vertex_index].co
        colors.data[loop.index].color = (.45, .34, .14, 1)
        uv.data[loop.index].uv = (point.x, point.z)
        # glTF 导出会翻转 V，Godot 的第二通道仍需保持分类值零。
        wind.data[loop.index].uv = (min(point.z / .6, 1), 1)
    modeling.preview("field_stalks", [obj], args.out)
    modeling.active(obj)
    bpy.ops.export_scene.gltf(filepath=str((args.out / "field_stalks.glb").resolve()),
                              export_format="GLB", use_selection=True, export_yup=True,
                              export_texcoords=True, export_normals=True)
    obj.data.calc_loop_triangles()
    (args.out / "field_stalks.json").write_text(json.dumps({"triangles": len(obj.data.loop_triangles),
        "height_m": max((obj.matrix_world @ vertex.co).z for vertex in obj.data.vertices)}), encoding="utf-8")


if __name__ == "__main__":
    main()
