#!/usr/bin/env python3
"""Check source/built Info.plist or an IPA's actual bundled privacy declarations."""
import argparse
import plistlib
import zipfile
import json
from pathlib import Path

REQUIRED = (
    "NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription",
    "NSCalendarsFullAccessUsageDescription", "NSRemindersFullAccessUsageDescription",
    "NSCameraUsageDescription", "NSPhotoLibraryUsageDescription",
)


def validate(path):
    path = Path(path)
    if path.suffix.lower() == ".ipa":
        with zipfile.ZipFile(path) as archive:
            matches = [name for name in archive.namelist()
                       if name.startswith("Payload/") and name.count("/") == 2
                       and name.endswith(".app/Info.plist")]
            if len(matches) != 1:
                raise ValueError("Expected exactly one app Info.plist in Payload")
            data = plistlib.loads(archive.read(matches[0]))
    else:
        with path.open("rb") as source:
            data = plistlib.load(source)
    missing = [key for key in REQUIRED if not str(data.get(key, "")).strip()]
    if missing:
        raise ValueError("Missing privacy declarations: " + ", ".join(missing))
    if "processing" in data.get("UIBackgroundModes", []) and not data.get("BGTaskSchedulerPermittedIdentifiers"):
        raise ValueError("Background processing declared without scheduler identifiers")
    if path.suffix.lower() == ".ipa":
        with zipfile.ZipFile(path) as archive:
            catalog = matches[0].replace("Info.plist", "Assets.car")
            if catalog not in archive.namelist() or archive.getinfo(catalog).file_size == 0:
                raise ValueError("Compiled asset catalog is missing or empty")
    elif path.parent.suffix == ".app":
        catalog = path.parent / "Assets.car"
        if not catalog.is_file() or catalog.stat().st_size == 0:
            raise ValueError("Compiled asset catalog is missing or empty")
    else:
        for manifest in (path.parent / "Assets.xcassets").glob("*.imageset/Contents.json"):
            for entry in json.loads(manifest.read_text(encoding="utf-8")).get("images", []):
                if "filename" in entry:
                    asset = manifest.parent / entry["filename"]
                    if not asset.is_file() or asset.stat().st_size == 0:
                        raise ValueError(f"Missing or empty image asset: {asset}")
    return data


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path")
    args = parser.parse_args()
    try:
        validate(args.path)
    except (ValueError, OSError, plistlib.InvalidFileException, zipfile.BadZipFile) as error:
        parser.exit(1, f"FAIL: {error}\n")
    print("PASS: privacy declarations, background modes, and image assets")
