"""Tests for store-art-compose.py. Run: python3 -I kits/app-factory/tools/test_compose.py"""

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
SCRIPT = TOOLS / "store-art-compose.py"
EXAMPLE = TOOLS / "compose.example.json"

HAVE_RENDER_DEPS = all(
    importlib.util.find_spec(m) is not None for m in ("PIL", "fontTools")
)


def run_compose(*args):
    env = {"PATH": os.environ.get("PATH", "")}
    return subprocess.run(
        [sys.executable, "-I", str(SCRIPT), *args],
        capture_output=True,
        text=True,
        env=env,
    )


def touch(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"")


def base_config():
    return {
        "font": None,
        "text_color": [255, 255, 255],
        "out_dir": "out",
        "screenshots_dir": "screens",
        "backgrounds_dir": "backs",
        "mascot_dir": "mascots",
        "shots": [
            {
                "screenshot": "home",
                "background": "sky",
                "flip_background": False,
                "mascot": "wave",
                "headline": "Line one\nLine two",
            },
            {
                "screenshot": "detail",
                "background": "sky",
                "flip_background": True,
                "mascot": None,
                "headline": "Second shot",
            },
        ],
        "feature_graphic": {
            "background": "wide",
            "mascot": "wave",
            "headline": "App Name\nShort tagline",
        },
    }


def write_empty_inputs(root):
    for rel in (
        "screens/home.png",
        "screens/detail.png",
        "backs/sky.png",
        "backs/wide.png",
        "mascots/wave.png",
    ):
        touch(root / rel)


def write_config(root, cfg):
    path = root / "compose.json"
    path.write_text(json.dumps(cfg))
    return path


class ComposeCli(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name).resolve()
        self.addCleanup(self._tmp.cleanup)

    def test_compose_dry_run_lists_outputs(self):
        write_empty_inputs(self.root)
        cfg = write_config(self.root, base_config())
        res = run_compose("--config", str(cfg), "--dry-run")
        self.assertEqual(res.returncode, 0, res.stderr)
        outputs = json.loads(res.stdout)
        out_dir = self.root / "out"
        self.assertEqual(
            [Path(p) for p in outputs],
            [
                out_dir / "phone-home.png",
                out_dir / "phone-detail.png",
                out_dir / "feature-graphic.png",
            ],
        )
        self.assertFalse(out_dir.exists(), "dry-run must not write")

    def test_compose_missing_input_exits_2_naming_file(self):
        write_empty_inputs(self.root)
        (self.root / "screens" / "detail.png").unlink()
        cfg = write_config(self.root, base_config())
        res = run_compose("--config", str(cfg), "--dry-run")
        self.assertEqual(res.returncode, 2)
        self.assertIn("detail", res.stderr)
        self.assertNotIn("Traceback", res.stderr)

    def test_compose_unreadable_config_exits_2(self):
        bad = self.root / "compose.json"
        bad.write_text("{not json")
        res = run_compose("--config", str(bad), "--dry-run")
        self.assertEqual(res.returncode, 2)
        self.assertNotIn("Traceback", res.stderr)

    def test_compose_missing_key_exits_2_naming_key(self):
        cfg = base_config()
        del cfg["backgrounds_dir"]
        path = write_config(self.root, cfg)
        res = run_compose("--config", str(path), "--dry-run")
        self.assertEqual(res.returncode, 2)
        self.assertIn("backgrounds_dir", res.stderr)

    def test_compose_mascot_without_mascot_dir_exits_2(self):
        write_empty_inputs(self.root)
        cfg = base_config()
        cfg["mascot_dir"] = None
        path = write_config(self.root, cfg)
        res = run_compose("--config", str(path), "--dry-run")
        self.assertEqual(res.returncode, 2)
        self.assertIn("mascot_dir", res.stderr)

    def test_compose_duplicate_screenshot_exits_2(self):
        write_empty_inputs(self.root)
        cfg = base_config()
        cfg["shots"][1]["screenshot"] = "home"
        path = write_config(self.root, cfg)
        res = run_compose("--config", str(path), "--dry-run")
        self.assertEqual(res.returncode, 2)
        self.assertIn("home", res.stderr)

    def test_compose_feature_graphic_null_is_omitted(self):
        write_empty_inputs(self.root)
        cfg = base_config()
        cfg["feature_graphic"] = None
        path = write_config(self.root, cfg)
        res = run_compose("--config", str(path), "--dry-run")
        self.assertEqual(res.returncode, 0, res.stderr)
        names = [Path(p).name for p in json.loads(res.stdout)]
        self.assertEqual(names, ["phone-home.png", "phone-detail.png"])

    def test_example_config_is_dry_run_valid(self):
        example = json.loads(EXAMPLE.read_text())
        for key in ("screenshots_dir", "backgrounds_dir"):
            self.assertIn(key, example)
        for shot in example["shots"]:
            touch(self.root / example["screenshots_dir"] / shot["screenshot"])
            touch(self.root / example["backgrounds_dir"] / shot["background"])
            if shot.get("mascot"):
                touch(self.root / example["mascot_dir"] / shot["mascot"])
        fg = example.get("feature_graphic")
        if fg:
            touch(self.root / example["backgrounds_dir"] / fg["background"])
            if fg.get("mascot"):
                touch(self.root / example["mascot_dir"] / fg["mascot"])
        if example.get("font"):
            touch(self.root / example["font"])
        cfg = self.root / "compose.json"
        cfg.write_text(EXAMPLE.read_text())
        res = run_compose("--config", str(cfg), "--dry-run")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertTrue(json.loads(res.stdout))


@unittest.skipUnless(HAVE_RENDER_DEPS, "Pillow and fontTools are required")
class ComposeRender(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name).resolve()
        self.addCleanup(self._tmp.cleanup)

    def make_inputs(self):
        from PIL import Image

        for rel, size, color in (
            ("screens/home.png", (400, 800), (200, 30, 30)),
            ("screens/detail.png", (400, 800), (30, 200, 30)),
            ("backs/sky.png", (1080, 1920), (30, 60, 200)),
            ("backs/wide.png", (1024, 800), (60, 30, 200)),
        ):
            path = self.root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            Image.new("RGB", size, color).save(path)
        mascot = self.root / "mascots" / "wave.png"
        mascot.parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGBA", (200, 200), (255, 220, 0, 255)).save(mascot)

    def test_compose_renders_phone_shot(self):
        from PIL import Image

        self.make_inputs()
        cfg = write_config(self.root, base_config())
        res = run_compose("--config", str(cfg))
        self.assertEqual(res.returncode, 0, res.stderr)
        out = self.root / "out" / "phone-home.png"
        with Image.open(out) as img:
            self.assertEqual(img.format, "PNG")
            self.assertEqual(img.size, (1080, 1920))
            rgb = img.convert("RGB")
            self.assertEqual(rgb.getpixel((540, 1164)), (200, 30, 30))
            self.assertEqual(rgb.getpixel((5, 1900)), (30, 60, 200))

    def test_compose_renders_all_declared_outputs(self):
        from PIL import Image

        self.make_inputs()
        cfg = write_config(self.root, base_config())
        res = run_compose("--config", str(cfg))
        self.assertEqual(res.returncode, 0, res.stderr)
        listed = [Path(p) for p in json.loads(res.stdout)]
        self.assertEqual(len(listed), 3)
        sizes = {}
        for p in listed:
            with Image.open(p) as img:
                sizes[p.name] = img.size
        self.assertEqual(sizes["phone-detail.png"], (1080, 1920))
        self.assertEqual(sizes["feature-graphic.png"], (1024, 500))

    def test_compose_headline_is_drawn(self):
        from PIL import Image

        self.make_inputs()
        cfg = write_config(self.root, base_config())
        self.assertEqual(run_compose("--config", str(cfg)).returncode, 0)
        with Image.open(self.root / "out" / "phone-detail.png") as img:
            band = img.convert("RGB").crop((0, 0, 1080, 300))
            self.assertGreater(len(band.getcolors(maxcolors=1 << 20)), 1)

    def test_compose_unreadable_image_exits_2(self):
        self.make_inputs()
        (self.root / "screens" / "home.png").write_bytes(b"not an image")
        cfg = write_config(self.root, base_config())
        res = run_compose("--config", str(cfg))
        self.assertEqual(res.returncode, 2)
        self.assertIn("home", res.stderr)
        self.assertNotIn("Traceback", res.stderr)


if __name__ == "__main__":
    unittest.main()
