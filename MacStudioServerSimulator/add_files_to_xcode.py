#!/usr/bin/env python3
"""
Add new Swift files to Xcode project
"""
import re
import uuid

project_file = "MacStudioServerSimulator.xcodeproj/project.pbxproj"

# Read the project file
with open(project_file, 'r') as f:
    content = f.read()

# Generate unique IDs for the new files
files_to_add = [
    "ServerManagementTestsTab.swift",
    "ABCDTestRunner.swift",
    "ABCDResultsDashboard.swift"
]

# Generate UUIDs (24 hex chars like Xcode uses)
new_file_refs = {}
new_build_refs = {}

for filename in files_to_add:
    # Generate deterministic-ish IDs
    file_ref_id = ''.join(f"{ord(c):02X}" for c in filename[:12])[:24].upper()
    build_ref_id = ''.join(f"{ord(c):02X}" for c in (filename + "BUILD")[:12])[:24].upper()
    new_file_refs[filename] = file_ref_id
    new_build_refs[filename] = build_ref_id

# Add PBXBuildFile entries
build_file_section = re.search(r'(/\* Begin PBXBuildFile section \*/.*?)(/\* End PBXBuildFile section \*/)', content, re.DOTALL)
if build_file_section:
    existing_entries = build_file_section.group(1)
    new_entries = ""
    for filename in files_to_add:
        new_entries += f"\t\t{new_build_refs[filename]} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {new_file_refs[filename]} /* {filename} */; }};\n"
    
    content = content.replace(
        build_file_section.group(0),
        build_file_section.group(1) + new_entries + "\t\t" + build_file_section.group(2)
    )

# Add PBXFileReference entries
file_ref_section = re.search(r'(/\* Begin PBXFileReference section \*/.*?)(/\* End PBXFileReference section \*/)', content, re.DOTALL)
if file_ref_section:
    existing_entries = file_ref_section.group(1)
    new_entries = ""
    for filename in files_to_add:
        new_entries += f"\t\t{new_file_refs[filename]} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = \"<group>\"; }};\n"
    
    content = content.replace(
        file_ref_section.group(0),
        file_ref_section.group(1) + new_entries + "\t\t" + file_ref_section.group(2)
    )

# Add to PBXGroup (main group with all the source files)
group_section = re.search(r'(A100000100000000000D /\* MacStudioServerSimulator \*/ = \{.*?children = \()(.*?)(\);.*?path = MacStudioServerSimulator;)', content, re.DOTALL)
if group_section:
    existing_children = group_section.group(2)
    new_children = ""
    for filename in files_to_add:
        new_children += f"\t\t\t\t{new_file_refs[filename]} /* {filename} */,\n"
    
    content = content.replace(
        group_section.group(0),
        group_section.group(1) + existing_children + new_children + group_section.group(3)
    )

# Add to PBXSourcesBuildPhase
sources_section = re.search(r'(/\* Sources \*/ = \{.*?files = \()(.*?)(\);)', content, re.DOTALL)
if sources_section:
    existing_files = sources_section.group(2)
    new_files = ""
    for filename in files_to_add:
        new_files += f"\t\t\t\t{new_build_refs[filename]} /* {filename} in Sources */,\n"
    
    content = content.replace(
        sources_section.group(0),
        sources_section.group(1) + existing_files + new_files + sources_section.group(3)
    )

# Write back
with open(project_file, 'w') as f:
    f.write(content)

print("✅ Added the following files to Xcode project:")
for filename in files_to_add:
    print(f"   - {filename}")
print("\nNow rebuild in Xcode (⌘+B)")
