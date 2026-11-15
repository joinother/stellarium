import argparse
import csv
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

def foreground_bounds(pixels, width, height):
    if width <= 0 or height <= 0 or len(pixels) != width * height * 4:
        raise ValueError("Invalid RGBA image dimensions")
    use_alpha = any(pixels[offset] < 1.0 for offset in range(3, len(pixels), 4))
    left, bottom, right, top = width, height, 0, 0
    for index in range(width * height):
        offset = index * 4
        visible = pixels[offset + 3] > 0 if use_alpha else max(pixels[offset:offset + 3]) > 0
        if visible:
            horizontal, vertical = index % width, index // width
            left, bottom = min(left, horizontal), min(bottom, vertical)
            right, top = max(right, horizontal + 1), max(top, vertical + 1)
    if right <= left or top <= bottom:
        raise ValueError("Illustration has no foreground")
    bounds = [left, bottom, right, top]
    padded = [max(0, left - 1), max(0, bottom - 1), min(width, right + 1), min(height, top + 1)]
    return bounds, padded, "alpha-positive" if use_alpha else "rgb-positive-black-background"


def fit_foreground(positions, image_size, bounds):
    width, height = image_size
    left, bottom, right, top = bounds
    if not positions or not (0 <= left < right <= width and 0 <= bottom < top <= height):
        raise ValueError("Invalid foreground fit")
    low = [min(position[axis] for position in positions) for axis in range(3)]
    high = [max(position[axis] for position in positions) for axis in range(3)]
    extent = [high[axis] - low[axis] for axis in range(3)]
    if extent[0] <= 0 or extent[1] <= 0:
        raise ValueError("Degenerate artwork plane")
    center = [(low[axis] + high[axis]) * 0.5 for axis in range(3)]
    scale = min((right - left) / extent[0], (top - bottom) / extent[1])
    return [((position[0] - center[0]) * scale / width + (left + right) / (2 * width),
             (position[1] - center[1]) * scale / height + (bottom + top) / (2 * height),
             (position[2] - center[2]) * scale / width) for position in positions]


def prepare(archive, culture, bootstrap, triangle_budget):
    import bpy
    from mathutils import Vector

    culture_data = json.loads((culture / "index.json").read_text())
    mapping = {}
    for constellation in culture_data["constellations"]:
        if "image" in constellation:
            illustration = constellation["image"]["file"]
            name = Path(illustration).stem
            if name == "horlogium":
                name = "horologium"
            if name in mapping:
                raise ValueError(f"Ambiguous artwork: {name}")
            mapping[name] = (constellation["id"].split()[-1], illustration)
    output = culture / "models"
    output.mkdir(exist_ok=True)
    records = []
    excluded = []
    with (archive / "_manifest.csv").open(newline="") as stream:
        entries = list(csv.DictReader(stream))
    for entry in entries:
        if entry["status"] != "done":
            excluded.append({"source": entry["file"], "status": entry["status"]})
            continue
        if entry["constellation"] not in mapping:
            raise ValueError(f"No artwork mapping: {entry['constellation']}")
        abbreviation, illustration_path = mapping[entry["constellation"]]
        if any(record["id"] == abbreviation for record in records):
            raise ValueError(f"Duplicate model: {abbreviation}")
        source = archive / "models_final" / entry["file"]
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(source))
        meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
        for obj in meshes:
            obj.data.calc_loop_triangles()
        source_triangles = sum(len(obj.data.loop_triangles) for obj in meshes)
        if source_triangles > triangle_budget:
            for obj in meshes:
                bpy.context.view_layer.objects.active = obj
                modifier = obj.modifiers.new('runtime_budget', 'DECIMATE')
                modifier.ratio = triangle_budget / source_triangles
                bpy.ops.object.modifier_apply(modifier=modifier.name)
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
        illustration = culture / illustration_path
        image = bpy.data.images.load(str(illustration))
        width, height = image.size
        pixels = list(image.pixels)
        foreground, bounds, mask = foreground_bounds(pixels, width, height)
        left, bottom, right, top = [value / dimension for value, dimension in
                                    zip(bounds, (width, height, width, height))]
        fitted = fit_foreground([position for position, _ in vertices], (width, height), bounds)
        payload = bytearray(struct.pack("<4sII", b"SCM1", len(vertices), len(indices)))
        for position, (_, normal) in zip(fitted, vertices):
            values = (*position, *normal)
            if not all(math.isfinite(value) for value in values):
                raise ValueError(f"Non-finite geometry: {source}")
            payload.extend(struct.pack("<6f", *values))
        payload.extend(struct.pack(f"<{len(indices)}I", *indices))
        destination = output / (abbreviation + ".scm")
        destination.write_bytes(payload)
        records.append({"id": abbreviation, "source": entry["file"],
                        "sourceSha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                        "mesh": destination.name, "sha256": hashlib.sha256(payload).hexdigest(),
                        "vertices": len(vertices), "triangles": len(indices) // 3,
                        "sourceTriangles": source_triangles, "bytes": len(payload),
                        "illustration": str(illustration.relative_to(culture)),
                        "illustrationSha256": hashlib.sha256(illustration.read_bytes()).hexdigest(),
                        "imageSize": [width, height],
                        "foregroundBoundsPixels": foreground,
                        "fitBoundsPixels": bounds,
                        "foregroundMask": mask,
                        "foregroundThreshold": 0,
                        "foregroundPaddingPixels": 1,
                        "boundsConvention": "bottom-left, exclusive right/top",
                        "sourceMeshBounds": [list(low), list(high)],
                        "imageBounds": [left, bottom, right, top]})
        print(abbreviation, len(vertices), len(indices) // 3, len(payload))
    records.sort(key=lambda record: record["id"])
    manifest = json.dumps({"schemaVersion": 1,
        "coordinateFrame": "image XY, front positive Z",
        "mapping": "foreground-pixel-contain-v1; depth normalized by image width",
        "source": "User Tripo archive/models_final; archive/_manifest.csv",
        "triangleBudget": triangle_budget,
        "excluded": excluded,
        "models": records}, ensure_ascii=False, indent=2) + "\n"
    (output / "manifest.json").write_text(manifest)
    revision = hashlib.sha256(manifest.encode()).hexdigest()[:20]
    assets = [{"name": record["mesh"], "bytes": record["bytes"]} for record in records]
    assets.append({"name": "manifest.json", "bytes": len(manifest.encode())})
    bootstrap.write_text('export interface ConstellationModelAsset {\n  name: string;\n  bytes: number;\n}\n\n' +
        f"export const CONSTELLATION_MODEL_REVISION = '{revision}';\n" +
        'export const CONSTELLATION_MODEL_ASSETS: ConstellationModelAsset[] = ' +
        json.dumps(assets, indent=2) + ';\n')
    print(f"Prepared {len(records)} models; excluded {len(excluded)} unfinished entries")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("culture", type=Path)
    parser.add_argument("--bootstrap", type=Path, default=Path(__file__).resolve().parents[1] /
                        "harmonyos/ets-source/common/config/ConstellationModelAssets.ets")
    parser.add_argument("--triangle-budget", type=int, default=8000)
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    if not 1000 <= arguments.triangle_budget <= 30000:
        parser.error("triangle budget must be between 1000 and 30000")
    prepare(arguments.archive, arguments.culture, arguments.bootstrap, arguments.triangle_budget)
