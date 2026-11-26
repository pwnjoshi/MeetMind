"""Run the golden-set evaluation on a USB-connected iPhone and score it.

Run with the build/device-tools virtualenv's Python (it has pymobiledevice3):

  build/device-tools/Scripts/python.exe Scripts/device_eval.py --golden golden

Steps: push each golden folder (audio + labels.json) into the app's Documents/Evaluation over
HouseArrest, launch MeetMind with --offline-evaluation (the app analyses only those folders, in
an isolated checkpoint folder, and never touches saved meetings), wait for the MEETMIND_EVAL
completion line, pull result.json for each meeting, then call Scripts/eval_score.py. Use --capture-only for unlabelled local recordings.

Golden audio is private. --clean-device removes Documents/Evaluation from the phone afterwards.
The pulled results contain transcripts, so build/eval is git-ignored territory: do not commit it.
"""
import argparse
import asyncio
import inspect
import json
import os
import queue
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from device_benchmark import BUNDLE, command, query  # noqa: E402
import eval_score  # noqa: E402

AUDIO_EXTENSIONS = (".m4a", ".wav", ".caf", ".mp3", ".aac", ".mp4")
REMOTE_ROOT = "/Documents/Evaluation"
MARKER = "MEETMIND_EVAL "


def golden_folders(golden, only=None):
    """[(id, folder, audio_path)] for every folder with labels.json and an audio.* file."""
    found = []
    for name in sorted(os.listdir(golden)):
        folder = os.path.join(golden, name)
        if not os.path.isfile(os.path.join(folder, "labels.json")):
            continue
        if only and name not in only:
            continue
        audio = next((os.path.join(folder, "audio" + ext) for ext in AUDIO_EXTENSIONS
                      if os.path.isfile(os.path.join(folder, "audio" + ext))), None)
        if audio is None:
            print(f"skip {name}: no audio.m4a/wav next to labels.json", file=sys.stderr)
            continue
        found.append((name, folder, audio))
    return found


async def settle(value):
    return await value if inspect.isawaitable(value) else value


async def open_container():
    """Full app container over HouseArrest, as build/pull_store.py does."""
    from pymobiledevice3.lockdown import create_using_usbmux
    from pymobiledevice3.services.house_arrest import HouseArrestService
    lockdown = await create_using_usbmux()
    return await HouseArrestService.create(lockdown, BUNDLE, documents_only=False)


async def push(folders, transcripts):
    afc = await open_container()
    async with afc:
        await settle(afc.makedirs(REMOTE_ROOT))
        for name, folder, audio in folders:
            remote = f"{REMOTE_ROOT}/{name}"
            await settle(afc.makedirs(remote))
            try:  # a stale result must never be mistaken for this run
                await settle(afc.rm(f"{remote}/result.json", force=True))
            except Exception:
                pass
            if name in transcripts:
                await settle(afc.set_file_contents(f"{remote}/transcript.json", transcripts[name]))
            for path in (audio, os.path.join(folder, "labels.json")):
                with open(path, "rb") as handle:
                    data = handle.read()
                await settle(afc.set_file_contents(f"{remote}/{os.path.basename(path)}", data))
                print(f"pushed {name}/{os.path.basename(path)} ({len(data) // 1024} KiB)", flush=True)


async def pull(names, destination):
    """Copy result.json of each meeting into destination/<id>/. Returns the ids that had one."""
    got = []
    afc = await open_container()
    async with afc:
        for name in names:
            try:
                data = await settle(afc.get_file_contents(f"{REMOTE_ROOT}/{name}/result.json"))
            except Exception as error:
                print(f"no result for {name}: {type(error).__name__}", file=sys.stderr)
                continue
            target = os.path.join(destination, name)
            os.makedirs(target, exist_ok=True)
            with open(os.path.join(target, "result.json"), "wb") as handle:
                handle.write(data)
            got.append(name)
    return got


async def clean_device():
    afc = await open_container()
    async with afc:
        await settle(afc.rm(REMOTE_ROOT, force=True))
    print("removed Documents/Evaluation from the device", flush=True)


def launch_and_wait(only, language, timeout, model, reuse_transcript):
    """Launch the evaluation and stream MEETMIND_EVAL lines. Returns (ok, commit)."""
    args = f"{BUNDLE} --offline-evaluation --eval-model={model}"
    if reuse_transcript:
        args += " --eval-reuse-transcript"
    if only:
        args += " --eval-only=" + ",".join(only)
    if language:
        args += f" --eval-language={language}"
    process = subprocess.Popen(command("developer", "dvt", "launch", args, "--userspace", "--stream"),
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                               encoding="utf-8", errors="replace", bufsize=1)
    lines = queue.Queue()

    def read():
        for line in process.stdout:
            if MARKER in line:  # only our own content-free markers are kept
                lines.put(line[line.index(MARKER):].strip())
        lines.put(None)

    threading.Thread(target=read, daemon=True).start()
    deadline = time.monotonic() + timeout
    commit = None
    try:
        while time.monotonic() < deadline:
            try:
                line = lines.get(timeout=1)
            except queue.Empty:
                continue
            if line is None:
                raise RuntimeError("Device stream ended before the evaluation finished. Check the iPhone.")
            print(line, flush=True)
            for part in line.split():
                if part.startswith("commit="):
                    commit = part[len("commit="):]
            if line.startswith(MARKER + "completed "):
                return " failed=0" in line, commit
            if line.startswith(MARKER + "cancelled"):
                raise RuntimeError("Evaluation was cancelled (app left the foreground). Keep MeetMind open and rerun.")
        raise RuntimeError("Timed out waiting for the evaluation. The app may still be running on the iPhone.")
    finally:
        if process.poll() is None:  # stop only the host-side stream, not the app or its data
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--golden", required=True, help="folder of golden meetings")
    parser.add_argument("--only", help="comma-separated meeting ids")
    parser.add_argument("--language", help="force the transcription language code, e.g. hi (default: automatic)")
    parser.add_argument("--model", choices=("qwen-1.7b", "qwen-3.5-2b"), default="qwen-1.7b")
    parser.add_argument("--transcript-from", help="prior result root with <meeting>/result.json for minutes-only replay")
    parser.add_argument("--timeout", type=int, default=7200, help="seconds to wait for the run (default 7200)")
    parser.add_argument("--out", default=os.path.join("build", "eval"))
    parser.add_argument("--skip-push", action="store_true", help="files are already on the device")
    parser.add_argument("--skip-run", action="store_true", help="only pull results and score")
    parser.add_argument("--clean-device", action="store_true", help="delete Documents/Evaluation afterwards")
    parser.add_argument("--capture-only", action="store_true",
                        help="save replay results without scoring recordings against reference labels")
    parser.add_argument("--task-source", choices=("tasks", "rawTasks"), default="tasks")
    args = parser.parse_args(argv)
    only = [x.strip() for x in args.only.split(",") if x.strip()] if args.only else None
    folders = golden_folders(args.golden, only)
    if not folders:
        print("No golden folders with labels.json and audio found.", file=sys.stderr)
        return 1
    names = [name for name, _, _ in folders]
    try:
        app = query("apps", "query", BUNDLE).get(BUNDLE, {})
        if not app:
            raise RuntimeError("MeetMind is not installed on the connected iPhone.")
        print(f"MeetMind {app.get('CFBundleShortVersionString')} build {app.get('CFBundleVersion')}", flush=True)
        if not args.skip_push and not args.skip_run:
            transcripts = {}
            if args.transcript_from:
                for name in names:
                    with open(os.path.join(args.transcript_from, name, "result.json"), encoding="utf-8") as source:
                        turns = json.load(source).get("turns")
                    if not isinstance(turns, list) or not turns:
                        raise ValueError(f"No saved transcript turns for {name}.")
                    transcripts[name] = json.dumps(turns, ensure_ascii=False).encode("utf-8")
            asyncio.run(push(folders, transcripts))
        ok, commit = True, None
        if not args.skip_run:
            ok, commit = launch_and_wait(names, args.language, args.timeout, args.model, bool(args.transcript_from))
        staging = os.path.join(args.out, "runs", commit or time.strftime("%Y%m%d-%H%M%S"))
        if args.transcript_from:
            staging = os.path.join(staging, args.model)
        got = asyncio.run(pull(names, staging))
        if args.clean_device:
            asyncio.run(clean_device())
        if not got:
            print("No results were produced.", file=sys.stderr)
            return 1
        if args.capture_only:
            print(f"Captured {len(got)}/{len(names)} replay results in {staging}.")
            return 0 if ok and len(got) == len(names) else 2
        if not ok:
            print("Some meetings failed; scoring the ones that finished.", file=sys.stderr)
        code = eval_score.main(["--golden", args.golden, "--results", staging, "--out", args.out,
                                "--task-source", args.task_source] + (["--commit", commit] if commit else []))
        return code if ok else (code or 2)
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
