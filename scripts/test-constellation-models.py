import hashlib
import json
import math
import re
import struct
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "skycultures" / "modern"


class ConstellationModelTests(unittest.TestCase):
    def test_packaged_geometry_and_artwork_anchors(self):
        manifest = json.loads((ROOT / "models/manifest.json").read_text())
        culture = json.loads((ROOT / "index.json").read_text())
        constellations = {entry["id"].split()[-1]: entry for entry in culture["constellations"]}
        expected = {key for key, entry in constellations.items() if 'image' in entry} | {'Pup', 'Vel'}
        self.assertEqual({entry["id"] for entry in manifest["models"]}, expected)
        self.assertEqual(len(manifest["models"]), len(expected))
        self.assertEqual({path.name for path in (ROOT / 'models').glob('*.scm')},
                         {entry['mesh'] for entry in manifest['models']})
        shared_groups = {}
        for entry in manifest["models"]:
            with self.subTest(constellation=entry["id"]):
                data = (ROOT / "models" / entry["mesh"]).read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(), entry["sha256"])
                magic, vertex_count, index_count = struct.unpack_from("<4sII", data)
                self.assertEqual(magic, b"SCM1")
                self.assertEqual(vertex_count, entry["vertices"])
                self.assertLessEqual(vertex_count, 65535)
                self.assertEqual(index_count, entry["triangles"] * 3)
                self.assertLessEqual(entry['triangles'], manifest['triangleBudget'])
                self.assertEqual(len(data), entry['bytes'])
                self.assertEqual(len(data), 12 + vertex_count * 24 + index_count * 4)
                vertices = list(struct.iter_unpack("<6f", data[12:12 + vertex_count * 24]))
                for horizontal, vertical, depth, normal_x, normal_y, normal_z in vertices:
                    self.assertTrue(all(math.isfinite(value) for value in
                                        (horizontal, vertical, depth, normal_x, normal_y, normal_z)))
                    self.assertTrue(0 <= horizontal <= 1 and 0 <= vertical <= 1)
                    self.assertLess(abs(depth), 2)
                    self.assertAlmostEqual(normal_x ** 2 + normal_y ** 2 + normal_z ** 2, 1, places=4)
                indices = struct.unpack_from(f"<{index_count}I", data, 12 + vertex_count * 24)
                self.assertLess(max(indices), vertex_count)
                group = entry.get("sharedIllustrationGroup")
                image_owner = "Car" if group == "argonavis" else entry["id"]
                image = constellations[image_owner]["image"]
                self.assertEqual(image["file"], entry["illustration"])
                self.assertEqual(len(image["anchors"]), 3)
                self.assertTrue((ROOT / entry["illustration"]).is_file())
                illustration = ROOT / entry["illustration"]
                self.assertEqual(hashlib.sha256(illustration.read_bytes()).hexdigest(), entry['illustrationSha256'])
                self.assertEqual(entry['imageSize'], image['size'])
                width, height = entry['imageSize']
                left, bottom, right, top = entry['fitBoundsPixels']
                self.assertEqual(entry['boundsConvention'], 'bottom-left, exclusive right/top')
                self.assertEqual(entry['foregroundThreshold'], 0)
                self.assertEqual(entry['foregroundPaddingPixels'], 1)
                self.assertEqual(entry['imageBounds'], [left / width, bottom / height, right / width, top / height])
                self.assertTrue(0 <= left < right <= width and 0 <= bottom < top <= height)
                mesh_low = [min(vertex[axis] for vertex in vertices) for axis in range(3)]
                mesh_high = [max(vertex[axis] for vertex in vertices) for axis in range(3)]
                pixel_width = (mesh_high[0] - mesh_low[0]) * width
                pixel_height = (mesh_high[1] - mesh_low[1]) * height
                source_low, source_high = entry['sourceMeshBounds']
                source_width = source_high[0] - source_low[0]
                source_height = source_high[1] - source_low[1]
                self.assertAlmostEqual(pixel_width / pixel_height, source_width / source_height, places=5)
                if group:
                    shared_groups.setdefault(group, []).append((entry, vertices))
                else:
                    self.assertAlmostEqual((mesh_high[0] + mesh_low[0]) * width / 2, (left + right) / 2, places=4)
                    self.assertAlmostEqual((mesh_high[1] + mesh_low[1]) * height / 2, (bottom + top) / 2, places=4)
                    self.assertLessEqual(pixel_width, right - left + 0.0001)
                    self.assertLessEqual(pixel_height, top - bottom + 0.0001)
                    self.assertAlmostEqual(max(pixel_width / (right - left), pixel_height / (top - bottom)), 1., places=5)
                for vertex in vertices:
                    self.assertTrue(left / width - 1e-7 <= vertex[0] <= right / width + 1e-7)
                    self.assertTrue(bottom / height - 1e-7 <= vertex[1] <= top / height + 1e-7)
        for group, members in shared_groups.items():
            with self.subTest(shared_group=group):
                first_entry = members[0][0]
                width, height = first_entry['imageSize']
                left, bottom, right, top = first_entry['fitBoundsPixels']
                all_verts = [v for _, verts in members for v in verts]
                mesh_low = [min(v[axis] for v in all_verts) for axis in range(3)]
                mesh_high = [max(v[axis] for v in all_verts) for axis in range(3)]
                pixel_width = (mesh_high[0] - mesh_low[0]) * width
                pixel_height = (mesh_high[1] - mesh_low[1]) * height
                source_low, source_high = first_entry['sharedSourceMeshBounds']
                self.assertAlmostEqual(pixel_width / pixel_height,
                                       (source_high[0] - source_low[0]) / (source_high[1] - source_low[1]), places=5)
                self.assertAlmostEqual((mesh_high[0] + mesh_low[0]) * width / 2, (left + right) / 2, places=4)
                self.assertAlmostEqual((mesh_high[1] + mesh_low[1]) * height / 2, (bottom + top) / 2, places=4)
                self.assertAlmostEqual(max(pixel_width / (right - left), pixel_height / (top - bottom)), 1., places=5)

    def test_upgrade_assets_match_exact_manifest_revision(self):
        manifest_bytes = (ROOT / 'models/manifest.json').read_bytes()
        manifest = json.loads(manifest_bytes)
        registry = (ROOT.parents[1] / 'harmonyos/ets-source/common/config/ConstellationModelAssets.ets').read_text()
        revision = re.search(r"MODEL_REVISION = '([a-f0-9]+)'", registry).group(1)
        self.assertEqual(revision, hashlib.sha256(manifest_bytes).hexdigest()[:20])
        assets = json.loads(registry.split('ConstellationModelAsset[] = ', 1)[1].rstrip(';\n'))
        expected = [{'name': entry['mesh'], 'bytes': entry['bytes']} for entry in manifest['models']]
        expected.append({'name': 'manifest.json', 'bytes': len(manifest_bytes)})
        self.assertEqual(assets, expected)


if __name__ == "__main__":
    unittest.main()
