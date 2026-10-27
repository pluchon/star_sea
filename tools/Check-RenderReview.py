"""校准画面统计：细纹不能因缩图消失，不规则纯色区域必须能检出。"""

import importlib.util
from pathlib import Path
import unittest

import numpy as np


spec = importlib.util.spec_from_file_location("render_review", Path(__file__).with_name("Review-Render.py"))
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)


class FlatRegionCalibration(unittest.TestCase):
    def test_fine_pattern_keeps_original_variance(self):
        pattern = np.indices((360, 640)).sum(axis=0) % 2
        rgb = np.repeat((0.3 + pattern * 0.3)[:, :, None], 3, axis=2)
        self.assertEqual(review.flat_regions(rgb), [])

    def test_connected_nonrectangular_region(self):
        rgb = np.random.default_rng(42).uniform(0.05, 0.95, (360, 640, 3))
        rgb[90:270, 290:350] = 0.45
        rgb[150:210, 170:470] = 0.45
        regions = review.flat_regions(rgb)
        self.assertTrue(regions)
        self.assertGreater(regions[0]["area_fraction"], 0.05)
        self.assertLess(regions[0]["luminance_std"], 0.02)


if __name__ == "__main__":
    unittest.main()
