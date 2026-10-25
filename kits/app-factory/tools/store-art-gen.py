#!/usr/bin/env python3
"""Generate one store-listing background image through an image-generation API.

Usage:
    store-art-gen.py <name> <WxH> <prompt> --out-dir DIR [--dry-run]

Inputs:
    name       File name without extension. The image is written to DIR/<name>.png.
    WxH        Pixel size such as 1024x500 (digits, "x", digits).
    prompt     Text description of the image.
    --out-dir  Directory for the output file. Created if missing.
    --dry-run  Print the request as one JSON object
               {"url", "model", "size", "prompt", "out"} and exit 0.
               Calls no service and does not need the API key.

Environment variables:
    OPENROUTER_API_KEY  Bearer key for the API. Required unless --dry-run.
    IMG_MODEL           Model id. Default: openai/gpt-image-2.

Exit codes:
    0  success
    2  bad input or missing environment variable (the message names it)
"""

import argparse
import base64
import json
import os
import re
import sys
import urllib.request

URL = "https://openrouter.ai/api/v1/images"
DEFAULT_MODEL = "openai/gpt-image-2"
KEY_VAR = "OPENROUTER_API_KEY"


def fail(message):
    print(f"store-art-gen: {message}", file=sys.stderr)
    sys.exit(2)


def build_request(name, size, prompt, out_dir):
    model = os.environ.get("IMG_MODEL", DEFAULT_MODEL)
    return {
        "url": URL,
        "model": model,
        "size": size,
        "prompt": prompt,
        "out": os.path.join(out_dir, f"{name}.png"),
    }


def generate(spec, key):
    body = json.dumps(
        {"model": spec["model"], "prompt": spec["prompt"], "size": spec["size"]}
    ).encode()
    req = urllib.request.Request(
        spec["url"],
        data=body,
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=290) as r:
        data = json.load(r)
    os.makedirs(os.path.dirname(spec["out"]) or ".", exist_ok=True)
    with open(spec["out"], "wb") as f:
        f.write(base64.b64decode(data["data"][0]["b64_json"]))


def main():
    p = argparse.ArgumentParser(
        description="Generate one store-listing background image."
    )
    p.add_argument("name")
    p.add_argument("size", metavar="WxH")
    p.add_argument("prompt")
    p.add_argument("--out-dir", required=True)
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args()

    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", a.name):
        fail(
            f"name '{a.name}' must be a plain file name (letters, digits, '.', '_', '-')"
        )
    if not re.fullmatch(r"\d+x\d+", a.size):
        fail(f"size '{a.size}' must look like 1024x500")
    spec = build_request(a.name, a.size, a.prompt, a.out_dir)
    if a.dry_run:
        print(json.dumps(spec))
        return
    key = os.environ.get(KEY_VAR)
    if not key:
        fail(f"missing environment variable {KEY_VAR}")
    generate(spec, key)
    print("saved", spec["out"])


if __name__ == "__main__":
    main()
