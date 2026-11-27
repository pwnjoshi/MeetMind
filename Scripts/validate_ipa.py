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
ALLOWED_BACKGROUND_MODES = {"audio", "processing"}
REQUIRED_API_CATEGORIES = {
    "NSPrivacyAccessedAPICategoryUserDefaults",
    "NSPrivacyAccessedAPICategoryFileTimestamp",
    "NSPrivacyAccessedAPICategoryDiskSpace",
    "NSPrivacyAccessedAPICategorySystemBootTime",
}


def validate_release_metadata(data, manifest_bytes):
    """Fail when App Store required compliance metadata is missing or wrong."""
    if data.get("ITSAppUsesNonExemptEncryption") is not False:
        raise ValueError("Info.plist must set ITSAppUsesNonExemptEncryption to false")
    if data.get("CFBundleDisplayName") != "Manent":
        raise ValueError("CFBundleDisplayName must be Manent")
    if not str(data.get("LSApplicationCategoryType", "")).startswith("public.app-category."):
        raise ValueError("Missing LSApplicationCategoryType")
    extra = set(data.get("UIBackgroundModes", [])) - ALLOWED_BACKGROUND_MODES
    if extra:
        raise ValueError("Unexpected UIBackgroundModes: " + ", ".join(sorted(extra)))
    if manifest_bytes is None:
        raise ValueError("PrivacyInfo.xcprivacy is missing from the app bundle")
    manifest = plistlib.loads(manifest_bytes)
    if manifest.get("NSPrivacyTracking") is not False:
        raise ValueError("Privacy manifest must declare NSPrivacyTracking false")
    if manifest.get("NSPrivacyTrackingDomains"):
        raise ValueError("Privacy manifest must not list tracking domains")
    if manifest.get("NSPrivacyCollectedDataTypes") != []:
        raise ValueError("Privacy manifest must declare no collected data types")
    declared = {entry.get("NSPrivacyAccessedAPIType"): entry.get("NSPrivacyAccessedAPITypeReasons")
                for entry in manifest.get("NSPrivacyAccessedAPITypes", [])}
    for category in sorted(REQUIRED_API_CATEGORIES):
        if not declared.get(category):
            raise ValueError(f"Privacy manifest lacks reason codes for {category}")


def validate(path, expected_commit=None, expected_bundle_id=None, require_signing=False):
    path = Path(path)
    if path.suffix.lower() == ".ipa":
        with zipfile.ZipFile(path) as archive:
            names = set(archive.namelist())
            matches = [name for name in names
                       if name.startswith("Payload/") and name.count("/") == 2
                       and name.endswith(".app/Info.plist")]
            if len(matches) != 1:
                raise ValueError("Expected exactly one app Info.plist in Payload")
            data = plistlib.loads(archive.read(matches[0]))
            app_prefix = matches[0].removesuffix("Info.plist")
            manifest_name = app_prefix + "PrivacyInfo.xcprivacy"
            manifest_bytes = archive.read(manifest_name) if manifest_name in names else None
            if require_signing:
                required_signing_files = (
                    app_prefix + "embedded.mobileprovision",
                    app_prefix + "_CodeSignature/CodeResources",
                )
                missing_signing = [name for name in required_signing_files
                                   if name not in names or archive.getinfo(name).file_size == 0]
                if missing_signing:
                    raise ValueError("IPA lacks App Store signing material: " + ", ".join(missing_signing))
    else:
        with path.open("rb") as source:
            data = plistlib.load(source)
        manifest_path = path.with_name("PrivacyInfo.xcprivacy")
        manifest_bytes = manifest_path.read_bytes() if manifest_path.is_file() else None
    missing = [key for key in REQUIRED if not str(data.get(key, "")).strip()]
    if missing:
        raise ValueError("Missing privacy declarations: " + ", ".join(missing))
    if expected_bundle_id and data.get("CFBundleIdentifier") != expected_bundle_id:
        raise ValueError(
            f"CFBundleIdentifier is {data.get('CFBundleIdentifier')!r}, expected {expected_bundle_id!r}"
        )
    if expected_commit and data.get("ManentBuildCommit") != expected_commit:
        raise ValueError(
            f"ManentBuildCommit is {data.get('ManentBuildCommit')!r}, expected {expected_commit!r}"
        )
    validate_release_metadata(data, manifest_bytes)
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
    parser.add_argument("--expected-commit", help="require this ManentBuildCommit value")
    parser.add_argument("--expected-bundle-id", help="require this CFBundleIdentifier value")
    parser.add_argument(
        "--require-signing",
        action="store_true",
        help="require an embedded provisioning profile and CodeResources in an IPA",
    )
    args = parser.parse_args()
    try:
        validate(
            args.path,
            expected_commit=args.expected_commit,
            expected_bundle_id=args.expected_bundle_id,
            require_signing=args.require_signing,
        )
    except (ValueError, OSError, plistlib.InvalidFileException, zipfile.BadZipFile) as error:
        parser.exit(1, f"FAIL: {error}\n")
    print("PASS: privacy declarations, privacy manifest, encryption flag, background modes, and image assets")
