#!/usr/bin/env python3
"""
build.py - Build system for grandMA3 Lua plugins.

Reads manifest.json describing a plugin's components, validates the
referenced .lua files under src/, generates the plugin's XML header in
the format grandMA3 expects, and stages everything - plus any files under
media/ - into a dist/ folder that mirrors a real gma3_library:

    dist/
      gma3_library/
        datapools/plugins/<path>/<path>.xml, *.lua
        media/...                              (mirrors media/ 1:1)

Commands:
  - build    Assemble the above into dist/
  - install  Build, then copy it into your local gma3_library
  - package  Build, then zip it up for sharing / manual installation

Usage:
    python3 build.py build
    python3 build.py install
    python3 build.py install --dest /path/to/gma3_library
    python3 build.py install --usb --dest /Volumes/MY_USB_STICK
    python3 build.py package

Requires only the Python standard library (Python 3.8+).
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import sys
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

ROOT_DIR = Path(__file__).resolve().parent
SRC_DIR = ROOT_DIR / "src"
MEDIA_DIR = ROOT_DIR / "media"
DIST_DIR = ROOT_DIR / "dist"
MANIFEST_PATH = ROOT_DIR / "manifest.json"

GMA3_XML_DATA_VERSION = "2.4.2.2"


# ---------------------------------------------------------------------------
# Manifest handling
# ---------------------------------------------------------------------------

def load_manifest(path: Path = MANIFEST_PATH) -> dict:
    if not path.exists():
        sys.exit(
            f"Manifest not found: {path}\n"
            f"Create a manifest.json describing your plugin (see manifest.example.json)."
        )

    with path.open("r", encoding="utf-8") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError as e:
            sys.exit(f"manifest.json is not valid JSON: {e}")

    required = ["name", "author", "version", "path", "components"]
    missing = [key for key in required if key not in manifest]
    if missing:
        sys.exit(f"manifest.json is missing required field(s): {', '.join(missing)}")

    if not manifest["components"]:
        sys.exit("manifest.json must declare at least one component.")

    seen_names = set()
    for i, comp in enumerate(manifest["components"]):
        for key in ("name", "file"):
            if key not in comp:
                sys.exit(f"Component #{i} is missing required field '{key}'.")
        if comp["name"] in seen_names:
            sys.exit(f"Duplicate component name: '{comp['name']}'")
        seen_names.add(comp["name"])

    return manifest


def validate_components(manifest: dict) -> None:
    missing_files = []
    for comp in manifest["components"]:
        src_file = SRC_DIR / comp["file"]
        if not src_file.exists():
            missing_files.append(str(src_file))

    if missing_files:
        sys.exit(
            "The following component files are missing from src/:\n  "
            + "\n  ".join(missing_files)
        )


# ---------------------------------------------------------------------------
# XML generation
# ---------------------------------------------------------------------------

def generate_xml(manifest: dict) -> str:
    """
    Generate the plugin's .xml header in the format grandMA3 expects, e.g.:

    <?xml version="1.0" encoding="UTF-8"?>
    <GMA3 DataVersion="2.0.2.0">
      <UserPlugin Name="MyPlugin" Author="..." Version="..." Path="MyPlugin">
        <ComponentLua Name="Core" FileName="core.lua"/>
        <ComponentLua Name="ColorPicker" FileName="color_picker.lua"/>
      </UserPlugin>
    </GMA3>
    """
    name = escape(str(manifest["name"]))
    author = escape(str(manifest["author"]))
    version = escape(str(manifest["version"]))
    path = escape(str(manifest["path"]))

    component_lines = "\n".join(
        f'    <ComponentLua Name="{escape(c["name"])}" FileName="{escape(c["file"])}" Installed="Yes"/>'
        for c in manifest["components"]
    )

    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<GMA3 DataVersion="{GMA3_XML_DATA_VERSION}">\n'
        f'  <UserPlugin Name="{name}" Author="{author}" Version="{version}" Path="{path}">\n'
        f"{component_lines}\n"
        "  </UserPlugin>\n"
        "</GMA3>\n"
    )


# ---------------------------------------------------------------------------
# File helpers
# ---------------------------------------------------------------------------

def copy_tree_merge(src: Path, dest: Path) -> int:
    """
    Copy every file from src into dest, creating subfolders as needed,
    WITHOUT deleting anything already in dest that isn't part of src.
    Files that already exist at the destination are overwritten (so
    re-running install picks up updated icons). Returns the file count.
    """
    count = 0
    for file in src.rglob("*"):
        if file.is_file():
            rel = file.relative_to(src)
            target = dest / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(file, target)
            count += 1
    return count


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def build(manifest: dict) -> tuple[Path, Path]:
    """
    Assemble dist/gma3_library/... so it mirrors a real gma3_library:
      - datapools/plugins/<path>/  (XML + all .lua components)
      - media/                     (1:1 copy of the repo's media/ folder)

    Returns (plugin_dir, media_dir) - the two staged source trees used by
    install() and package().
    """
    validate_components(manifest)

    gma3_lib_dist = DIST_DIR / "gma3_library"

    # --- plugin (XML + components) ---
    plugin_dir = gma3_lib_dist / "datapools" / "plugins" / manifest["path"]
    if plugin_dir.exists():
        shutil.rmtree(plugin_dir)
    plugin_dir.mkdir(parents=True)

    xml_content = generate_xml(manifest)
    xml_path = plugin_dir / f'{manifest["path"]}.xml'
    xml_path.write_text(xml_content, encoding="utf-8")

    for comp in manifest["components"]:
        shutil.copy2(SRC_DIR / comp["file"], plugin_dir / comp["file"])

    print(f"Built '{manifest['name']}' v{manifest['version']} -> {plugin_dir}")
    print(
        f"  {1 + len(manifest['components'])} file(s) written "
        f"({xml_path.name} + {len(manifest['components'])} component(s))"
    )

    # --- media (appearance icons etc.) ---
    media_dir = gma3_lib_dist / "media"
    if media_dir.exists():
        shutil.rmtree(media_dir)
    media_dir.mkdir(parents=True)

    if MEDIA_DIR.exists():
        media_count = copy_tree_merge(MEDIA_DIR, media_dir)
        if media_count:
            print(f"Staged {media_count} media file(s) -> {media_dir}")
        else:
            print("media/ exists but is empty - nothing to stage.")
    else:
        print("No media/ folder found - skipping (this is fine if you have no custom icons yet).")

    return plugin_dir, media_dir


# ---------------------------------------------------------------------------
# Install (copy into the local gma3_library, or onto a USB drive)
# ---------------------------------------------------------------------------

def detect_gma3_library_root() -> Path | None:
    """
    Best-effort detection of the local gma3_library folder.
    Returns None if the platform/location can't be reliably determined,
    in which case the caller should ask the user for --dest explicitly.
    """
    system = platform.system()

    if system == "Windows":
        # Respect the real ProgramData location rather than hardcoding
        # "C:\\ProgramData", since it can differ (locale, custom setups, etc.)
        program_data = os.environ.get("ProgramData", r"C:\ProgramData")
        return Path(program_data) / "MALightingTechnology" / "gma3_library"

    if system == "Darwin":  # macOS
        return Path.home() / "MALightingTechnology" / "gma3_library"

    # grandMA3 (console OS / onPC) does not officially target Linux, so we
    # deliberately don't guess a path here - ask the user for --dest instead.
    return None


def install(
    manifest: dict,
    plugin_dir: Path,
    media_dir: Path,
    dest: Path | None,
    usb: bool,
) -> None:
    if usb:
        # Official USB stick / removable-drive layout expected by grandMA3's
        # Import dialog: <drive_root>/grandMA3/gma3_library/...
        if dest is None:
            sys.exit("--usb requires --dest <path to the root of your USB drive>")
        gma3_lib_root = dest / "grandMA3" / "gma3_library"
    elif dest is not None:
        # --dest points directly at a gma3_library folder
        gma3_lib_root = dest
    else:
        auto = detect_gma3_library_root()
        if auto is None:
            sys.exit(
                "Could not auto-detect your gma3_library path on this OS.\n"
                "Re-run with --dest pointing at your gma3_library folder, e.g.:\n"
                "  Windows : %ProgramData%\\MALightingTechnology\\gma3_library\n"
                "  macOS   : ~/MALightingTechnology/gma3_library"
            )
        gma3_lib_root = auto

    # Plugin folder is uniquely named (manifest["path"]) so it's safe to
    # fully replace on every install.
    plugins_target = gma3_lib_root / "datapools" / "plugins" / manifest["path"]
    plugins_target.parent.mkdir(parents=True, exist_ok=True)
    if plugins_target.exists():
        shutil.rmtree(plugins_target)
    shutil.copytree(plugin_dir, plugins_target)
    print(f"Installed plugin to: {plugins_target}")

    # media/ is a SHARED folder (other plugins/symbols may already have
    # files there) - merge into it rather than wiping it.
    media_target = gma3_lib_root / "media"
    media_target.mkdir(parents=True, exist_ok=True)
    media_count = copy_tree_merge(media_dir, media_target)
    if media_count:
        print(f"Merged {media_count} media file(s) into: {media_target}")
    else:
        print("No media files to install.")

    print_post_install_instructions(manifest, usb)


def print_post_install_instructions(manifest: dict, usb: bool) -> None:
    print("\nNext steps:")
    if usb:
        print("  1. Safely eject the USB drive and insert it into your console (or onPC machine).")
        print("  2. In grandMA3, open a Plugin Pool window on an empty pool object.")
        print("  3. Edit -> Import, select the USB drive, and choose:")
        print(f"       grandMA3/gma3_library/datapools/plugins/{manifest['path']}/{manifest['path']}.xml")
    else:
        print("  1. In grandMA3, go to the Show Creator page (or open a Plugin Pool window).")
        print("  2. Import the plugin - it should be auto-detected under:")
        print(f"       {manifest['path']}/{manifest['path']}.xml")
        print(
            "  3. If the plugin was already imported before, run 'ReloadAllPlugins' from "
            "the command line to pick up the new files instead of re-importing."
        )
    print(
        "  4. If you use custom icons, create/assign the Appearance(s) in the console "
        "pointing at the file(s) now under gma3_library/media - the build only stages "
        "the image files, the Appearance/Symbol pool assignment itself is still a console-side step."
    )
    print(
        f"\n  Once imported, run components with:  "
        f"Plugin '{manifest['name']}'.<component name or number>"
    )


# ---------------------------------------------------------------------------
# Package (zip dist folder for sharing / manual installation)
# ---------------------------------------------------------------------------

def package(manifest: dict) -> Path:
    """
    Zip the entire staged dist/gma3_library tree (plugin + media), so
    extracting the zip at the root of a drive or folder reproduces the
    gma3_library/... structure directly.
    """
    gma3_lib_dist = DIST_DIR / "gma3_library"
    zip_path = DIST_DIR / f'{manifest["path"]}-v{manifest["version"]}.zip'
    if zip_path.exists():
        zip_path.unlink()

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for file in gma3_lib_dist.rglob("*"):
            if file.is_file():
                zf.write(file, arcname=Path("gma3_library") / file.relative_to(gma3_lib_dist))

    print(f"Packaged: {zip_path}")
    print(
        "Extract this zip so its 'gma3_library' folder merges into your target "
        "gma3_library (or under grandMA3/ on a USB drive)."
    )
    return zip_path


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Build system for grandMA3 Lua plugins.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("build", help="Generate the plugin XML + stage components and media into dist/")

    install_parser = subparsers.add_parser("install", help="Build and install into a gma3_library")
    install_parser.add_argument(
        "--dest",
        type=Path,
        default=None,
        help="Path to a gma3_library folder, or a USB drive root when combined with --usb",
    )
    install_parser.add_argument(
        "--usb",
        action="store_true",
        help="Treat --dest as the root of a USB drive and use the official "
        "grandMA3/gma3_library/... layout expected by the console's Import dialog",
    )

    subparsers.add_parser("package", help="Build and zip the plugin + media for distribution")

    args = parser.parse_args()
    manifest = load_manifest()

    if args.command == "build":
        build(manifest)

    elif args.command == "install":
        plugin_dir, media_dir = build(manifest)
        install(manifest, plugin_dir, media_dir, args.dest, args.usb)

    elif args.command == "package":
        build(manifest)
        package(manifest)


if __name__ == "__main__":
    main()