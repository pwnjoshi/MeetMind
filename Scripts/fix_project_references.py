import os
import re

# 1. Map all swift files on disk
disk_map = {} # filename -> relpath from repo root
for root, dirs, files in os.walk('.'):
    if '.git' in root or 'DerivedData' in root or 'build' in root:
        continue
    for f in files:
        if f.endswith('.swift') or f.endswith('.plist'):
            rel = os.path.relpath(os.path.join(root, f), '.').replace('\\', '/')
            disk_map[f] = rel

print(f"Total files on disk: {len(disk_map)}")

with open('MeetMind.xcodeproj/project.pbxproj', 'r', encoding='utf-8') as f:
    pbx = f.read()

# Check for phantom / renamed files
# E.g. MeetingTemplateSelectorView.swift -> MeetingTemplatePicker.swift
if 'MeetingTemplateSelectorView.swift' in pbx:
    pbx = pbx.replace('MeetingTemplateSelectorView.swift', 'MeetingTemplatePicker.swift')
    print("Replaced MeetingTemplateSelectorView.swift with MeetingTemplatePicker.swift")

# For every PBXFileReference, if the file is in disk_map, set sourceTree = SOURCE_ROOT and path = disk_map[filename]
def fix_file_ref(match):
    file_id = match.group(1)
    filename = match.group(2).strip()
    rest = match.group(3)
    
    # Products (MeetMind.app, MeetMindTests.xctest) stay BUILT_PRODUCTS_DIR
    if 'wrapper.application' in rest or 'wrapper.cfbundle' in rest:
        return match.group(0)
    
    if filename in disk_map:
        exact_path = disk_map[filename]
        # Return updated PBXFileReference with SOURCE_ROOT
        return f'\t\t{file_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{exact_path}"; sourceTree = SOURCE_ROOT; }};'
    else:
        print(f"WARNING: File {filename} not found on disk!")
        return match.group(0)

# Regex matching PBXFileReference
ref_pattern = re.compile(r'^\t\t([0-9A-Fa-f]{24})\s+/\*\s+(.*?)\s+\*/\s+=\s+\{isa = PBXFileReference;(.*?)\};$', re.MULTILINE)
new_pbx, count = ref_pattern.subn(fix_file_ref, pbx)
print(f"Updated {count} PBXFileReference entries to SOURCE_ROOT")

with open('MeetMind.xcodeproj/project.pbxproj', 'w', encoding='utf-8') as f:
    f.write(new_pbx)

print("Saved project.pbxproj successfully")
