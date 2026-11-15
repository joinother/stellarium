import importlib.util
import json
import unittest
from pathlib import Path


SPEC = importlib.util.spec_from_file_location(
    "model_exporter", Path(__file__).with_name("prepare-constellation-models.py"))
EXPORTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EXPORTER)


class ForegroundMappingTests(unittest.TestCase):
    def test_packaged_masks_against_independent_source_image_decode(self):
        try:
            from PIL import Image, ImageChops
        except ImportError:
            self.skipTest("Pillow required for independent PNG verification")
        root = Path(__file__).resolve().parents[1] / 'skycultures/modern'
        manifest = json.loads((root / 'models/manifest.json').read_text())
        corrected = 0
        for entry in manifest['models']:
            with self.subTest(constellation=entry['id']):
                with Image.open(root / entry['illustration']) as source:
                    rgba = source.convert('RGBA')
                    red, green, blue, alpha = rgba.split()
                    if alpha.getextrema()[0] < 255:
                        mask, policy = alpha, 'alpha-positive'
                    else:
                        mask = ImageChops.lighter(ImageChops.lighter(red, green), blue)
                        policy = 'rgb-positive-black-background'
                    left, top, right, bottom = mask.getbbox()
                    width, height = source.size
                    expected = [left, height - bottom, right, height - top]
                    padded = [max(0, left - 1), max(0, height - bottom - 1),
                              min(width, right + 1), min(height, height - top + 1)]
                    self.assertEqual(entry['foregroundBoundsPixels'], expected)
                    self.assertEqual(entry['fitBoundsPixels'], padded)
                    self.assertEqual(entry['foregroundMask'], policy)
                    corrected += padded != [0, 0, width, height]
        self.assertGreater(corrected, 0)

    def test_opaque_black_background_keeps_faint_and_detached_extensions(self):
        width, height = 12, 10
        pixels = [0., 0., 0., 1.] * (width * height)
        for horizontal, vertical, brightness in [(5, 4, 0.8), (6, 5, 0.8), (2, 1, 1e-7), (9, 7, 1e-7)]:
            offset = (vertical * width + horizontal) * 4
            pixels[offset:offset + 3] = [0., brightness, 0.]
        raw, padded, policy = EXPORTER.foreground_bounds(pixels, width, height)
        self.assertEqual(raw, [2, 1, 10, 8])
        self.assertEqual(padded, [1, 0, 11, 9])
        self.assertEqual(policy, "rgb-positive-black-background")

    def test_transparent_black_foreground_ignores_hidden_rgb(self):
        pixels = [1., 1., 1., 0.] * 30
        pixels[(2 * 6 + 3) * 4:(2 * 6 + 3) * 4 + 4] = [0., 0., 0., 1e-7]
        self.assertEqual(EXPORTER.foreground_bounds(pixels, 6, 5),
                         ([3, 2, 4, 3], [2, 1, 5, 4], "alpha-positive"))

    def test_padding_clamps_to_canvas_and_keeps_bottom_left_origin(self):
        pixels = [0., 0., 0., 1.] * 24
        pixels[:4] = [0.1, 0., 0., 1.]
        self.assertEqual(EXPORTER.foreground_bounds(pixels, 6, 4)[:2],
                         ([0, 0, 1, 1], [0, 0, 2, 2]))

    def test_empty_and_invalid_images_fail_instead_of_using_whole_canvas(self):
        for pixels in ([0., 0., 0., 1.] * 4, [1., 1., 1., 0.] * 4):
            with self.assertRaises(ValueError):
                EXPORTER.foreground_bounds(pixels, 2, 2)
        with self.assertRaises(ValueError):
            EXPORTER.foreground_bounds([], 2, 2)

    def test_non_square_canvas_preserves_pixel_aspect_and_depth_scale(self):
        positions = [(10., 20., -2.), (12., 21., 2.)]
        fitted = EXPORTER.fit_foreground(positions, (200, 100), [40, 10, 160, 90])
        for actual, expected in zip(fitted, [(0.2, 0.2, -0.6), (0.8, 0.8, 0.6)]):
            for coordinate, target in zip(actual, expected):
                self.assertAlmostEqual(coordinate, target)
        pixel_width = (fitted[1][0] - fitted[0][0]) * 200
        pixel_height = (fitted[1][1] - fitted[0][1]) * 100
        self.assertAlmostEqual(pixel_width / pixel_height, 2.)

    def test_height_limited_offset_fit_does_not_stretch_or_recenter_canvas(self):
        fitted = EXPORTER.fit_foreground([(0., 0., 0.), (1., 4., 0.)],
                                          (200, 100), [100, 20, 180, 80])
        for actual, expected in zip(fitted, [(0.6625, 0.2, 0.), (0.7375, 0.8, 0.)]):
            for coordinate, target in zip(actual, expected):
                self.assertAlmostEqual(coordinate, target)
        with self.assertRaises(ValueError):
            EXPORTER.fit_foreground([(0, 0, 0), (0, 1, 0)], (200, 100), [100, 20, 180, 80])


if __name__ == "__main__":
    unittest.main()
