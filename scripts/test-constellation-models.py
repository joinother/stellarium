import hashlib
import json
import math
import struct
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "skycultures" / "modern"


class ConstellationModelTests(unittest.TestCase):
    def test_packaged_geometry_and_artwork_anchors(self):
        manifest = json.loads((ROOT / "models/manifest.json").read_text())
        culture = json.loads((ROOT / "index.json").read_text())
        constellations = {entry["id"].split()[-1]: entry for entry in culture["constellations"]}
        self.assertEqual({entry["id"] for entry in manifest["models"]},
                         {"And", "Ant", "Aps", "Aqr", "Aql", "Ara", "Hya"})
        for entry in manifest["models"]:
            with self.subTest(constellation=entry["id"]):
                data = (ROOT / "models" / entry["mesh"]).read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(), entry["sha256"])
                magic, vertex_count, index_count = struct.unpack_from("<4sII", data)
                self.assertEqual(magic, b"SCM1")
                self.assertEqual(vertex_count, entry["vertices"])
                self.assertEqual(index_count, entry["triangles"] * 3)
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
                image = constellations[entry["id"]]["image"]
                self.assertEqual(image["file"], entry["illustration"])
                self.assertEqual(len(image["anchors"]), 3)
                self.assertTrue((ROOT / entry["illustration"]).is_file())


if __name__ == "__main__":
    unittest.main()
