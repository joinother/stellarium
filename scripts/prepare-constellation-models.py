import argparse
import csv
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def prepare(archive, culture):
    mapping = {"andromeda": "And", "antlia": "Ant", "apus": "Aps",
               "aquarius": "Aqr", "aquila": "Aql", "ara": "Ara", "hydra": "Hya"}
    output = culture / "models"
    output.mkdir(exist_ok=True)
    records = []
    with (archive / "_manifest.csv").open(newline="") as stream:
        entries = list(csv.DictReader(stream))
    for entry in entries:
        if entry["status"] != "done" or entry["constellation"] not in mapping:
            continue
        source = archive / "models_final" / entry["file"]
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(source))
        vertices, indices = [], []
        for obj in bpy.context.scene.objects:
            if obj.type != "MESH":
                continue
            mesh = obj.data
            mesh.calc_loop_triangles()
            offset = len(vertices)
            normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
            for vertex in mesh.vertices:
                position = obj.matrix_world @ vertex.co
                source_normal = vertex.normal.copy()
                if source_normal.length_squared < 0.1:
                    source_normal = sum((face.normal for face in mesh.polygons
                                         if vertex.index in face.vertices), Vector())
                if source_normal.length_squared < 0.1:
                    source_normal = Vector((0, -1, 0))
                normal = (normal_matrix @ source_normal).normalized()
                vertices.append((Vector((position.x, position.z, -position.y)),
                                 Vector((normal.x, normal.z, -normal.y))))
            for triangle in mesh.loop_triangles:
                indices.extend(offset + index for index in triangle.vertices)
        if not vertices or len(vertices) > 100000 or len(indices) > 600000:
            raise ValueError(f"Invalid mesh size: {source}")
        low = Vector(tuple(min(position[axis] for position, _ in vertices) for axis in range(3)))
        high = Vector(tuple(max(position[axis] for position, _ in vertices) for axis in range(3)))
        center = (low + high) * 0.5
        extent = high - low
        illustration = culture / "illustrations" / (entry["constellation"] + ".png")
        image = bpy.data.images.load(str(illustration))
        width, height = image.size
        pixels = list(image.pixels)
        occupied = [(index % width, index // width) for index in range(width * height)
                    if pixels[index * 4 + 3] > 0.05]
        left = min(point[0] for point in occupied) / width
        right = (max(point[0] for point in occupied) + 1) / width
        bottom = min(point[1] for point in occupied) / height
        top = (max(point[1] for point in occupied) + 1) / height
        scale = min((right - left) / extent.x, (top - bottom) / extent.y)
        payload = bytearray(struct.pack("<4sII", b"SCM1", len(vertices), len(indices)))
        for position, normal in vertices:
            position = (position - center) * scale
            values = (position.x + (left + right) / 2,
                      position.y + (bottom + top) / 2, position.z, *normal)
            if not all(math.isfinite(value) for value in values):
                raise ValueError(f"Non-finite geometry: {source}")
            payload.extend(struct.pack("<6f", *values))
        payload.extend(struct.pack(f"<{len(indices)}I", *indices))
        abbreviation = mapping[entry["constellation"]]
        destination = output / (abbreviation + ".scm")
        destination.write_bytes(payload)
        records.append({"id": abbreviation, "source": entry["file"],
                        "sourceSha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                        "mesh": destination.name, "sha256": hashlib.sha256(payload).hexdigest(),
                        "vertices": len(vertices), "triangles": len(indices) // 3,
                        "illustration": str(illustration.relative_to(culture)),
                        "imageBounds": [left, bottom, right, top]})
        print(abbreviation, len(vertices), len(indices) // 3, len(payload))
    (output / "manifest.json").write_text(json.dumps({"schemaVersion": 1,
        "coordinateFrame": "image XY, front positive Z",
        "source": "User Tripo archive/models_final; archive/_manifest.csv",
        "models": records}, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("culture", type=Path)
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    prepare(arguments.archive, arguments.culture)
