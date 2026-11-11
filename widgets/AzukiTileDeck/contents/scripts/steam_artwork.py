#!/usr/bin/env python3
"""Read-only Steam artwork discovery. No network, credentials or subprocesses."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys

from artwork_manager import ArtworkError, read_image

APP_ID = re.compile(r"[0-9]{1,20}\Z")
MAX_RESULTS = 12
# Only named artwork assets; no recursive traversal of Steam's library.
VARIANTS = (
    ("library_hero", "Fondo horizontal · Hero"),
    ("header", "Cabecera · Header"),
    ("library_600x900", "Portada vertical · 600×900"),
)
EXTENSIONS = ("jpg", "jpeg", "png", "webp")
# Aliases used by different Steam library-cache layouts.
ALIASES = {
    "library_hero": ("library_hero",),
    "header": ("header", "library_header"),
    "library_600x900": ("library_600x900", "library_capsule"),
}
HASH_DIR = re.compile(r"[0-9a-fA-F]{40}\Z")
MAX_HASH_DIRS = 256
MAX_CANDIDATES = 8192


def validate_app_id(value):
    value = str(value)
    if not APP_ID.fullmatch(value) or int(value) == 0:
        raise ArtworkError("El AppID de Steam debe ser un número válido.")
    return value


def discover_roots(home=None):
    home = Path(home) if home is not None else Path.home()
    candidates = (
        home / ".steam/debian-installation/appcache/librarycache",
        home / ".local/share/Steam/appcache/librarycache",
        home / ".steam/root/appcache/librarycache",
        home / ".steam/steam/appcache/librarycache",
        home / ".var/app/com.valvesoftware.Steam/data/Steam/appcache/librarycache",
        home / ".var/app/com.valvesoftware.Steam/.local/share/Steam/appcache/librarycache",
    )
    result, seen = [], set()
    for candidate in candidates:
        try:
            root = candidate.resolve(strict=True)
            if root.is_dir() and root not in seen:
                seen.add(root)
                result.append(root)
        except (OSError, RuntimeError):
            continue
    return result


def hash_directories(root, app_id):
    """Find only one-level, 40-hex cache directories for this AppID."""
    app_dir = root / app_id
    if app_dir.is_symlink() or not app_dir.is_dir():
        return []
    try:
        if app_dir.resolve(strict=True) != app_dir:
            return []
        names = sorted(app_dir.iterdir(), key=lambda p: p.name)
    except (OSError, RuntimeError):
        return []
    result = []
    for child in names:
        if not HASH_DIR.fullmatch(child.name) or child.is_symlink():
            continue
        try:
            if child.is_dir() and child.resolve(strict=True) == child:
                result.append(child)
        except (OSError, RuntimeError):
            continue
        if len(result) >= MAX_HASH_DIRS:
            break
    return result


def candidate_paths(root, app_id):
    """Yield known names in flat, direct and one-level hashed layouts.

    The direct/legacy variants remain supported. Hash directories are
    discovered only beneath the requested AppID; no recursive tree walk.
    """
    folders = [root / app_id] + hash_directories(root, app_id)
    for stem, label in VARIANTS:
        for folder in folders:
            for alias in ALIASES[stem]:
                for suffix in ("", "@2x"):
                    for ext in EXTENSIONS:
                        name = alias + suffix + "." + ext
                        yield folder / name, stem, label
        # Original flat cache format, including known aliases.
        for alias in ALIASES[stem]:
            for suffix in ("", "@2x"):
                for ext in EXTENSIONS:
                    yield root / (app_id + "_" + alias + suffix + "." + ext), stem, label


def scan(app_id, roots=None):
    app_id = validate_app_id(app_id)
    roots = discover_roots() if roots is None else roots
    images, seen_paths, seen_hashes = [], set(), set()
    checked, skipped, candidates_checked = 0, 0, 0
    for candidate_root in roots[:12]:
        try:
            root = Path(candidate_root).resolve(strict=True)
            if not root.is_dir():
                continue
        except (OSError, RuntimeError):
            continue
        checked += 1
        app_dir = root / app_id
        # A game directory may not redirect discovery into another game.
        game_dir_safe = not app_dir.is_symlink()
        if game_dir_safe:
            try:
                game_dir_safe = (not app_dir.exists()
                                 or app_dir.resolve(strict=True) == app_dir)
            except (OSError, RuntimeError):
                game_dir_safe = False
        for candidate, variant, label in candidate_paths(root, app_id):
            candidates_checked += 1
            if candidates_checked > MAX_CANDIDATES:
                break
            try:
                # Flat files remain under the cache root. Files in a game
                # folder must stay inside the requested AppID directory.
                is_flat = candidate.parent == root
                if not is_flat and not game_dir_safe:
                    continue
                path = candidate.resolve(strict=True)
                scope = root if is_flat else app_dir
                if not path.is_relative_to(scope) or path in seen_paths or not path.is_file():
                    continue
                seen_paths.add(path)
                data, kind, width, height = read_image(path)
                digest = hashlib.sha256(data).hexdigest()
                if digest in seen_hashes:
                    continue
                seen_hashes.add(digest)
                images.append({
                    "fileUrl": path.as_uri(), "name": path.name,
                    "variant": variant, "label": label,
                    "format": kind.upper(), "width": width, "height": height,
                    "bytes": len(data), "sha256": digest,
                })
            except FileNotFoundError:
                continue
            except (ArtworkError, OSError, RuntimeError, ValueError):
                skipped += 1
                continue
            if len(images) >= MAX_RESULTS:
                break
        if len(images) >= MAX_RESULTS or candidates_checked >= MAX_CANDIDATES:
            break
    return {
        "appId": app_id, "images": images,
        "rootsChecked": checked, "skipped": skipped,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--request-id", default="0")
    parser.add_argument("--cache-dir", action="append", type=Path,
                        help="Optional local cache root for diagnostics, not used by the GUI.")
    args = parser.parse_args(argv)
    try:
        data = scan(args.app_id, args.cache_dir)
        payload = {"ok": True, "requestId": args.request_id, "data": data}
        status = 0
    except (ArtworkError, OSError, ValueError) as exc:
        payload = {"ok": False, "requestId": args.request_id,
                   "message": str(exc)}
        status = 1
    print(json.dumps(payload, ensure_ascii=False))
    return status


if __name__ == "__main__":
    sys.exit(main())
