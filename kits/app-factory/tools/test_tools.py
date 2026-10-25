"""Tests for the app-factory tools. Run: python3 -I kits/app-factory/tools/test_tools.py"""

import json
import os
import subprocess
import sys
import unittest

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))


def run_tool(script, args, extra_env=None):
    """Run a tool as `python3 -I` with an explicit environment (no inherited secrets)."""
    env = {"PATH": os.environ.get("PATH", "")}
    env.update(extra_env or {})
    return subprocess.run(
        [sys.executable, "-I", os.path.join(TOOLS_DIR, script), *args],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )


class StoreArtGenTests(unittest.TestCase):
    def test_gen_dry_run_prints_request_without_key(self):
        r = run_tool(
            "store-art-gen.py",
            ["hero", "1024x500", "a calm gradient", "--out-dir", "art", "--dry-run"],
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        d = json.loads(r.stdout)
        self.assertEqual(set(d), {"url", "model", "size", "prompt", "out"})
        self.assertEqual(d["size"], "1024x500")
        self.assertEqual(d["prompt"], "a calm gradient")
        self.assertEqual(d["model"], "openai/gpt-image-2")
        self.assertTrue(d["out"].endswith("hero.png"), d["out"])

    def test_gen_missing_key_exits_2_naming_variable(self):
        r = run_tool("store-art-gen.py", ["hero", "1024x500", "p", "--out-dir", "art"])
        self.assertEqual(r.returncode, 2)
        self.assertIn("OPENROUTER_API_KEY", r.stderr)

    def test_gen_bad_size_exits_2(self):
        r = run_tool(
            "store-art-gen.py", ["hero", "big", "p", "--out-dir", "art", "--dry-run"]
        )
        self.assertEqual(r.returncode, 2)
        self.assertIn("big", r.stderr)

    def test_gen_name_with_path_parts_exits_2(self):
        for name in ("../escape", "a/b", ".hidden", ""):
            r = run_tool(
                "store-art-gen.py",
                [name, "1024x500", "p", "--out-dir", "art", "--dry-run"],
            )
            self.assertEqual(r.returncode, 2, name)
            self.assertIn("name", r.stderr)


if __name__ == "__main__":
    unittest.main()
