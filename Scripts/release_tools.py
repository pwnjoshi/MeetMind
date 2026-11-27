#!/usr/bin/env python3
"""Release-only checks and a non-secret TestFlight build summary."""
from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import subprocess
from pathlib import Path
from typing import Iterable

BLOCKING_PLACEHOLDERS = (
    "<SUPPORT EMAIL>",
    "<DATE>",
    "<YOUR NAME OR COMPANY>",
)


def markdown_files(paths: Iterable[Path]) -> list[Path]:
    files: set[Path] = set()
    for path in paths:
        if path.is_dir():
            files.update(candidate for candidate in path.rglob("*.md") if candidate.is_file())
        elif path.is_file():
            files.add(path)
        else:
            raise ValueError(f"Submission document does not exist: {path}")
    return sorted(files)


def find_placeholders(paths: Iterable[Path]) -> dict[str, list[str]]:
    findings: dict[str, list[str]] = {}
    for path in markdown_files(paths):
        text = path.read_text(encoding="utf-8")
        matches = [token for token in BLOCKING_PLACEHOLDERS if token.casefold() in text.casefold()]
        if matches:
            findings[str(path)] = matches
    return findings


def check_placeholders(paths: Iterable[Path], upload: bool) -> int:
    findings = find_placeholders(paths)
    if not findings:
        print("PASS: hosted submission documents contain no blocking legal/contact placeholders")
        return 0
    level = "error" if upload else "warning"
    action = "Upload refused" if upload else "Dry-run allowed"
    for filename, tokens in findings.items():
        print(f"::{level} file={filename},title=Submission placeholder::{filename}: {', '.join(tokens)}")
    print(f"{action}: replace the placeholders in the filenames above before a TestFlight upload.")
    return 1 if upload else 0


def _status(path: Path) -> str:
    if not path.is_file():
        return "not run"
    value = path.read_text(encoding="utf-8").strip()
    return value or "unknown"


def _count_from_log(path: Path, patterns: tuple[str, ...]) -> str:
    if not path.is_file():
        return "unknown"
    text = path.read_text(encoding="utf-8", errors="replace")
    values: list[int] = []
    for pattern in patterns:
        values.extend(int(match) for match in re.findall(pattern, text, flags=re.IGNORECASE))
    return str(max(values)) if values else "unknown"


def parse_xcresult_summary(data: dict) -> dict[str, int | str]:
    total = data.get("totalTestCount")
    passed = data.get("passedTests")
    failed = data.get("failedTests")
    skipped = data.get("skippedTests")
    configurations = data.get("devicesAndConfigurations") or []
    if configurations:
        passed = sum(int(item.get("passedTests", 0)) for item in configurations)
        failed = sum(int(item.get("failedTests", 0)) for item in configurations)
        skipped = sum(int(item.get("skippedTests", 0)) for item in configurations)
    if total is None and all(value is not None for value in (passed, failed, skipped)):
        total = int(passed) + int(failed) + int(skipped)
    return {
        "total": total if total is not None else "unknown",
        "passed": passed if passed is not None else "unknown",
        "failed": failed if failed is not None else "unknown",
        "skipped": skipped if skipped is not None else "unknown",
    }


def xcresult_counts(path: Path) -> dict[str, int | str]:
    unknown = {"total": "unknown", "passed": "unknown", "failed": "unknown", "skipped": "unknown"}
    if not path.exists():
        return unknown
    try:
        result = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(path), "--format", "json"],
            check=True,
            capture_output=True,
            text=True,
            timeout=60,
        )
        return parse_xcresult_summary(json.loads(result.stdout))
    except (FileNotFoundError, subprocess.SubprocessError, json.JSONDecodeError, TypeError, ValueError):
        return unknown


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def plist_values(path: Path) -> dict[str, str]:
    if not path.is_file():
        return {}
    with path.open("rb") as source:
        data = plistlib.load(source)
    return {
        "marketing_version": str(data.get("CFBundleShortVersionString", "unknown")),
        "build_version": str(data.get("CFBundleVersion", "unknown")),
        "bundle_id": str(data.get("CFBundleIdentifier", "unknown")),
        "embedded_sha": str(data.get("ManentBuildCommit", "unknown")),
    }


def create_summary(args: argparse.Namespace) -> None:
    info = plist_values(args.info_plist)
    ipa_hash = sha256(args.ipa) if args.ipa.is_file() else "unavailable"
    xctest = xcresult_counts(args.xcresult)
    if xctest["total"] == "unknown":
        app_total = _count_from_log(
            getattr(args, "app_log", Path("build/xcodebuild-test.log")),
            (r"Executed\s+(\d+)\s+tests?", r"Ran\s+(\d+)\s+tests?"),
        )
        if app_total != "unknown":
            xctest["total"] = int(app_total)
            if _status(args.app_status) == "PASS":
                xctest.update({"passed": int(app_total), "failed": 0})
    python_count = _count_from_log(args.python_log, (r"Ran\s+(\d+)\s+tests?",))
    engine_count = _count_from_log(args.engine_log, (r"Executed\s+(\d+)\s+tests?", r"Ran\s+(\d+)\s+tests?"))
    lines = [
        "# Manent release summary",
        "",
        f"- Checkout SHA: `{args.sha}`",
        f"- Embedded SHA: `{info.get('embedded_sha', 'unknown')}`",
        f"- Marketing version: `{info.get('marketing_version', 'unknown')}`",
        f"- Build version: `{info.get('build_version', 'unknown')}`",
        f"- Bundle ID: `{info.get('bundle_id', args.bundle_id)}`",
        f"- Signing identity: `{args.signing_identity or 'unavailable'}`",
        f"- Provisioning profile UUID: `{args.profile_uuid or 'unavailable'}`",
        f"- Provisioning profile expiry: `{args.profile_expiry or 'unavailable'}`",
        f"- IPA SHA-256: `{ipa_hash}`",
        f"- Privacy and signed-IPA validation: `{_status(args.privacy_status)}`",
        "",
        "## Test counts",
        "",
        f"- Python: {python_count} ({_status(args.python_status)})",
        f"- OfflineEngineKit Swift: {engine_count} ({_status(args.engine_status)})",
        (
            f"- App XCTest: {xctest['total']} total, {xctest['passed']} passed, "
            f"{xctest['failed']} failed, {xctest['skipped']} skipped ({_status(args.app_status)})"
        ),
        f"- Launch smoke: {_status(args.smoke_status)}",
        "",
        "Generated from local build artifacts. This file contains no signing secrets or private keys.",
    ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote release summary to {args.output}")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)

    placeholders = commands.add_parser("check-placeholders")
    placeholders.add_argument("--upload", action="store_true", help="fail instead of warn")
    placeholders.add_argument("paths", nargs="+", type=Path)

    summary = commands.add_parser("summary")
    summary.add_argument("--sha", required=True)
    summary.add_argument("--bundle-id", required=True)
    summary.add_argument("--signing-identity", default="")
    summary.add_argument("--profile-uuid", default="")
    summary.add_argument("--profile-expiry", default="")
    summary.add_argument("--ipa", type=Path, default=Path("build/export/Manent.ipa"))
    summary.add_argument("--info-plist", type=Path, default=Path("build/archive-Info.plist"))
    summary.add_argument("--xcresult", type=Path, default=Path("build/TestResults.xcresult"))
    summary.add_argument("--app-log", type=Path, default=Path("build/xcodebuild-test.log"))
    summary.add_argument("--python-log", type=Path, default=Path("build/python-tests.log"))
    summary.add_argument("--engine-log", type=Path, default=Path("build/engine-tests.log"))
    summary.add_argument("--python-status", type=Path, default=Path("build/python-tests.status"))
    summary.add_argument("--engine-status", type=Path, default=Path("build/engine-tests.status"))
    summary.add_argument("--app-status", type=Path, default=Path("build/app-tests.status"))
    summary.add_argument("--smoke-status", type=Path, default=Path("build/launch-smoke.status"))
    summary.add_argument("--privacy-status", type=Path, default=Path("build/privacy-validation.status"))
    summary.add_argument("--output", type=Path, default=Path("build/release-summary.md"))
    return result


def main() -> int:
    args = parser().parse_args()
    if args.command == "check-placeholders":
        return check_placeholders(args.paths, args.upload)
    create_summary(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
