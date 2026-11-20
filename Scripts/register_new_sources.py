#!/usr/bin/env python3
"""Register every Swift file under MeetMind/ and MeetMindTests/ that project.pbxproj does not reference by path.

App files join the MeetMind group and app Sources phase; test files join the MeetMindTests group and test
Sources phase. Matching is by SOURCE_ROOT-relative path, so files with the same name in different folders work.
Usage: python Scripts/register_new_sources.py [--check]
"""
import os, re, sys

PBX = "MeetMind.xcodeproj/project.pbxproj"
TARGETS = {
    "MeetMind": ("1D0000032CEE000100000001", "1F0000202CEE000100000001"),
    "MeetMindTests": ("1D0000042CEE000100000001", "1F0000212CEE000100000001"),
}


def main():
    check = "--check" in sys.argv
    pbx = open(PBX, encoding="utf-8").read()
    referenced = set(re.findall(r'path = "?([^";]+\.swift)"?;', pbx))
    used = set(re.findall(r"[0-9A-F]{24}", pbx))
    counter = [0xC000]

    def new_id(prefix):
        while True:
            candidate = f"{prefix}{counter[0]:04X}2CEE000100000001"
            counter[0] += 1
            if candidate not in used:
                used.add(candidate)
                return candidate

    missing = []
    for top in TARGETS:
        for root, _, files in os.walk(top):
            for name in sorted(files):
                if name.endswith(".swift"):
                    rel = os.path.join(root, name).replace("\\", "/")
                    if rel not in referenced:
                        missing.append((top, name, rel))

    for _, _, rel in missing:
        print("missing:", rel)
    if check:
        sys.exit(1 if missing else 0)
    if not missing:
        print("All Swift sources are registered.")
        return

    build_lines, ref_lines = [], []
    group_add = {t: [] for t in TARGETS}
    phase_add = {t: [] for t in TARGETS}
    for top, name, rel in missing:
        b, r = new_id("1A"), new_id("1B")
        build_lines.append(f"\t\t{b} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {r} /* {name} */; }};")
        ref_lines.append(f'\t\t{r} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{rel}"; sourceTree = SOURCE_ROOT; }};')
        group_add[top].append(f"\t\t\t\t{r} /* {name} */,")
        phase_add[top].append(f"\t\t\t\t{b} /* {name} in Sources */,")

    def insert_after(marker, lines):
        nonlocal pbx
        i = pbx.index(marker) + len(marker)
        pbx = pbx[:i] + "\n" + "\n".join(lines) + pbx[i:]

    insert_after("/* Begin PBXBuildFile section */", build_lines)
    insert_after("/* Begin PBXFileReference section */", ref_lines)
    for top, (group_id, phase_id) in TARGETS.items():
        for obj_id, key, lines in ((group_id, "children", group_add[top]), (phase_id, "files", phase_add[top])):
            if not lines:
                continue
            m = re.search(re.escape(obj_id) + r" /\* [^*]+ \*/ = \{[^}]*?" + key + r" = \(", pbx)
            if not m:
                raise SystemExit(f"could not find {key} of {obj_id}")
            pbx = pbx[:m.end()] + "\n" + "\n".join(lines) + pbx[m.end():]

    open(PBX, "w", encoding="utf-8", newline="").write(pbx)
    print(f"Registered {len(missing)} files.")


if __name__ == "__main__":
    main()
