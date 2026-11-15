import argparse
import json
import math
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


def render_model(path, size):
    data = path.read_bytes()
    magic, vertex_count, index_count = struct.unpack_from('<4sII', data)
    if magic != b'SCM1':
        raise ValueError(path)
    vertices = np.frombuffer(data, dtype='<f4', count=vertex_count * 6, offset=12).reshape(-1, 6)
    triangles = np.frombuffer(data, dtype='<u4', count=index_count, offset=12 + vertex_count * 24).reshape(-1, 3)
    light = np.array([-0.35, 0.5, 0.8])
    light /= np.linalg.norm(light)
    normals = vertices[:, 3:].astype(float)
    normals /= np.linalg.norm(normals, axis=1)[:, None]
    shade = 0.025 + 0.12 * np.maximum(0, normals @ light) + 0.55 * (1 - np.minimum(1, abs(normals[:, 2]))) ** 3
    colors = np.clip(shade[:, None] * np.array([0.60, 0.75, 1.0]) * 255, 0, 255)
    canvas = Image.new('RGB', (size * 2, size * 2), (6, 10, 19))
    painter = ImageDraw.Draw(canvas)
    points = vertices[:, :2] * (size * 2 - 24) + 12
    points[:, 1] = size * 2 - points[:, 1]
    order = np.argsort(vertices[triangles, 2].mean(axis=1))
    for triangle in triangles[order]:
        painter.polygon([tuple(point) for point in points[triangle]],
                        fill=tuple(colors[triangle].mean(axis=0).astype(int)))
    return canvas.resize((size, size), Image.Resampling.LANCZOS)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[1] / 'skycultures/modern/models'
    models = json.loads((root / 'manifest.json').read_text())['models']
    size, columns = 200, 8
    rows = math.ceil(len(models) / columns)
    sheet = Image.new('RGB', (columns * size, rows * (size + 28) + 48), (6, 10, 19))
    painter = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=17)
    painter.text((16, 14), f'{len(models)} user models / runtime mesh front views / not an in-app screenshot', fill='#b7cada', font=font)
    for offset, model in enumerate(models):
        left, top = offset % columns * size, offset // columns * (size + 28) + 48
        sheet.paste(render_model(root / model['mesh'], size), (left, top))
        painter.text((left + 14, top + size), model['id'] + '  ' + str(model['triangles']) + ' tris', fill='#b7cada', font=font)
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(arguments.output)
