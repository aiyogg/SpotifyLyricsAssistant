#!/usr/bin/env python3
"""
Generates a minimal Xcode project (.xcodeproj) for SpotifyLyricsAssistant.
Run: python3 generate_xcodeproj.py
"""

import uuid
from pathlib import Path

PROJECT_NAME = "SpotifyLyricsAssistant"
BUNDLE_ID = "com.spotifylyrics.assistant"
SWIFT_VERSION = "6.0"
MACOS_TARGET = "15.0"
SOURCE_DIR = "SpotifyLyricsAssistant"

def new_id():
    return uuid.uuid4().hex[:24].upper()

base = Path(__file__).parent
src_dir = base / SOURCE_DIR

swift_files = sorted(src_dir.rglob("*.swift"))

# Resource files (relative to project root)
resource_paths = [
    src_dir / "Resources" / "Assets.xcassets",
]

print(f"Found {len(swift_files)} Swift files:")
for f in swift_files:
    print(f"  {f.relative_to(base)}")

# ─── IDs ────────────────────────────────────────────────────────────────────
# file_ref_id[path] = id  (key = Path relative to project root)
file_ref_id = {f: new_id() for f in swift_files + resource_paths}
build_file_id = {f: new_id() for f in swift_files + resource_paths}

PROJ_ID = new_id()
TARGET_ID = new_id()
GROUP_MAIN = new_id()
GROUP_PRODUCTS = new_id()
PRODUCT_REF = new_id()
BUILD_CONFIG_LIST_PROJ = new_id()
BUILD_CONFIG_LIST_TARGET = new_id()
CONFIG_DEBUG_PROJ = new_id()
CONFIG_RELEASE_PROJ = new_id()
CONFIG_DEBUG_TARGET = new_id()
CONFIG_RELEASE_TARGET = new_id()
SOURCES_PHASE = new_id()
RESOURCES_PHASE = new_id()
FRAMEWORKS_PHASE = new_id()

# ─── Group Tree ──────────────────────────────────────────────────────────────
# Build a tree of groups from the file structure
# group_tree: maps directory Path -> group_id
group_tree = {}

def get_group_id(path: Path) -> str:
    if path not in group_tree:
        group_tree[path] = new_id()
    return group_tree[path]

# Ensure all parent directories have group IDs
for f in swift_files + resource_paths:
    d = f.parent
    while d != base and d != base.parent:
        get_group_id(d)
        d = d.parent

# Root source group = src_dir
root_src_id = get_group_id(src_dir)

# ─── Build pbxproj ──────────────────────────────────────────────────────────
def pbxproj():
    lines = []
    def w(s=""): lines.append(s)

    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {")
    w("\t};")
    w("\tobjectVersion = 56;")
    w("\tobjects = {")
    w()

    # PBXBuildFile
    w("/* Begin PBXBuildFile section */")
    for f in swift_files:
        bid = build_file_id[f]
        fid = file_ref_id[f]
        w(f"\t\t{bid} /* {f.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {f.name} */; }};")
    for f in resource_paths:
        bid = build_file_id[f]
        fid = file_ref_id[f]
        w(f"\t\t{bid} /* {f.name} in Resources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {f.name} */; }};")
    w("/* End PBXBuildFile section */")
    w()

    # PBXFileReference
    w("/* Begin PBXFileReference section */")
    w(f"\t\t{PRODUCT_REF} /* {PROJECT_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {PROJECT_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    for f, fid in file_ref_id.items():
        name = f.name
        if name.endswith(".swift"):
            ftype = "sourcecode.swift"
        elif name.endswith(".plist"):
            ftype = "text.plist.xml"
        elif name.endswith(".entitlements"):
            ftype = "text.plist.entitlements"
        elif name.endswith(".xcassets"):
            ftype = "folder.assetcatalog"
        else:
            ftype = "file"
        # path is relative to its parent group (which matches parent dir)
        w(f"\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = {name}; sourceTree = \"<group>\"; }};")
    w("/* End PBXFileReference section */")
    w()

    # PBXFrameworksBuildPhase
    w("/* Begin PBXFrameworksBuildPhase section */")
    w(f"\t\t{FRAMEWORKS_PHASE} /* Frameworks */ = {{")
    w("\t\t\tisa = PBXFrameworksBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXFrameworksBuildPhase section */")
    w()

    # PBXGroup
    w("/* Begin PBXGroup section */")

    # Main group
    w(f"\t\t{GROUP_MAIN} = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w(f"\t\t\t\t{root_src_id} /* {SOURCE_DIR} */,")
    w(f"\t\t\t\t{GROUP_PRODUCTS} /* Products */,")
    w("\t\t\t);")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

    # Products
    w(f"\t\t{GROUP_PRODUCTS} /* Products */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w(f"\t\t\t\t{PRODUCT_REF} /* {PROJECT_NAME}.app */,")
    w("\t\t\t);")
    w("\t\t\tname = Products;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

    # Emit each directory group
    # For each dir in group_tree (sorted by depth so parents come before children)
    all_dirs = sorted(group_tree.keys(), key=lambda p: len(p.parts))
    for d in all_dirs:
        gid = group_tree[d]
        name = d.name

        # Children: immediate subdirs + files directly in this dir
        child_entries = []

        # Subdirectories
        for sub in sorted(d.iterdir()) if d.exists() else []:
            if sub.is_dir() and sub in group_tree:
                child_entries.append(f"\t\t\t\t{group_tree[sub]} /* {sub.name} */,")

        # Files directly in this directory
        for f in sorted(swift_files + resource_paths):
            if f.parent == d:
                fid = file_ref_id[f]
                child_entries.append(f"\t\t\t\t{fid} /* {f.name} */,")

        w(f"\t\t{gid} /* {name} */ = {{")
        w("\t\t\tisa = PBXGroup;")
        w("\t\t\tchildren = (")
        for ce in child_entries:
            w(ce)
        w("\t\t\t);")
        w(f"\t\t\tname = {name};")
        w(f"\t\t\tpath = {name};")
        w("\t\t\tsourceTree = \"<group>\";")
        w("\t\t};")

    w("/* End PBXGroup section */")
    w()

    # PBXNativeTarget
    w("/* Begin PBXNativeTarget section */")
    w(f"\t\t{TARGET_ID} /* {PROJECT_NAME} */ = {{")
    w("\t\t\tisa = PBXNativeTarget;")
    w(f"\t\t\tbuildConfigurationList = {BUILD_CONFIG_LIST_TARGET};")
    w("\t\t\tbuildPhases = (")
    w(f"\t\t\t\t{SOURCES_PHASE} /* Sources */,")
    w(f"\t\t\t\t{FRAMEWORKS_PHASE} /* Frameworks */,")
    w(f"\t\t\t\t{RESOURCES_PHASE} /* Resources */,")
    w("\t\t\t);")
    w("\t\t\tbuildRules = (")
    w("\t\t\t);")
    w("\t\t\tdependencies = (")
    w("\t\t\t);")
    w(f"\t\t\tname = {PROJECT_NAME};")
    w(f"\t\t\tproductName = {PROJECT_NAME};")
    w(f"\t\t\tproductReference = {PRODUCT_REF};")
    w("\t\t\tproductType = \"com.apple.product-type.application\";")
    w("\t\t};")
    w("/* End PBXNativeTarget section */")
    w()

    # PBXProject
    w("/* Begin PBXProject section */")
    w(f"\t\t{PROJ_ID} /* Project object */ = {{")
    w("\t\t\tisa = PBXProject;")
    w(f"\t\t\tbuildConfigurationList = {BUILD_CONFIG_LIST_PROJ};")
    w("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    w("\t\t\tdevelopmentRegion = en;")
    w("\t\t\thasScannedForEncodings = 0;")
    w("\t\t\tknownRegions = (en, Base,);")
    w(f"\t\t\tmainGroup = {GROUP_MAIN};")
    w(f"\t\t\tproductRefGroup = {GROUP_PRODUCTS};")
    w("\t\t\tprojectDirPath = \"\";")
    w("\t\t\tprojectRoot = \"\";")
    w("\t\t\ttargets = (")
    w(f"\t\t\t\t{TARGET_ID} /* {PROJECT_NAME} */,")
    w("\t\t\t);")
    w("\t\t};")
    w("/* End PBXProject section */")
    w()

    # PBXResourcesBuildPhase
    w("/* Begin PBXResourcesBuildPhase section */")
    w(f"\t\t{RESOURCES_PHASE} /* Resources */ = {{")
    w("\t\t\tisa = PBXResourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for f in resource_paths:
        bid = build_file_id[f]
        w(f"\t\t\t\t{bid} /* {f.name} in Resources */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXResourcesBuildPhase section */")
    w()

    # PBXSourcesBuildPhase
    w("/* Begin PBXSourcesBuildPhase section */")
    w(f"\t\t{SOURCES_PHASE} /* Sources */ = {{")
    w("\t\t\tisa = PBXSourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for f in swift_files:
        bid = build_file_id[f]
        w(f"\t\t\t\t{bid} /* {f.name} in Sources */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXSourcesBuildPhase section */")
    w()

    # XCBuildConfiguration
    w("/* Begin XCBuildConfiguration section */")

    shared = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "MACOSX_DEPLOYMENT_TARGET": MACOS_TARGET,
        "SWIFT_VERSION": SWIFT_VERSION,
    }

    def emit_config(cfg_id, name, extra):
        w(f"\t\t{cfg_id} /* {name} */ = {{")
        w("\t\t\tisa = XCBuildConfiguration;")
        w("\t\t\tbuildSettings = {")
        merged = {**shared, **extra}
        for k, v in sorted(merged.items()):
            w(f"\t\t\t\t{k} = {v};")
        w("\t\t\t};")
        w(f"\t\t\tname = {name};")
        w("\t\t};")

    emit_config(CONFIG_DEBUG_PROJ, "Debug", {
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0",
        'GCC_PREPROCESSOR_DEFINITIONS': '("DEBUG=1", "$(inherited)")',
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    })
    emit_config(CONFIG_RELEASE_PROJ, "Release", {
        "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
        "ENABLE_NS_ASSERTIONS": "NO",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "MTL_FAST_MATH": "YES",
    })

    target_base = {
        f'PRODUCT_BUNDLE_IDENTIFIER': f'"{BUNDLE_ID}"',
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        f"INFOPLIST_FILE": f'"{SOURCE_DIR}/Resources/Info.plist"',
        f"CODE_SIGN_ENTITLEMENTS": f'"{SOURCE_DIR}/Resources/SpotifyLyricsAssistant.entitlements"',
        "CODE_SIGN_STYLE": "Automatic",
        "ENABLE_HARDENED_RUNTIME": "YES",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/../Frameworks"',
        "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
    }

    emit_config(CONFIG_DEBUG_TARGET, "Debug", {**target_base, "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE"})
    emit_config(CONFIG_RELEASE_TARGET, "Release", {**target_base, "MTL_ENABLE_DEBUG_INFO": "NO"})
    w("/* End XCBuildConfiguration section */")
    w()

    # XCConfigurationList
    w("/* Begin XCConfigurationList section */")
    w(f"\t\t{BUILD_CONFIG_LIST_PROJ} = {{")
    w("\t\t\tisa = XCConfigurationList;")
    w("\t\t\tbuildConfigurations = (")
    w(f"\t\t\t\t{CONFIG_DEBUG_PROJ} /* Debug */,")
    w(f"\t\t\t\t{CONFIG_RELEASE_PROJ} /* Release */,")
    w("\t\t\t);")
    w("\t\t\tdefaultConfigurationIsVisible = 0;")
    w("\t\t\tdefaultConfigurationName = Release;")
    w("\t\t};")
    w(f"\t\t{BUILD_CONFIG_LIST_TARGET} = {{")
    w("\t\t\tisa = XCConfigurationList;")
    w("\t\t\tbuildConfigurations = (")
    w(f"\t\t\t\t{CONFIG_DEBUG_TARGET} /* Debug */,")
    w(f"\t\t\t\t{CONFIG_RELEASE_TARGET} /* Release */,")
    w("\t\t\t);")
    w("\t\t\tdefaultConfigurationIsVisible = 0;")
    w("\t\t\tdefaultConfigurationName = Release;")
    w("\t\t};")
    w("/* End XCConfigurationList section */")
    w()

    w("\t};")
    w(f"\trootObject = {PROJ_ID} /* Project object */;")
    w("}")

    return "\n".join(lines)

# Write
xcodeproj_dir = base / f"{PROJECT_NAME}.xcodeproj"
xcodeproj_dir.mkdir(exist_ok=True)
(xcodeproj_dir / "project.pbxproj").write_text(pbxproj())
print(f"\n✅ Generated: {xcodeproj_dir}")
print(f"   Open with: open {xcodeproj_dir}")
