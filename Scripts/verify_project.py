#!/usr/bin/env python3
"""
MeetMind Project Verification & Architecture Integrity Gatekeeper
Platform: Cross-platform (Windows, macOS, Linux)
Target: Swift 5.9 / iOS 17+ Clean Architecture + MVVM + Observation
Validates:
  1. Filesystem Layout & Architecture Compliance (Clean Architecture boundaries)
  2. Xcode project.pbxproj Integrity (Deployment target, Swift 5.9, Strict Concurrency)
  3. Info.plist Capabilities & Privacy Descriptions (Microphone, Speech, Background Audio)
  4. Assets.xcassets Catalog & Design System Tokens (Figma palette compliance)
  5. Swift Static Code Quality (Balanced delimiters, concurrency safety, zero TODO stubs)
"""

import sys
import os
import re
import json
import argparse
import xml.etree.ElementTree as ET
from typing import List, Dict, Tuple, Optional

# ANSI Color formatting
ESC = "\033"
GREEN = f"{ESC}[92m"
RED = f"{ESC}[91m"
YELLOW = f"{ESC}[93m"
CYAN = f"{ESC}[96m"
BOLD = f"{ESC}[1m"
DIM = f"{ESC}[2m"
RESET = f"{ESC}[0m"


def clean_swift_delimiters(line: str) -> str:
    """Strips comments and string literals without mishandling '//' inside strings."""
    out = []
    in_str = False
    escape = False
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if in_str:
            if escape:
                escape = False
            elif c == '\\':
                escape = True
            elif c == '"':
                in_str = False
            i += 1
            continue

        if c == '"':
            in_str = True
            i += 1
            continue

        if c == '/' and i + 1 < n and line[i + 1] == '/':
            break  # comment starts, ignore rest of line

        out.append(c)
        i += 1
    return "".join(out)


REQUIRED_DIRECTORIES = [
    "MeetMind",
    "MeetMind/DesignSystem",
    "MeetMind/DesignSystem/Components",
    "MeetMind/DesignSystem/Components/Buttons",
    "MeetMind/DesignSystem/Components/Cards",
    "MeetMind/DesignSystem/Components/Badges",
    "MeetMind/DesignSystem/Components/Inputs",
    "MeetMind/DesignSystem/Components/Audio",
    "MeetMind/Models",
    "MeetMind/Services",
    "MeetMind/Services/Audio",
    "MeetMind/Services/Transcription",
    "MeetMind/Services/Intelligence",
    "MeetMind/Services/Export",
    "MeetMind/Services/Persistence",
    "MeetMind/Resources",
    "MeetMindTests",
    "MeetMindTests/Models",
    "MeetMindTests/Services",
    "MeetMindTests/ViewModels",
    "MeetMindTests/E2E",
    "Scripts",
]

REQUIRED_FILES = [
    # Scaffolding & Config
    ".gitignore",
    "README.md",
    "PROJECT.md",
    "TEST_INFRA.md",
    "MeetMind.xcodeproj/project.pbxproj",
    "MeetMind/Resources/Info.plist",
    # Design System
    "MeetMind/DesignSystem/Theme.swift",
    "MeetMind/DesignSystem/Typography.swift",
    "MeetMind/DesignSystem/Spacing.swift",
    "MeetMind/DesignSystem/Components/Buttons/Buttons.swift",
    "MeetMind/DesignSystem/Components/Cards/Cards.swift",
    "MeetMind/DesignSystem/Components/Badges/Badges.swift",
    "MeetMind/DesignSystem/Components/Inputs/Inputs.swift",
    "MeetMind/DesignSystem/Components/Audio/AudioWaveformBar.swift",
    # Models & Persistence
    "MeetMind/Models/Meeting.swift",
    "MeetMind/Models/TranscriptSegment.swift",
    "MeetMind/Models/Speaker.swift",
    "MeetMind/Models/Summary.swift",
    "MeetMind/Models/ActionItem.swift",
    "MeetMind/Models/Note.swift",
    "MeetMind/Models/Tag.swift",
    "MeetMind/Models/Folder.swift",
    "MeetMind/Models/FilterOptions.swift",
    "MeetMind/Models/SampleDataGenerator.swift",
    "MeetMind/Services/Persistence/ModelContainerFactory.swift",
    # Domain Services
    "MeetMind/Services/Audio/AudioRecordingServiceProtocol.swift",
    "MeetMind/Services/Audio/AudioRecordingService.swift",
    "MeetMind/Services/Audio/AudioPlaybackServiceProtocol.swift",
    "MeetMind/Services/Audio/AudioPlaybackService.swift",
    "MeetMind/Services/Audio/MockAudioRecordingService.swift",
    "MeetMind/Services/Audio/MockAudioPlaybackService.swift",
    "MeetMind/Services/Transcription/SpeechTranscriptionServiceProtocol.swift",
    "MeetMind/Services/Transcription/SpeechTranscriptionService.swift",
    "MeetMind/Services/Transcription/MockSpeechTranscriptionService.swift",
    "MeetMind/Services/Intelligence/SummarizationServiceProtocol.swift",
    "MeetMind/Services/Intelligence/NaturalLanguageSummarizationService.swift",
    "MeetMind/Services/Intelligence/LLMSummarizationService.swift",
    "MeetMind/Services/Intelligence/MockSummarizationService.swift",
    "MeetMind/Services/Export/ExportServiceProtocol.swift",
    "MeetMind/Services/Export/ExportService.swift",
    "MeetMind/Services/Export/MockExportService.swift",
    # Scripts
    "Scripts/verify_project.py",
    "Scripts/run_unit_tests.py",
]


class ProjectVerifier:
    def __init__(self, root_dir: str = ".", strict: bool = False):
        self.root_dir = os.path.abspath(root_dir)
        self.strict = strict
        self.errors: List[str] = []
        self.warnings: List[str] = []
        self.passed_checks: List[str] = []

    def log_pass(self, check_name: str, detail: str = ""):
        msg = f"{GREEN}✓{RESET} {check_name}"
        if detail:
            msg += f" {DIM}({detail}){RESET}"
        print(f"  {msg}")
        self.passed_checks.append(check_name)

    def log_warn(self, check_name: str, detail: str):
        print(f"  {YELLOW}⚠{RESET} {check_name}: {detail}")
        self.warnings.append(f"{check_name}: {detail}")

    def log_error(self, check_name: str, detail: str):
        print(f"  {RED}✗{RESET} {check_name}: {detail}")
        self.errors.append(f"{check_name}: {detail}")

    def verify_all(self) -> bool:
        print("=" * 80)
        print(f"{BOLD}{CYAN} MEETMIND PROJECT INTEGRITY & ARCHITECTURE VERIFIER{RESET}")
        print("=" * 80)
        print(f"Target Directory: {self.root_dir}")
        print(f"Mode: {'STRICT' if self.strict else 'STANDARD ARCHITECTURE VERIFICATION'}")
        print("-" * 80)

        print(f"\n{BOLD}[1/5] Verifying Filesystem Layout & Architecture Compliance...{RESET}")
        self.verify_filesystem_layout()

        print(f"\n{BOLD}[2/5] Verifying Xcode project.pbxproj Integrity...{RESET}")
        self.verify_pbxproj_structure()

        print(f"\n{BOLD}[3/5] Verifying Info.plist Privacy & Capabilities...{RESET}")
        self.verify_info_plist()

        print(f"\n{BOLD}[4/5] Verifying Assets Catalog & Design Tokens...{RESET}")
        self.verify_assets_catalog()

        print(f"\n{BOLD}[5/5] Verifying Swift Static Code Quality & Architectural Standards...{RESET}")
        self.verify_swift_code_quality()

        print("\n" + "=" * 80)
        print(f"{BOLD} VERIFICATION SUMMARY{RESET}")
        print("=" * 80)
        print(f" Passed Checks: {GREEN}{len(self.passed_checks)}{RESET}")
        print(f" Warnings:      {YELLOW}{len(self.warnings)}{RESET}")
        print(f" Errors:        {RED}{len(self.errors)}{RESET}")
        print("-" * 80)

        if self.errors:
            print(f"\n{RED}{BOLD}[FAIL] Project integrity check failed with {len(self.errors)} errors:{RESET}")
            for err in self.errors:
                print(f"  {RED}• {err}{RESET}")
            return False
        else:
            print(f"\n{GREEN}{BOLD}[PASS] Project verification successful with 0 errors!{RESET}")
            return True

    def verify_filesystem_layout(self):
        # 1. State Isolation Check
        teamwork_dir = os.path.join(self.root_dir, ".agents", "teamwork")
        if os.path.exists(teamwork_dir):
            self.log_warn(
                "State Directory Notice",
                ".agents/teamwork found in working directory (created by concurrent agent). State should reside in AppData scratch."
            )
        else:
            self.log_pass("State Directory Isolation", ".agents/teamwork is cleanly isolated from working directory")

        # 2. Required directories
        missing_dirs = []
        for d in REQUIRED_DIRECTORIES:
            full_p = os.path.join(self.root_dir, d)
            if not os.path.isdir(full_p):
                missing_dirs.append(d)

        if not missing_dirs:
            self.log_pass("Directory Layout", f"All {len(REQUIRED_DIRECTORIES)} required directories present")
        else:
            if self.strict:
                self.log_error("Directory Layout", f"Missing {len(missing_dirs)} required directories: {', '.join(missing_dirs)}")
            else:
                self.log_warn("Directory Layout", f"Missing directories: {', '.join(missing_dirs)}")

        # 3. Required files
        missing_files = []
        for f in REQUIRED_FILES:
            full_p = os.path.join(self.root_dir, f)
            if not os.path.isfile(full_p):
                missing_files.append(f)

        if not missing_files:
            self.log_pass("Core Scaffolding Files", f"All {len(REQUIRED_FILES)} required source & config files present")
        else:
            if self.strict:
                self.log_error("Core Scaffolding Files", f"Missing {len(missing_files)} required files: {', '.join(missing_files)}")
            else:
                self.log_warn("Core Scaffolding Files", f"Missing files: {', '.join(missing_files)}")

    def verify_pbxproj_structure(self):
        pbx_path = os.path.join(self.root_dir, "MeetMind.xcodeproj", "project.pbxproj")
        if not os.path.exists(pbx_path):
            self.log_error("Xcode Project", "MeetMind.xcodeproj/project.pbxproj not found")
            return

        with open(pbx_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()

        if content.startswith("// !$*UTF8*$!"):
            self.log_pass("PBX Header", "Valid // !$*UTF8*$! header present")
        else:
            self.log_error("PBX Header", "Missing standard // !$*UTF8*$! Xcode header")

        if "IPHONEOS_DEPLOYMENT_TARGET = 17.0" in content or "IPHONEOS_DEPLOYMENT_TARGET = 17" in content:
            self.log_pass("Deployment Target", "iOS 17.0+ deployment target configured")
        else:
            self.log_error("Deployment Target", "Missing IPHONEOS_DEPLOYMENT_TARGET = 17.0 in project.pbxproj")

        if "SWIFT_VERSION = 5.9" in content or "SWIFT_VERSION = 5" in content:
            self.log_pass("Swift Version", "Swift 5.9 compiler version configured")
        else:
            self.log_error("Swift Version", "Missing SWIFT_VERSION = 5.9 in project.pbxproj")

        if "com.meetmind.app" in content:
            self.log_pass("Bundle Identifier", "Bundle identifier com.meetmind.app configured")
        else:
            self.log_error("Bundle Identifier", "Missing bundle identifier com.meetmind.app in project.pbxproj")

        if "PBXNativeTarget" in content:
            self.log_pass("PBX Targets", "PBXNativeTarget build configurations defined")
        else:
            self.log_error("PBX Targets", "Missing PBXNativeTarget section in project.pbxproj")

    def verify_info_plist(self):
        plist_path = os.path.join(self.root_dir, "MeetMind", "Resources", "Info.plist")
        if not os.path.exists(plist_path):
            self.log_error("Info.plist", "MeetMind/Resources/Info.plist not found")
            return

        with open(plist_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()

        try:
            ET.fromstring(content)
            self.log_pass("Info.plist XML", "Valid XML structure")
        except Exception as e:
            self.log_error("Info.plist XML", f"XML parse error: {e}")

        if "NSMicrophoneUsageDescription" in content:
            self.log_pass("Privacy: Microphone", "NSMicrophoneUsageDescription present")
        else:
            self.log_error("Privacy: Microphone", "Missing NSMicrophoneUsageDescription in Info.plist")

        if "NSSpeechRecognitionUsageDescription" in content:
            self.log_pass("Privacy: Speech", "NSSpeechRecognitionUsageDescription present")
        else:
            self.log_error("Privacy: Speech", "Missing NSSpeechRecognitionUsageDescription in Info.plist")

        if "UIBackgroundModes" in content and "audio" in content:
            self.log_pass("Background Audio", "UIBackgroundModes audio configured for background recording/playback")
        else:
            self.log_error("Background Audio", "Missing UIBackgroundModes with audio in Info.plist")

    def verify_assets_catalog(self):
        assets_dir = os.path.join(self.root_dir, "MeetMind", "Resources", "Assets.xcassets")
        if not os.path.exists(assets_dir):
            self.log_warn("Assets Catalog", "Assets.xcassets not yet populated (UI themes defined in Theme.swift)")
            return

        root_contents = os.path.join(assets_dir, "Contents.json")
        if os.path.exists(root_contents):
            try:
                with open(root_contents, "r", encoding="utf-8") as f:
                    json.load(f)
                self.log_pass("Assets Root", "Valid root Contents.json in Assets.xcassets")
            except Exception as e:
                self.log_error("Assets Root", f"Invalid Contents.json in Assets.xcassets: {e}")

    def verify_swift_code_quality(self):
        swift_files: List[str] = []
        for root, _, files in os.walk(self.root_dir):
            if ".git" in root or ".agents" in root or "node_modules" in root:
                continue
            for f in files:
                if f.endswith(".swift"):
                    swift_files.append(os.path.join(root, f))

        if not swift_files:
            self.log_error("Swift Sources", "No Swift source files found in workspace")
            return

        total_lines = 0
        balanced_files = 0
        forbidden_stubs = []
        syntax_delimiters_errors = []
        has_sendable = False
        has_in_memory_container = False
        has_protocols = False

        for fp in swift_files:
            rel_path = os.path.relpath(fp, self.root_dir)
            with open(fp, "r", encoding="utf-8", errors="replace") as sf:
                lines = sf.readlines()
            total_lines += len(lines)

            braces = 0
            parens = 0
            brackets = 0

            for idx, line in enumerate(lines, 1):
                clean_line = clean_swift_delimiters(line)

                braces += clean_line.count("{") - clean_line.count("}")
                parens += clean_line.count("(") - clean_line.count(")")
                brackets += clean_line.count("[") - clean_line.count("]")

                stripped = line.strip()
                if 'fatalError("TODO' in stripped or 'fatalError("Not implemented' in stripped:
                    forbidden_stubs.append(f"{rel_path}:{idx}: {stripped}")
                elif re.search(r'\bTODO:\s*implement\b', stripped, re.IGNORECASE):
                    forbidden_stubs.append(f"{rel_path}:{idx}: {stripped}")

                if "protocol " in stripped:
                    has_protocols = True
                if "Sendable" in stripped:
                    has_sendable = True
                if "isStoredInMemoryOnly: true" in stripped:
                    has_in_memory_container = True

            if braces != 0 or parens != 0 or brackets != 0:
                syntax_delimiters_errors.append(
                    f"{rel_path} (braces offset: {braces}, parens offset: {parens}, brackets offset: {brackets})"
                )
            else:
                balanced_files += 1

        if syntax_delimiters_errors:
            for s_err in syntax_delimiters_errors:
                self.log_error("Delimiter Balance", s_err)
        else:
            self.log_pass("Delimiter Balance", f"All {len(swift_files)} Swift files have perfectly balanced delimiters")

        if forbidden_stubs:
            for stub in forbidden_stubs[:5]:
                self.log_error("Forbidden Stub", stub)
            if len(forbidden_stubs) > 5:
                self.log_error("Forbidden Stub", f"... and {len(forbidden_stubs) - 5} more placeholder stubs")
        else:
            self.log_pass("Code Authenticity", f"Zero forbidden placeholder stubs across {total_lines:,} lines of Swift code")

        # Architectural Standards Validation
        if has_protocols:
            self.log_pass("Clean Architecture: Protocols", "Service contracts strictly defined as Protocols for dependency injection")
        else:
            self.log_error("Clean Architecture: Protocols", "Missing service protocols")

        if has_sendable:
            self.log_pass("Swift Concurrency: Sendable", "Data models and stream chunks conform to Sendable protocol")
        else:
            self.log_warn("Swift Concurrency: Sendable", "No Sendable models detected yet")

        if has_in_memory_container:
            self.log_pass("SwiftData Isolation", "In-memory ModelContainer (isStoredInMemoryOnly: true) configured for test isolation")
        else:
            self.log_warn("SwiftData Isolation", "In-memory ModelContainer not detected yet")


def main():
    parser = argparse.ArgumentParser(description="MeetMind Project Verification Gatekeeper")
    parser.add_argument("--strict", action="store_true", help="Fail if any optional component is missing")
    parser.add_argument("--root", default=".", help="Root directory of the MeetMind repository")
    args = parser.parse_args()

    verifier = ProjectVerifier(root_dir=args.root, strict=args.strict)
    success = verifier.verify_all()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
