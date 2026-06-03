#!/usr/bin/env python3
"""Generate Roana app icon assets for Android and iOS."""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]

BACKGROUND = "#faf6ed"
GRADIENT_STOPS = (
    (0.0, (196, 149, 107, 255)),
    (0.5, (168, 133, 61, 255)),
    (1.0, (107, 142, 78, 255)),
)
START_COLOR = (196, 149, 107, 255)
END_COLOR = (107, 142, 78, 255)

# Source coordinates match assets/logo.svg after its group transform.
MARK_PATH = (
    ("M", (38.0, 160.0)),
    ("L", (38.0, 52.0)),
    ("Q", (38.0, 48.0), (42.0, 48.0)),
    ("L", (84.0, 48.0)),
    ("Q", (112.0, 48.0), (112.0, 74.0)),
    ("Q", (112.0, 98.0), (84.0, 98.0)),
    ("L", (58.0, 98.0)),
    ("Q", (52.0, 98.0), (56.0, 104.0)),
    ("L", (128.0, 160.0)),
    ("Q", (162.0, 150.0), (180.0, 120.0)),
)

MARK_TARGET_WIDTH = 480.0
SOURCE_SCALE = MARK_TARGET_WIDTH / 142.0
SOURCE_TRANSLATE = (
    ((1024.0 - MARK_TARGET_WIDTH) / 2.0) - (38.0 * SOURCE_SCALE),
    ((1024.0 - ((160.0 - 48.0) * SOURCE_SCALE)) / 2.0) - (48.0 * SOURCE_SCALE),
)
STROKE_WIDTH = 11.0 * SOURCE_SCALE
DOT_RADIUS = 7.0 * SOURCE_SCALE

ANDROID_DENSITIES = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}

IOS_ICONS = (
    ("iphone", "20x20", "2x", 40),
    ("iphone", "20x20", "3x", 60),
    ("iphone", "29x29", "2x", 58),
    ("iphone", "29x29", "3x", 87),
    ("iphone", "40x40", "2x", 80),
    ("iphone", "40x40", "3x", 120),
    ("iphone", "60x60", "2x", 120),
    ("iphone", "60x60", "3x", 180),
    ("ios-marketing", "1024x1024", "1x", 1024),
)


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def interpolate_color(position: float) -> tuple[int, int, int, int]:
    position = max(0.0, min(1.0, position))
    for index, (stop, color) in enumerate(GRADIENT_STOPS[1:], start=1):
        previous_stop, previous_color = GRADIENT_STOPS[index - 1]
        if position <= stop:
            span = stop - previous_stop
            local = 0.0 if span == 0 else (position - previous_stop) / span
            return tuple(
                round(previous_color[channel] + ((color[channel] - previous_color[channel]) * local))
                for channel in range(4)
            )
    return GRADIENT_STOPS[-1][1]


def quadratic(
    start: tuple[float, float],
    control: tuple[float, float],
    end: tuple[float, float],
    position: float,
) -> tuple[float, float]:
    inverse = 1.0 - position
    x = (inverse * inverse * start[0]) + (2.0 * inverse * position * control[0]) + (position * position * end[0])
    y = (inverse * inverse * start[1]) + (2.0 * inverse * position * control[1]) + (position * position * end[1])
    return x, y


def source_points() -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    current = (0.0, 0.0)
    for command in MARK_PATH:
        if command[0] == "M":
            current = command[1]
            points.append(current)
        elif command[0] == "L":
            end = command[1]
            distance = math.dist(current, end)
            steps = max(2, math.ceil(distance / 2.0))
            for step in range(1, steps + 1):
                t = step / steps
                points.append((
                    current[0] + ((end[0] - current[0]) * t),
                    current[1] + ((end[1] - current[1]) * t),
                ))
            current = end
        elif command[0] == "Q":
            control, end = command[1], command[2]
            distance = math.dist(current, control) + math.dist(control, end)
            steps = max(8, math.ceil(distance / 1.0))
            for step in range(1, steps + 1):
                points.append(quadratic(current, control, end, step / steps))
            current = end
    return points


def transform_point(point: tuple[float, float], size: int, supersample: int) -> tuple[float, float]:
    scale = (size / 1024.0) * supersample
    return (
        ((point[0] * SOURCE_SCALE) + SOURCE_TRANSLATE[0]) * scale,
        ((point[1] * SOURCE_SCALE) + SOURCE_TRANSLATE[1]) * scale,
    )


def draw_icon(size: int, *, include_background: bool) -> Image.Image:
    supersample = 4 if size < 512 else 2
    canvas_size = size * supersample
    mode = "RGB" if include_background else "RGBA"
    background = BACKGROUND if include_background else (0, 0, 0, 0)
    image = Image.new(mode, (canvas_size, canvas_size), background)

    points = [transform_point(point, size, supersample) for point in source_points()]
    stroke_width = round(STROKE_WIDTH * (size / 1024.0) * supersample)

    mask = Image.new("L", (canvas_size, canvas_size), 0)
    mask_draw = ImageDraw.Draw(mask)
    radius = stroke_width / 2.0
    step = max(1, stroke_width // 6)
    for start, end in zip(points, points[1:]):
        distance = math.dist(start, end)
        steps = max(1, math.ceil(distance / step))
        for index in range(steps + 1):
            position = index / steps
            x = start[0] + ((end[0] - start[0]) * position)
            y = start[1] + ((end[1] - start[1]) * position)
            mask_draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=255)

    dot_radius = DOT_RADIUS * (size / 1024.0) * supersample
    for point in (points[0], points[-1]):
        mask_draw.ellipse(
            (point[0] - dot_radius, point[1] - dot_radius, point[0] + dot_radius, point[1] + dot_radius),
            fill=255,
        )

    gradient = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    pixels = []
    denominator = max(1, (canvas_size - 1) * 2)
    for y in range(canvas_size):
        for x in range(canvas_size):
            pixels.append(interpolate_color((x + (canvas_size - 1 - y)) / denominator))
    gradient.putdata(pixels)

    image = Image.composite(gradient.convert(mode), image, mask)
    if supersample > 1:
        image = image.resize((size, size), Image.Resampling.LANCZOS)
    return image


def write_png(path: Path, image: Image.Image) -> None:
    ensure_dir(path.parent)
    image.save(path, "PNG", optimize=True)


def path_d() -> str:
    parts: list[str] = []
    for command in MARK_PATH:
        if command[0] == "M":
            parts.append(f"M {command[1][0]:g} {command[1][1]:g}")
        elif command[0] == "L":
            parts.append(f"L {command[1][0]:g} {command[1][1]:g}")
        elif command[0] == "Q":
            parts.append(
                f"Q {command[1][0]:g} {command[1][1]:g}, {command[2][0]:g} {command[2][1]:g}"
            )
    return " ".join(parts)


def transform_source_coordinate(point: tuple[float, float]) -> tuple[float, float]:
    return (
        (point[0] * SOURCE_SCALE) + SOURCE_TRANSLATE[0],
        (point[1] * SOURCE_SCALE) + SOURCE_TRANSLATE[1],
    )


def path_d_transformed() -> str:
    parts: list[str] = []
    for command in MARK_PATH:
        if command[0] == "M":
            point = transform_source_coordinate(command[1])
            parts.append(f"M {point[0]:.3f},{point[1]:.3f}")
        elif command[0] == "L":
            point = transform_source_coordinate(command[1])
            parts.append(f"L {point[0]:.3f},{point[1]:.3f}")
        elif command[0] == "Q":
            control = transform_source_coordinate(command[1])
            end = transform_source_coordinate(command[2])
            parts.append(f"Q {control[0]:.3f},{control[1]:.3f} {end[0]:.3f},{end[1]:.3f}")
    return " ".join(parts)


def write_source_svg() -> None:
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024" role="img" aria-label="Roana app icon">
  <title>Roana</title>
  <defs>
    <linearGradient id="roana-app-icon-r" x1="0" y1="1" x2="1" y2="0">
      <stop offset="0%" stop-color="#c4956b" />
      <stop offset="50%" stop-color="#a8853d" />
      <stop offset="100%" stop-color="#6b8e4e" />
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" fill="{BACKGROUND}" />
  <g transform="translate({SOURCE_TRANSLATE[0]:.4f}, {SOURCE_TRANSLATE[1]:.4f}) scale({SOURCE_SCALE:.6f})">
    <path d="{path_d()}"
          stroke="url(#roana-app-icon-r)" stroke-width="11" fill="none" stroke-linecap="round" stroke-linejoin="round" />
    <circle cx="38" cy="160" r="7" fill="#c4956b" />
    <circle cx="180" cy="120" r="7" fill="#6b8e4e" />
  </g>
</svg>
"""
    (ROOT / "assets" / "app-icon.svg").write_text(svg, encoding="utf-8")


def write_android_monochrome_icon() -> None:
    xml = f"""<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="1024"
    android:viewportHeight="1024">
    <path
        android:pathData="{path_d_transformed()}"
        android:fillColor="@android:color/transparent"
        android:strokeColor="#FFFFFFFF"
        android:strokeWidth="{STROKE_WIDTH:.3f}"
        android:strokeLineCap="round"
        android:strokeLineJoin="round" />
</vector>
"""
    path = ROOT / "app" / "src" / "main" / "res" / "drawable" / "ic_launcher_monochrome.xml"
    ensure_dir(path.parent)
    path.write_text(xml, encoding="utf-8")


def generate_android() -> None:
    for density, size in ANDROID_DENSITIES.items():
        write_png(
            ROOT / "app" / "src" / "main" / "res" / f"mipmap-{density}" / "ic_launcher_foreground.png",
            draw_icon(size, include_background=False),
        )
    write_android_monochrome_icon()


def generate_ios() -> None:
    app_icon_dir = ROOT / "ios" / "Roana" / "Roana" / "Assets.xcassets" / "AppIcon.appiconset"
    ensure_dir(app_icon_dir)

    images = []
    for idiom, point_size, scale, pixels in IOS_ICONS:
        filename = f"AppIcon-{point_size.replace('x', 'x')}@{scale}.png"
        if idiom == "ios-marketing":
            filename = "AppIcon-1024.png"
        write_png(app_icon_dir / filename, draw_icon(pixels, include_background=True))
        images.append({
            "filename": filename,
            "idiom": idiom,
            "scale": scale,
            "size": point_size,
        })

    contents = {
        "images": images,
        "info": {
            "author": "xcode",
            "version": 1,
        },
    }
    (app_icon_dir / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    write_source_svg()
    generate_android()
    generate_ios()


if __name__ == "__main__":
    main()
