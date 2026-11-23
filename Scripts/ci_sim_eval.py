"""Run the offline evaluation inside an iOS Simulator (CI) and score it.

  python3 -X utf8 Scripts/ci_sim_eval.py preflight --udid U
  python3 -X utf8 Scripts/ci_sim_eval.py run --udid U --golden build/eval-golden --commit abc1234

preflight launches the installed app once with `--offline-evaluation --eval-only=__preflight__`,
which only prints the environment and the state of the three required models (MEETMIND_EVAL env/model
lines), then fails fast when a model is not "ready" or the simulator reports no available memory.

run copies the golden folders into the app's Documents/Evaluation, launches
`--offline-evaluation` with stdout going to a file, follows the MEETMIND_EVAL lines until
`completed`, collects every result.json into build/eval/runs/<commit>/<id>/ and calls
Scripts/eval_score.py. Exit codes: 0 all meetings scored, 2 some meetings failed, 1 nothing usable.
It also writes <out>/status.json for the workflow summary.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import ci_install_models as models  # noqa: E402
import eval_score  # noqa: E402

BUNDLE = "com.meetmind.app"
MARKER = "MEETMIND_EVAL "
PAIR = re.compile(r'(\w+)=("(?:[^"\\]|\\.)*"|\S+)')
AUDIO_EXTENSIONS = (".wav", ".m4a", ".caf", ".mp3", ".aac", ".mp4")
REQUIRED_MODELS = ("whisper-large", "diarization", "qwen-1.7b")


def parse_line(line):
    """`MEETMIND_EVAL meeting id=a state=done total_ms=5` -> ("meeting", {"id": "a", ...}); else None."""
    if MARKER not in line:
        return None
    rest = line[line.index(MARKER) + len(MARKER):].strip()
    if not rest:
        return None
    kind, _, tail = rest.partition(" ")
    fields = {key: value.strip('"') for key, value in PAIR.findall(tail)}
    return kind, fields


def summarize_events(events):
    """Fold parsed lines into {started, completed, ok, failed, meetings: {id: state}, models: {id: state}, env}."""
    state = {"started": False, "completed": False, "cancelled": False, "ok": 0, "failed": 0,
             "meetings": {}, "models": {}, "env": {}, "commit": None, "messages": {}}
    for kind, fields in events:
        if kind == "start":
            state["started"] = True
            state["commit"] = fields.get("commit")
        elif kind == "env":
            state["env"] = fields
        elif kind == "model":
            state["models"][fields.get("id", "?")] = fields
        elif kind == "meeting" and "id" in fields:
            state["meetings"][fields["id"]] = fields.get("state", "?")
            if fields.get("state") == "failed":
                state["messages"][fields["id"]] = fields.get("message", "")
        elif kind == "skipped" and "id" in fields:
            state["meetings"][fields["id"]] = "skipped"
        elif kind == "completed":
            state["completed"] = True
            state["ok"] = int(fields.get("ok", 0))
            state["failed"] = int(fields.get("failed", 0))
        elif kind == "cancelled":
            state["cancelled"] = True
    return state


def preflight_problems(state):
    """Human-readable reasons the simulator cannot run the evaluation; empty when fine."""
    problems = []
    for model_id in REQUIRED_MODELS:
        info = state["models"].get(model_id)
        if info is None:
            problems.append(f"model {model_id}: no status line from the app")
        elif info.get("state") != "ready":
            problems.append(f"model {model_id}: {info.get('state')} (app expects folder {info.get('dir')})")
    env = state["env"]
    if env.get("simulator") == "1" and env.get("available_mb") == "0":
        problems.append(
            "os_proc_available_memory() returns 0 on the simulator, so LocalLanguageModel rejects every "
            "model load. LocalLanguageModel.swift needs `#if os(iOS) && !targetEnvironment(simulator)` around "
            "both os_proc_available_memory() uses.")
    return problems


def simctl(*args, timeout=120, check=True):
    return subprocess.run(["xcrun", "simctl", *args], capture_output=True, text=True, encoding="utf-8",
                          timeout=timeout, check=check)


def launch(udid, log_path, arguments):
    """Start the app with stdout/stderr redirected into log_path. Returns the process id."""
    simctl("terminate", udid, BUNDLE, check=False)
    open(log_path, "w").close()
    result = simctl("launch", f"--stdout={log_path}", f"--stderr={log_path}", udid, BUNDLE, *arguments)
    match = re.search(r":\s*(\d+)\s*$", result.stdout.strip())
    if not match:
        raise RuntimeError("could not read the app process id from: " + result.stdout.strip())
    return int(match.group(1))


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


class LogFollower:
    def __init__(self, path):
        self.path = path
        self.offset = 0
        self.events = []

    def poll(self, echo=True):
        try:
            with open(self.path, "rb") as handle:
                handle.seek(self.offset)
                data = handle.read()
        except OSError:
            return []
        end = data.rfind(b"\n")
        if end < 0:
            return []
        self.offset += end + 1
        fresh = []
        for raw in data[:end].decode("utf-8", "replace").splitlines():
            parsed = parse_line(raw)
            if parsed:
                self.events.append(parsed)
                fresh.append(parsed)
                if echo:
                    print(raw[raw.index(MARKER):].strip(), flush=True)
        return fresh


def wait_for(udid, pid, follower, done, timeout, label):
    """Poll the log until done(state) or the app exits or the timeout. Returns (state, reason)."""
    deadline = time.monotonic() + timeout
    while True:
        follower.poll()
        state = summarize_events(follower.events)
        if done(state):
            return state, "ok"
        if not alive(pid):
            follower.poll()
            state = summarize_events(follower.events)
            return state, "app_exited" if not done(state) else "ok"
        if time.monotonic() > deadline:
            return state, "timeout"
        time.sleep(3)


def cmd_preflight(args):
    log = os.path.join(args.work, "preflight.log")
    os.makedirs(args.work, exist_ok=True)
    pid = launch(args.udid, log, ["--offline-evaluation", "--eval-only=__preflight__"])
    follower = LogFollower(log)
    state, reason = wait_for(args.udid, pid, follower, lambda s: s["completed"], args.timeout, "preflight")
    simctl("terminate", args.udid, BUNDLE, check=False)
    problems = preflight_problems(state)
    if reason != "ok" and not state["models"]:
        problems.append(f"the app never reported ({reason}); see {log}")
    for problem in problems:
        print(f"::error title=Evaluation preflight::{problem}")
    return 1 if problems else 0


def stage_golden(container, golden, only=None):
    """Copy audio and labels for each golden meeting into Documents/Evaluation. Returns the ids."""
    root = os.path.join(container, "Documents", "Evaluation")
    if os.path.isdir(root):
        shutil.rmtree(root)
    os.makedirs(root)
    names = []
    for name in sorted(os.listdir(golden)):
        folder = os.path.join(golden, name)
        if not os.path.isfile(os.path.join(folder, "labels.json")) or (only and name not in only):
            continue
        audio = next((f for f in sorted(os.listdir(folder)) if f.startswith("audio") and f.endswith(AUDIO_EXTENSIONS)), None)
        if audio is None:
            continue
        target = os.path.join(root, name)
        os.makedirs(target)
        shutil.copy2(os.path.join(folder, audio), os.path.join(target, audio))
        shutil.copy2(os.path.join(folder, "labels.json"), os.path.join(target, "labels.json"))
        names.append(name)
    return root, names


def collect_results(root, names, destination):
    got = []
    for name in names:
        source = os.path.join(root, name, "result.json")
        if os.path.isfile(source):
            os.makedirs(os.path.join(destination, name), exist_ok=True)
            shutil.copy2(source, os.path.join(destination, name, "result.json"))
            got.append(name)
    return got


def write_status(out, status):
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "status.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(status, handle, indent=2, sort_keys=True)
        handle.write("\n")


def cmd_run(args):
    only = [x.strip() for x in args.only.split(",") if x.strip()] if args.only else None
    container = models.simulator_container(args.udid)
    root, names = stage_golden(container, args.golden, only)
    if not names:
        print("::error title=Evaluation::no golden meetings with audio and labels were found")
        return 1
    print(f"staged {len(names)} meetings: {', '.join(names)}", flush=True)
    arguments = ["--offline-evaluation"]
    if only:
        arguments.append("--eval-only=" + ",".join(names))
    if args.language:
        arguments.append(f"--eval-language={args.language}")
    log = os.path.join(args.work, "evaluation.log")
    os.makedirs(args.work, exist_ok=True)
    started = time.monotonic()
    pid = launch(args.udid, log, arguments)
    follower = LogFollower(log)
    state, reason = wait_for(args.udid, pid, follower, lambda s: s["completed"] or s["cancelled"], args.timeout, "run")
    elapsed = round(time.monotonic() - started)
    if reason == "timeout":
        print(f"::error title=Evaluation::timed out after {args.timeout} s")
    elif reason == "app_exited":
        print("::error title=Evaluation::the app exited before finishing (crash or jetsam); see the crash logs artifact")
    simctl("terminate", args.udid, BUNDLE, check=False)
    commit = args.commit or state.get("commit") or "unknown"
    runs = os.path.join(args.out, "runs", commit)
    got = collect_results(root, names, runs)
    failed = sorted(set(names) - set(got))
    for name in failed:
        message = state["messages"].get(name, "")
        print(f"::error title=Evaluation failed for {name}::{message or state['meetings'].get(name, 'no result')}")
    status = {"commit": commit, "meetings": names, "scored": got, "failed": failed, "reason": reason,
              "elapsedSeconds": elapsed, "env": state["env"], "messages": state["messages"]}
    write_status(args.out, status)
    if not got:
        return 1
    score = eval_score.main(["--golden", args.golden, "--results", runs, "--out", args.out, "--commit", commit])
    if score:
        return 1
    return 0 if not failed and reason == "ok" else 2


def render_summary(out, outcome=""):
    """Markdown for $GITHUB_STEP_SUMMARY: a clear pass/fail banner, then the scorer's report."""
    lines = ["# Offline evaluation on synthetic meetings (simulator)", ""]
    status_path = os.path.join(out, "status.json")
    status = None
    if os.path.isfile(status_path):
        with open(status_path, encoding="utf-8") as handle:
            status = json.load(handle)
    if status is None:
        lines += [f"> :x: **No evaluation result was produced** (job outcome: {outcome or 'unknown'}). "
                  "Check the failing step and the `eval-logs` artifact. The IPA build is unaffected.", ""]
    elif status["failed"] or status["reason"] != "ok":
        lines += [f"> :warning: **{len(status['scored'])} of {len(status['meetings'])} meetings scored** "
                  f"(stopped: {status['reason']}, failed: {', '.join(status['failed']) or 'none'}). "
                  "The IPA build is unaffected.", ""]
        for name, message in sorted(status.get("messages", {}).items()):
            lines.append(f"- `{name}`: {message}")
        lines.append("")
    else:
        lines += [f"> :white_check_mark: **All {len(status['scored'])} meetings scored** in "
                  f"{status['elapsedSeconds'] // 60} min {status['elapsedSeconds'] % 60} s on the simulator "
                  f"(commit `{status['commit']}`). Simulator timings are CPU-only and not comparable to an iPhone.", ""]
    reports = sorted(f for f in os.listdir(out) if f.startswith("report-") and f.endswith(".md")) if os.path.isdir(out) else []
    for name in reports:
        with open(os.path.join(out, name), encoding="utf-8") as handle:
            lines.append(handle.read())
    return "\n".join(lines) + "\n"


def cmd_summary(args):
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stdout.write(render_summary(args.out, args.outcome))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    summary = sub.add_parser("summary", help="print Markdown for the GitHub step summary")
    summary.add_argument("--out", default=os.path.join("build", "eval"))
    summary.add_argument("--outcome", default="")
    pre = sub.add_parser("preflight")
    pre.add_argument("--udid", required=True)
    pre.add_argument("--work", default=os.path.join("build", "eval-work"))
    pre.add_argument("--timeout", type=int, default=900, help="seconds (hashing 2 GB of models takes a while)")
    run = sub.add_parser("run")
    run.add_argument("--udid", required=True)
    run.add_argument("--golden", required=True)
    run.add_argument("--out", default=os.path.join("build", "eval"))
    run.add_argument("--work", default=os.path.join("build", "eval-work"))
    run.add_argument("--commit")
    run.add_argument("--only")
    run.add_argument("--language")
    run.add_argument("--timeout", type=int, default=3600, help="seconds for the whole run")
    args = parser.parse_args(argv)
    try:
        if args.command == "summary":
            return cmd_summary(args)
        return cmd_preflight(args) if args.command == "preflight" else cmd_run(args)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"::error title=Evaluation::{error}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
