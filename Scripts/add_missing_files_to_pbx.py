import os
import re

with open('MeetMind.xcodeproj/project.pbxproj', 'r', encoding='utf-8') as f:
    pbx = f.read()

# Collect all existing IDs
existing_ids = set(re.findall(r'[0-9A-Fa-f]{24}', pbx))

# Find missing swift files in MeetMind
missing = []
for root, dirs, files in os.walk('MeetMind'):
    for file in files:
        if file.endswith('.swift'):
            if file not in pbx:
                rel = os.path.relpath(os.path.join(root, file), '.').replace('\\', '/')
                missing.append((file, rel))

print(f"Found {len(missing)} missing files:")
for f, path in missing:
    print(f"  {f} -> {path}")

if not missing:
    print("Nothing to add!")
    exit(0)

# Generate new IDs
next_build_counter = 0xE000
next_ref_counter = 0xE000

build_file_entries = []
file_ref_entries = []
group_children_entries = []
sources_entries = []

for filename, filepath in missing:
    while True:
        build_id = f"1A{next_build_counter:04X}2CEE000100000001"
        next_build_counter += 1
        if build_id not in existing_ids:
            existing_ids.add(build_id)
            break
            
    while True:
        ref_id = f"1B{next_ref_counter:04X}2CEE000100000001"
        next_ref_counter += 1
        if ref_id not in existing_ids:
            existing_ids.add(ref_id)
            break

    build_file_entries.append(f"\t\t{build_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_id} /* {filename} */; }};")
    file_ref_entries.append(f'\t\t{ref_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{filepath}"; sourceTree = SOURCE_ROOT; }};')
    group_children_entries.append(f"\t\t\t\t{ref_id} /* {filename} */,")
    sources_entries.append(f"\t\t\t\t{build_id} /* {filename} in Sources */,")

# 1. Insert into PBXBuildFile section
pos_build = pbx.find('/* Begin PBXBuildFile section */') + len('/* Begin PBXBuildFile section */\n')
pbx = pbx[:pos_build] + '\n'.join(build_file_entries) + '\n' + pbx[pos_build:]

# 2. Insert into PBXFileReference section
pos_ref = pbx.find('/* Begin PBXFileReference section */') + len('/* Begin PBXFileReference section */\n')
pbx = pbx[:pos_ref] + '\n'.join(file_ref_entries) + '\n' + pbx[pos_ref:]

# 3. Insert into Views PBXGroup
views_pattern = r'(1D0000172CEE000100000001 /\* Views \*/ = \{[^\}]+children = \(\n)'
pbx = re.sub(views_pattern, r'\g<1>' + '\n'.join(group_children_entries) + '\n', pbx)

# 4. Insert into Sources build phase
sources_pattern = r'(1F0000202CEE000100000001 /\* Sources \*/ = \{[^\}]+files = \(\n)'
pbx = re.sub(sources_pattern, r'\g<1>' + '\n'.join(sources_entries) + '\n', pbx)

with open('MeetMind.xcodeproj/project.pbxproj', 'w', encoding='utf-8') as f:
    f.write(pbx)

print("Successfully updated project.pbxproj with missing files!")
