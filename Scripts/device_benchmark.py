"""Control MeetMind's isolated benchmark lab over USB; never pull meeting content.

Requires the ignored build/device-tools virtualenv with pymobiledevice3 installed.
Run this script with that virtualenv's Python. --status is read-only. --run restarts
MeetMind in the lab, downloads the selected public model if necessary, and runs a
synthetic smoke fixture. It does not establish real-meeting quality.
"""
import argparse
import json
import queue
import subprocess
import sys
import threading
import time

BUNDLE = "com.meetmind.app.JK2M3K5ACG"
MODELS = ["whisper-small", "whisper-large", "diarization", "qwen-1.7b", "qwen-4b"]


def command(*args):
    return [sys.executable, "-m", "pymobiledevice3", *args]


def query(*args):
    result = subprocess.run(command(*args), capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60)
    if result.returncode:
        raise RuntimeError("Device query failed; unlock/trust the iPhone and verify USB developer access.")
    return json.loads(result.stdout)


def status():
    devices = query("usbmux", "list")
    print(json.dumps({"connected": [{"model": d.get("ProductType"), "iOS": d.get("ProductVersion"),
                                    "transport": d.get("ConnectionType")} for d in devices]}, indent=2), flush=True)
    apps = query("apps", "query", BUNDLE)
    app = apps.get(BUNDLE, {})
    print(json.dumps({"MeetMind": {"version": app.get("CFBundleShortVersionString"),
                                  "build": app.get("CFBundleVersion")}}, indent=2), flush=True)
    metrics = query("developer", "dvt", "sysmon", "process", "single", "--userspace",
                    "--filter", "name=MeetMind", "--key", "pid", "--key", "physFootprint", "--key", "memResidentSize")
    print(json.dumps({"process_snapshots": metrics}, indent=2), flush=True)


def run(model, timeout):
    app = query("apps", "query", BUNDLE).get(BUNDLE, {})
    if int(app.get("CFBundleVersion", "0")) < 4:
        raise RuntimeError("Install the benchmark-enabled build 4 before running engine tests. The installed build is older.")
    if model == "qwen-4b" and int(app.get("CFBundleVersion", "0")) < 6:
        raise RuntimeError("Install build 6 before testing 4B: earlier builds lack the memory admission guard.")
    args = f"{BUNDLE} --offline-benchmark --benchmark-model={model}"
    print(f"Starting {model} synthetic smoke test; not a quality qualification.", flush=True)
    watch(args, timeout)


def storage_check(timeout):
    app = query("apps", "query", BUNDLE).get(BUNDLE, {})
    if int(app.get("CFBundleVersion", "0")) < 6:
        raise RuntimeError("Install build 6 before running the content-free storage diagnostic.")
    watch(f"{BUNDLE} --diagnose-storage", timeout, storage=True)
    time.sleep(5)
    snapshots = query("developer", "dvt", "sysmon", "process", "single", "--userspace",
                      "--filter", "name=MeetMind", "--key", "pid", "--key", "physFootprint")
    if not snapshots:
        raise RuntimeError("MeetMind exited after opening its production store.")
    print("Production store opened; MeetMind remained running after 5 seconds.", flush=True)


def watch(args, timeout, storage=False):
    marker = "MEETMIND_STORAGE_READY " if storage else "MEETMIND_BENCHMARK "
    process = subprocess.Popen(command("developer", "dvt", "launch", args, "--userspace", "--stream"),
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, encoding="utf-8", errors="replace", bufsize=1)
    lines = queue.Queue()
    def read():
        for line in process.stdout:
            # Libraries may print internal diagnostics; never persist/forward
            # arbitrary stdout. Only our own content-free markers are emitted.
            if marker in line:
                lines.put(line[line.index(marker):].strip())
        lines.put(None)
    threading.Thread(target=read, daemon=True).start()
    deadline = time.monotonic() + timeout
    try:
        while time.monotonic() < deadline:
            try:
                line = lines.get(timeout=1)
            except queue.Empty:
                continue
            if line is None:
                raise RuntimeError("Device stream ended before a benchmark result. Inspect the on-device status.")
            print(line, flush=True)
            if storage:
                if line == "MEETMIND_STORAGE_READY true":
                    return
                raise RuntimeError("The production meeting store did not open. Inspect the recovery message on the iPhone.")
            if "MEETMIND_BENCHMARK completed " in line:
                return
            if "MEETMIND_BENCHMARK rejected_memory" in line:
                raise RuntimeError("Model rejected before allocation by the safe memory budget.")
            if "MEETMIND_BENCHMARK failed" in line or "MEETMIND_BENCHMARK cancelled" in line:
                raise RuntimeError("Benchmark did not complete; inspect its status on the iPhone.")
        raise RuntimeError("Timed out waiting for the benchmark. The app may still be running on the iPhone.")
    finally:
        # Stop only the host-side stream, not the iPhone application or its data.
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument("--status", action="store_true")
    choice.add_argument("--run", choices=MODELS)
    choice.add_argument("--storage-check", action="store_true")
    parser.add_argument("--timeout", type=int, default=1800)
    args = parser.parse_args()
    try:
        if args.status:
            status()
        elif args.storage_check:
            storage_check(args.timeout)
        else:
            run(args.run, args.timeout)
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
