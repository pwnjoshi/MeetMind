"""Download the offline models named in the manifest and install them into a simulator app container.

  python3 -X utf8 Scripts/ci_install_models.py --cache-dir build/ci-models --udid <simulator udid>
  python3 -X utf8 Scripts/ci_install_models.py --cache-dir build/ci-models --download-only

Mirrors OfflineEngineKit's OfflineModelStore so the app sees the models as ready:
  * URLs, sizes and SHA-256 values come from OfflineEngineKit/.../Resources/models.json
    (only https://huggingface.co is accepted, like the app's downloader).
  * Folder: <Application Support>/OfflineIntelligence/Models/<id>-<first 12 hex of the profile digest>
    where the digest is SHA-256 of the profile encoded by Swift's JSONEncoder with .sortedKeys
    (compact, "/" escaped as "\\/"). The app's readiness check recomputes it, so it must match.
  * Each folder holds every asset at its manifest path plus verified.json (the profile as JSON).

--cache-dir keeps the same layout (<id>-<digest>/...) and is what actions/cache should persist.
Everything is idempotent: complete, size-checked cache folders are not downloaded again, partial
files resume with HTTP Range, and an installed folder that already matches is left alone.
Default models are whisper-large, diarization and qwen-1.7b. whisper-small is not needed.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_MANIFEST = os.path.join(HERE, "..", "OfflineEngineKit", "Sources", "OfflineEngineKit", "Resources", "models.json")
DEFAULT_IDS = ("whisper-large", "diarization", "qwen-1.7b")
DEFAULT_BUNDLE = "com.meetmind.app"
SUPPORT_SUBPATH = ("Library", "Application Support", "OfflineIntelligence", "Models")
CHUNK = 1024 * 1024


def load_manifest(path=DEFAULT_MANIFEST):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def select_profiles(manifest, ids):
    by_id = {profile["id"]: profile for profile in manifest}
    missing = [i for i in ids if i not in by_id]
    if missing:
        raise KeyError("not in manifest: " + ", ".join(missing))
    return [by_id[i] for i in ids]


def swift_sorted_json(value):
    """Compact JSON with sorted keys and escaped slashes, as Foundation's JSONEncoder
    with .sortedKeys writes it. Only strings, integers, lists and dicts occur in a profile."""
    text = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return text.replace("/", "\\/")


def profile_digest(profile):
    coded = {
        "id": profile["id"],
        "name": profile["name"],
        "revision": profile["revision"],
        "files": [{"path": f["path"], "url": f["url"], "sha256": f["sha256"], "bytes": int(f["bytes"])}
                  for f in profile["files"]],
    }
    return hashlib.sha256(swift_sorted_json(coded).encode("utf-8")).hexdigest()


def folder_name(profile):
    """`<id>-<digest prefix>`, the folder OfflineModelStore uses."""
    return f"{profile['id']}-{profile_digest(profile)[:12]}"


def validate_asset(asset, allow_any_url=False):
    path = asset["path"]
    if not path or ".." in path or path.startswith("/") or "\\" in path:
        raise ValueError(f"invalid asset path: {path!r}")
    if not allow_any_url and not asset["url"].startswith("https://huggingface.co/"):
        raise ValueError(f"asset origin is not huggingface.co: {asset['url']}")


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while True:
            block = handle.read(CHUNK)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def folder_complete(folder, profile):
    """Cheap check: verified.json matches this profile and every asset exists at the right size."""
    marker = os.path.join(folder, "verified.json")
    try:
        with open(marker, "r", encoding="utf-8") as handle:
            installed = json.load(handle)
        if profile_digest(installed) != profile_digest(profile):
            return False
        for asset in profile["files"]:
            if os.path.getsize(os.path.join(folder, *asset["path"].split("/"))) != int(asset["bytes"]):
                return False
    except (OSError, ValueError, KeyError):
        return False
    return True


def download_asset(asset, target, retries=5, opener=urllib.request.build_opener(), log=print):
    """Fetch one asset to `target`, resuming `<target>.partial`, and verify size and SHA-256."""
    expected = asset["sha256"].lower()
    size = int(asset["bytes"])
    os.makedirs(os.path.dirname(target), exist_ok=True)
    if os.path.isfile(target) and os.path.getsize(target) == size and sha256_file(target) == expected:
        return "cached"
    partial = target + ".partial"
    last_error = None
    for attempt in range(1, retries + 1):
        have = os.path.getsize(partial) if os.path.isfile(partial) else 0
        if have > size:
            os.remove(partial)
            have = 0
        try:
            if have < size:
                request = urllib.request.Request(asset["url"], headers={"User-Agent": "manent-ci-models/1"})
                if have:
                    request.add_header("Range", f"bytes={have}-")
                with opener.open(request, timeout=120) as response:
                    status = getattr(response, "status", 200)
                    if have and status != 206:  # server ignored Range: start over
                        have = 0
                    with open(partial, "ab" if have else "wb") as out:
                        while True:
                            block = response.read(CHUNK)
                            if not block:
                                break
                            out.write(block)
            if os.path.getsize(partial) != size:
                raise OSError(f"size {os.path.getsize(partial)} != {size}")
            if sha256_file(partial) != expected:
                os.remove(partial)  # a corrupt partial must not be resumed again
                raise OSError("SHA-256 mismatch")
            os.replace(partial, target)
            return "downloaded"
        except (OSError, urllib.error.URLError) as error:
            last_error = error
            log(f"  retry {attempt}/{retries} for {asset['path']}: {type(error).__name__}: {error}")
            time.sleep(min(30, 2 ** attempt))
    raise RuntimeError(f"could not download {asset['path']}: {last_error}")


def write_marker(folder, profile):
    tmp = os.path.join(folder, "verified.json.tmp")
    with open(tmp, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(profile, handle, ensure_ascii=False)
    os.replace(tmp, os.path.join(folder, "verified.json"))


def ensure_cached(profile, cache_dir, workers=4, allow_any_url=False, opener=None, log=print):
    """Make <cache_dir>/<folder> complete and verified. Returns its path."""
    folder = os.path.join(cache_dir, folder_name(profile))
    if folder_complete(folder, profile):
        log(f"{profile['id']}: cache complete ({folder_name(profile)})")
        return folder
    log(f"{profile['id']}: downloading {len(profile['files'])} files, {sum(int(f['bytes']) for f in profile['files']) / 1e6:.0f} MB")
    for asset in profile["files"]:
        validate_asset(asset, allow_any_url)
    kwargs = {"opener": opener} if opener is not None else {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(download_asset, asset, os.path.join(folder, *asset["path"].split("/")), log=log, **kwargs):
                   asset for asset in profile["files"]}
        for future in concurrent.futures.as_completed(futures):
            future.result()  # raises the first failure
    write_marker(folder, profile)
    return folder


def link_or_copy(source, target):
    os.makedirs(os.path.dirname(target), exist_ok=True)
    if os.path.lexists(target):
        os.remove(target)
    try:
        os.link(source, target)  # same volume: instant and no extra disk
    except OSError:
        shutil.copyfile(source, target)


def install_into(models_root, profile, cache_folder, log=print):
    """Install a verified cache folder into the app's Models directory. Returns the folder path."""
    destination = os.path.join(models_root, folder_name(profile))
    if folder_complete(destination, profile):
        log(f"{profile['id']}: already installed")
        return destination
    staging = destination + ".download"
    if os.path.isdir(staging):
        shutil.rmtree(staging)
    os.makedirs(staging)
    for asset in profile["files"]:
        parts = asset["path"].split("/")
        link_or_copy(os.path.join(cache_folder, *parts), os.path.join(staging, *parts))
    write_marker(staging, profile)
    if os.path.isdir(destination):
        shutil.rmtree(destination)
    os.rename(staging, destination)
    log(f"{profile['id']}: installed as {folder_name(profile)}")
    return destination


def app_models_root(container):
    return os.path.join(container, *SUPPORT_SUBPATH)


def simulator_container(udid, bundle=DEFAULT_BUNDLE, attempts=5):
    """Data container path of the installed app (`xcrun simctl get_app_container`)."""
    last = ""
    for _ in range(attempts):
        result = subprocess.run(["xcrun", "simctl", "get_app_container", udid, bundle, "data"],
                                capture_output=True, text=True, encoding="utf-8")
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
        last = (result.stderr or result.stdout).strip()
        time.sleep(3)
    raise RuntimeError(f"no data container for {bundle} on {udid}: {last}. Install and launch the app once first.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cache-dir", required=True, help="download cache, same layout as the app's Models folder")
    target = parser.add_mutually_exclusive_group()
    target.add_argument("--udid", help="booted or shutdown simulator with the app installed")
    target.add_argument("--container", help="app data container path (for testing)")
    target.add_argument("--download-only", action="store_true")
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE)
    parser.add_argument("--manifest", default=DEFAULT_MANIFEST)
    parser.add_argument("--ids", default=",".join(DEFAULT_IDS))
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--verify-all", action="store_true", help="re-hash cached files even when the folder looks complete")
    args = parser.parse_args(argv)
    if not (args.udid or args.container or args.download_only):
        parser.error("give --udid, --container or --download-only")
    ids = [x.strip() for x in args.ids.split(",") if x.strip()]
    try:
        profiles = select_profiles(load_manifest(args.manifest), ids)
        os.makedirs(args.cache_dir, exist_ok=True)
        root = None
        if not args.download_only:
            container = args.container or simulator_container(args.udid, args.bundle_id)
            root = app_models_root(container)
            os.makedirs(root, exist_ok=True)
        for profile in profiles:
            if args.verify_all:
                stale = os.path.join(args.cache_dir, folder_name(profile), "verified.json")
                if os.path.isfile(stale):
                    os.remove(stale)
            cached = ensure_cached(profile, args.cache_dir, workers=args.workers)
            if root:
                install_into(root, profile, cached)
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print("models ready: " + ", ".join(folder_name(p) for p in profiles))
    return 0


if __name__ == "__main__":
    sys.exit(main())
