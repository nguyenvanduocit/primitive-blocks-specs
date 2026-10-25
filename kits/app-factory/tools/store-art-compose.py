"""Compose store listing images from backgrounds, app screenshots and mascot sprites.

Usage:
    python3 -I store-art-compose.py --config FILE [--dry-run]

Inputs:
    FILE is a JSON config. Every relative path in it resolves against the folder
    that holds FILE. Image names may carry an extension ("home.png") or omit it
    ("home"); an omitted extension is looked up as .png, .webp, .jpg, .jpeg.

    {
      "font": "fonts/title.woff2" | null,   .ttf, .otf or .woff2; null = Pillow default font
      "text_color": [r, g, b],              headline fill
      "outline_color": [r, g, b],           optional; default black or white, whichever contrasts
      "out_dir": "store",
      "screenshots_dir": "screenshots",
      "backgrounds_dir": "art",
      "mascot_dir": "mascots" | null,       required when any mascot is named
      "shots": [
        {"screenshot": "home", "background": "sky", "flip_background": false,
         "mascot": "wave" | null, "headline": "Two line\\nheadline"}
      ],
      "feature_graphic": {"background": "wide", "mascot": "wave" | null,
                          "headline": "Title\\nOptional tagline"} | null
    }

Outputs, in out_dir:
    phone-<screenshot>.png   1080x1920, one per entry of "shots"
    feature-graphic.png      1024x500, only when "feature_graphic" is set

    The mascot peeks out from alternating sides of the phone frame, starting on
    the right for the first shot. The feature graphic headline has at most two
    lines: the first is the title, the second the tagline.

Behaviour:
    --dry-run validates the config, checks that every input file exists and
    prints the JSON list of output paths without writing anything. A normal run
    writes the images and prints the same list.

Exit codes:
    0 success
    2 bad config, missing or unreadable input file (stderr names the problem)

Requires Pillow; fontTools is imported only for .woff2 fonts.
"""

import argparse
import io
import json
import sys
from pathlib import Path

IMAGE_EXTENSIONS = (".png", ".webp", ".jpg", ".jpeg")
PHONE_SIZE = (1080, 1920)
FEATURE_SIZE = (1024, 500)


class ConfigError(Exception):
    """A problem in the config or its input files; reported on stderr with exit code 2."""


# ---------------------------------------------------------------- config (pure)


def require(obj, key, kind, where):
    if key not in obj:
        raise ConfigError(f"{where}: missing key '{key}'")
    if not isinstance(obj[key], kind):
        raise ConfigError(f"{where}: '{key}' must be {kind.__name__}")
    return obj[key]


def optional_str(obj, key, where):
    value = obj.get(key)
    if value is not None and not isinstance(value, str):
        raise ConfigError(f"{where}: '{key}' must be a string or null")
    return value


def parse_color(value, where):
    ok = (
        isinstance(value, list)
        and len(value) == 3
        and all(
            isinstance(c, int) and not isinstance(c, bool) and 0 <= c <= 255
            for c in value
        )
    )
    if not ok:
        raise ConfigError(f"{where} must be [r, g, b] with integers 0-255")
    return tuple(value)


def contrast_color(fill):
    luma = 0.299 * fill[0] + 0.587 * fill[1] + 0.114 * fill[2]
    return (0, 0, 0) if luma > 128 else (255, 255, 255)


def stem(name):
    p = Path(name)
    return p.stem if p.suffix.lower() in IMAGE_EXTENSIONS else p.name


def find_image(directory, name):
    """Return the existing file for `name` in `directory`, or the exact path when none exists."""
    exact = directory / name
    if exact.is_file():
        return exact
    for ext in IMAGE_EXTENSIONS:
        candidate = directory / (name + ext)
        if candidate.is_file():
            return candidate
    return exact


def load_config(config_path):
    """Parse and validate the config. Returns a dict with every path resolved; no I/O beyond reading it."""
    config_path = Path(config_path)
    try:
        raw = json.loads(config_path.read_text())
    except OSError as e:
        raise ConfigError(f"cannot read config {config_path}: {e.strerror}")
    except json.JSONDecodeError as e:
        raise ConfigError(f"config {config_path} is not valid JSON: {e}")
    if not isinstance(raw, dict):
        raise ConfigError("config: top level must be an object")

    base = config_path.resolve().parent

    def path_of(value):
        return base / value

    text_color = parse_color(raw.get("text_color"), "config: 'text_color'")
    outline = raw.get("outline_color")
    outline_color = (
        parse_color(outline, "config: 'outline_color'")
        if outline is not None
        else contrast_color(text_color)
    )

    font = optional_str(raw, "font", "config")
    mascot_dir = optional_str(raw, "mascot_dir", "config")
    shots_raw = require(raw, "shots", list, "config")
    feature_raw = raw.get("feature_graphic")
    if feature_raw is not None and not isinstance(feature_raw, dict):
        raise ConfigError("config: 'feature_graphic' must be an object or null")

    screenshots_dir = path_of(require(raw, "screenshots_dir", str, "config"))
    backgrounds_dir = path_of(require(raw, "backgrounds_dir", str, "config"))
    out_dir = path_of(require(raw, "out_dir", str, "config"))

    def mascot_path(entry, where):
        name = optional_str(entry, "mascot", where)
        if name is None:
            return None
        if mascot_dir is None:
            raise ConfigError(
                f"{where}: names mascot '{name}' but 'mascot_dir' is null"
            )
        return find_image(path_of(mascot_dir), name)

    shots = []
    seen = set()
    for i, entry in enumerate(shots_raw):
        where = f"shots[{i}]"
        if not isinstance(entry, dict):
            raise ConfigError(f"{where}: must be an object")
        screenshot = require(entry, "screenshot", str, where)
        flip = entry.get("flip_background", False)
        if not isinstance(flip, bool):
            raise ConfigError(f"{where}: 'flip_background' must be true or false")
        output = out_dir / f"phone-{stem(screenshot)}.png"
        if output in seen:
            raise ConfigError(
                f"{where}: screenshot '{screenshot}' produces {output.name} twice"
            )
        seen.add(output)
        shots.append(
            {
                "screenshot": find_image(screenshots_dir, screenshot),
                "background": find_image(
                    backgrounds_dir, require(entry, "background", str, where)
                ),
                "flip": flip,
                "mascot": mascot_path(entry, where),
                "headline": require(entry, "headline", str, where),
                "output": output,
            }
        )

    feature = None
    if feature_raw is not None:
        where = "feature_graphic"
        headline = require(feature_raw, "headline", str, where)
        if len(headline.split("\n")) > 2:
            raise ConfigError(f"{where}: headline has at most 2 lines (title, tagline)")
        feature = {
            "background": find_image(
                backgrounds_dir, require(feature_raw, "background", str, where)
            ),
            "mascot": mascot_path(feature_raw, where),
            "headline": headline,
            "output": out_dir / "feature-graphic.png",
        }

    return {
        "font": path_of(font) if font else None,
        "text_color": text_color,
        "outline_color": outline_color,
        "out_dir": out_dir,
        "shots": shots,
        "feature_graphic": feature,
    }


def input_files(cfg):
    files = [cfg["font"]] if cfg["font"] else []
    for shot in cfg["shots"]:
        files += [shot["screenshot"], shot["background"]]
        if shot["mascot"]:
            files.append(shot["mascot"])
    fg = cfg["feature_graphic"]
    if fg:
        files.append(fg["background"])
        if fg["mascot"]:
            files.append(fg["mascot"])
    return files


def output_files(cfg):
    outputs = [shot["output"] for shot in cfg["shots"]]
    if cfg["feature_graphic"]:
        outputs.append(cfg["feature_graphic"]["output"])
    return outputs


def check_inputs(cfg):
    missing = [str(p) for p in input_files(cfg) if not p.is_file()]
    if missing:
        raise ConfigError("input file not found: " + ", ".join(missing))


# ------------------------------------------------------------ compositing (Pillow)


def make_font_loader(font_path):
    """Return size -> ImageFont. A None path selects Pillow's default font."""
    from PIL import ImageFont

    if font_path is None:
        return lambda size: ImageFont.load_default(size)
    if font_path.suffix.lower() == ".woff2":
        from fontTools.ttLib import TTFont

        ttf = TTFont(str(font_path))
        ttf.flavor = None
        buf = io.BytesIO()
        ttf.save(buf)
        data = buf.getvalue()
        return lambda size: ImageFont.truetype(io.BytesIO(data), size)
    return lambda size: ImageFont.truetype(str(font_path), size)


def open_image(path):
    from PIL import Image

    try:
        img = Image.open(path)
        img.load()
        return img
    except (OSError, ValueError) as e:
        raise ConfigError(f"cannot read image {path}: {e}")


def cover(img, w, h):
    from PIL import Image, ImageOps

    return ImageOps.fit(
        img.convert("RGB"), (w, h), method=Image.LANCZOS, centering=(0.5, 0.5)
    )


def rounded(img, radius):
    from PIL import Image, ImageDraw

    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *img.size), radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def sprite(path, size):
    from PIL import Image

    return open_image(path).convert("RGBA").resize((size, size), Image.LANCZOS)


class Painter:
    def __init__(self, cfg):
        self.fonts = make_font_loader(cfg["font"])
        self.fill = cfg["text_color"]
        self.outline = cfg["outline_color"]

    def headline(self, canvas, text, size, xy, anchor):
        from PIL import ImageDraw

        ImageDraw.Draw(canvas).multiline_text(
            xy,
            text,
            font=self.fonts(size),
            fill=self.fill,
            stroke_width=max(6, size // 12),
            stroke_fill=self.outline,
            anchor=anchor,
            align="center" if anchor[0] == "m" else "left",
            spacing=size // 10,
        )

    def line(self, canvas, text, size, xy, stroke):
        from PIL import ImageDraw

        ImageDraw.Draw(canvas).text(
            xy,
            text,
            font=self.fonts(size),
            fill=self.fill,
            stroke_width=stroke,
            stroke_fill=self.outline,
            anchor="ls",
        )

    def phone_shot(self, index, shot):
        from PIL import Image, ImageDraw, ImageFilter, ImageOps

        W, H = PHONE_SIZE
        bg = open_image(shot["background"])
        canvas = cover(ImageOps.mirror(bg) if shot["flip"] else bg, W, H).convert(
            "RGBA"
        )

        screen = open_image(shot["screenshot"]).convert("RGB")
        ph = 1500
        screen = screen.resize(
            (round(screen.width * ph / screen.height), ph), Image.LANCZOS
        )
        bezel = 14
        frame = rounded(
            Image.new("RGB", (screen.width + 2 * bezel, ph + 2 * bezel), (20, 24, 48)),
            70,
        )
        inner = rounded(screen, 58)
        frame.paste(inner, (bezel, bezel), inner)
        x, y = (W - frame.width) // 2, 400

        if shot["mascot"]:
            fox = sprite(shot["mascot"], 330)
            peek = 110
            on_right = index % 2 == 0
            canvas.alpha_composite(
                fox if on_right else ImageOps.mirror(fox),
                (x + frame.width - peek if on_right else x - fox.width + peek, 1230),
            )

        shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle(
            (x, y + 24, x + frame.width, y + frame.height + 24),
            70,
            fill=(10, 20, 70, 110),
        )
        canvas = Image.alpha_composite(
            canvas, shadow.filter(ImageFilter.GaussianBlur(28))
        )
        canvas.alpha_composite(frame, (x, y))

        self.headline(canvas, shot["headline"], 96, (W // 2, 70), "ma")
        save_png(canvas, shot["output"])

    def feature_graphic(self, fg):
        from PIL import Image

        W, H = FEATURE_SIZE
        bg = open_image(fg["background"]).convert("RGB")
        band_h = round(bg.width * H / W)
        if band_h >= bg.height:
            canvas = cover(bg, W, H)
        else:
            top = min(120, bg.height - band_h)
            canvas = bg.crop((0, top, bg.width, top + band_h)).resize(
                (W, H), Image.LANCZOS
            )
        canvas = canvas.convert("RGBA")

        if fg["mascot"]:
            canvas.alpha_composite(sprite(fg["mascot"], 420), (W - 420 - 20, 60))

        title, _, tagline = fg["headline"].partition("\n")
        self.line(canvas, title, 108, (56, 160), 10)
        if tagline:
            self.line(canvas, tagline, 38, (60, 255), 6)
        save_png(canvas, fg["output"])


def save_png(canvas, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(path)


def render(cfg):
    painter = Painter(cfg)
    for i, shot in enumerate(cfg["shots"]):
        painter.phone_shot(i, shot)
    if cfg["feature_graphic"]:
        painter.feature_graphic(cfg["feature_graphic"])


# --------------------------------------------------------------------------- CLI


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Compose store listing images from a JSON config.",
    )
    parser.add_argument("--config", required=True, help="path to the JSON config")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="validate and list outputs without writing",
    )
    args = parser.parse_args(argv)

    try:
        cfg = load_config(args.config)
        check_inputs(cfg)
        if not args.dry_run:
            render(cfg)
    except ConfigError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    print(json.dumps([str(p) for p in output_files(cfg)], indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
