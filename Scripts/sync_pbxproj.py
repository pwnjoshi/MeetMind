#!/usr/bin/env python3
"""
Synchronizes MeetMind.xcodeproj/project.pbxproj by registering all missing Swift files.
"""

import os
import re

PBX_PATH = "MeetMind.xcodeproj/project.pbxproj"

def sync_project():
    with open(PBX_PATH, "r", encoding="utf-8") as f:
        pbx = f.read()

    # Find highest used ID suffix
    existing_ids = re.findall(r'1[A-F]0000([0-9A-Fa-f]{2})2CEE', pbx)
    next_idx = max(int(h, 16) for h in existing_ids) + 1 if existing_ids else 0xA0

    # Collect all missing files
    files_to_add = []
    for root, _, files in os.walk("."):
        if ".git" in root or ".agents" in root:
            continue
        for f in files:
            if f.endswith(".swift") and f not in pbx:
                rel = os.path.relpath(os.path.join(root, f), ".").replace("\\", "/")
                is_test = "Tests" in rel
                files_to_add.append((f, rel, is_test))

    print(f"Found {len(files_to_add)} missing files to register.")
    if not files_to_add:
        print("Nothing to sync.")
        return

    pbx_build_files = []
    pbx_file_refs = []
    app_sources_entries = []
    test_sources_entries = []
    file_map = {}

    for f, rel, is_test in files_to_add:
        idx_hex = f"{next_idx:02X}"
        next_idx += 1
        build_id = f"1A0000{idx_hex}2CEE000100000001"
        ref_id = f"1B0000{idx_hex}2CEE000100000001"

        file_map[f] = (build_id, ref_id, rel, is_test)

        pbx_build_files.append(
            f"\t\t{build_id} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_id} /* {f} */; }};"
        )
        pbx_file_refs.append(
            f"\t\t{ref_id} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = \"<group>\"; }};"
        )
        entry = f"\t\t\t\t{build_id} /* {f} in Sources */,"
        if is_test:
            test_sources_entries.append(entry)
        else:
            app_sources_entries.append(entry)

    # 1. Insert PBXBuildFile entries
    pbx = pbx.replace(
        "/* End PBXBuildFile section */",
        "\n".join(pbx_build_files) + "\n/* End PBXBuildFile section */"
    )

    # 2. Insert PBXFileReference entries
    pbx = pbx.replace(
        "/* End PBXFileReference section */",
        "\n".join(pbx_file_refs) + "\n/* End PBXFileReference section */"
    )

    # 3. Insert into Sources Build Phase for App target (1F0000202CEE000100000001)
    app_pattern = r'(1F0000202CEE000100000001 /\* Sources \*/ = \{[\s\S]*?files = \([\s\S]*?)(\s*\);\s*runOnlyForDeploymentPostprocessing)'
    app_replacement = r'\1\n' + "\n".join(app_sources_entries) + r'\2'
    pbx = re.sub(app_pattern, app_replacement, pbx, count=1)

    # 4. Insert into Sources Build Phase for Tests target (1F0000212CEE000100000001)
    test_pattern = r'(1F0000212CEE000100000001 /\* Sources \*/ = \{[\s\S]*?files = \([\s\S]*?)(\s*\);\s*runOnlyForDeploymentPostprocessing)'
    test_replacement = r'\1\n' + "\n".join(test_sources_entries) + r'\2'
    pbx = re.sub(test_pattern, test_replacement, pbx, count=1)

    with open(PBX_PATH, "w", encoding="utf-8") as f:
        f.write(pbx)

    print(f"Successfully registered {len(files_to_add)} files into {PBX_PATH}")

if __name__ == "__main__":
    sync_project()
