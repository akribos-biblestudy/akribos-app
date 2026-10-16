#!/usr/bin/env python3
"""Export existing Akribos branding and original SVG artwork for Google Play."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
from xml.sax.saxutils import escape


def run(*args, env=None):
    return subprocess.check_output(args, text=True, env=env).strip()


def png_info(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Not a PNG: {path}")
    width, height, depth, color = struct.unpack(">IIBB", data[16:26])
    return {
        "width": width,
        "height": height,
        "bitDepth": depth,
        "colorType": color,
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def main():
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=here / "../../..")
    parser.add_argument("--output", type=Path, default=here)
    args = parser.parse_args()
    root, out = args.repo_root.resolve(), args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    logo = root / "assets/brand/icon.png"
    wordmark = root / "assets/brand/wordmark.png"
    fonts = root / "assets/fonts"
    source = here / "feature-graphic.svg"
    for path in (logo, wordmark, source, fonts / "akribos-text-semibold.ttf"):
        if not path.is_file():
            raise FileNotFoundError(path)

    # Retain the existing logo's shape and color; only crop transparent padding,
    # downsample, and place it on an opaque full-square brand-paper background.
    run(
        "magick", str(logo), "-trim", "+repage", "-filter", "Lanczos",
        "-resize", "384x384", "-background", "#fffefa", "-gravity", "center",
        "-extent", "512x512", "-alpha", "remove", "-alpha", "on",
        "-colorspace", "sRGB", "-depth", "8", "-strip",
        "-define", "png:color-type=6", "-define", "png:exclude-chunk=date,time",
        "PNG32:" + str(out / "icon.png"),
    )

    with tempfile.TemporaryDirectory(prefix="akribos-play-graphics-") as temporary:
        temp = Path(temporary)
        fontconfig = temp / "fonts.conf"
        fontconfig.write_text(
            '<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">'
            '<fontconfig><dir>' + escape(str(fonts)) + '</dir><cachedir>'
            + escape(str(temp / "font-cache")) + '</cachedir></fontconfig>',
            encoding="utf-8",
        )
        env = {**os.environ, "FONTCONFIG_FILE": str(fontconfig)}
        selected = run("fc-match", "-f", "%{family}", "Akribos Text", env=env)
        if "Akribos Text" not in selected:
            raise ValueError("Bundled Akribos Text font could not be selected")
        svg = source.read_text(encoding="utf-8").replace(
            "../../../assets/brand/wordmark.png",
            "data:image/png;base64," + base64.b64encode(wordmark.read_bytes()).decode(),
        )
        drawing = temp / "feature-graphic.svg"
        drawing.write_text(svg, encoding="utf-8")
        rendered = temp / "feature-graphic.png"
        run("rsvg-convert", "--output", str(rendered), str(drawing), env=env)
        run(
            "magick", str(rendered), "-alpha", "off", "-colorspace", "sRGB",
            "-depth", "8", "-strip", "-define", "png:color-type=2",
            "-define", "png:exclude-chunk=date,time", "PNG24:" + str(out / "feature-graphic.png"),
        )

    outputs = {name: png_info(out / name) for name in ("icon.png", "feature-graphic.png")}
    icon, feature = outputs.values()
    assert (icon["width"], icon["height"], icon["bitDepth"], icon["colorType"]) == (512, 512, 8, 6)
    assert icon["bytes"] <= 1024 * 1024
    assert (feature["width"], feature["height"], feature["bitDepth"], feature["colorType"]) == (1024, 500, 8, 2)
    manifest = {
        "sources": {
            str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (logo, wordmark, fonts / "akribos-text-regular.ttf", fonts / "akribos-text-semibold.ttf")
        },
        "artworkSourceSha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "renderer": {
            "imagemagick": run("magick", "-version").splitlines()[0],
            "librsvg": run("rsvg-convert", "--version"),
        },
        "outputs": outputs,
    }
    (out / "build-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(outputs, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
