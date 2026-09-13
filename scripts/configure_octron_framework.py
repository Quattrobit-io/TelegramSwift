#!/usr/bin/env python3
"""Derive the embedded framework target from the pinned native application target."""

import hashlib
import json
import os
import plistlib
from pathlib import Path
import subprocess
from xml.sax.saxutils import escape


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "work" / "octron-project"
UPSTREAM_TARGET = "D098C7141D7E175A007784E4"


def identifier(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def configure():
    project = json.loads(subprocess.check_output([
        "plutil", "-convert", "json", "-o", "-",
        str(ROOT / "Telegram.xcodeproj" / "project.pbxproj"),
    ]))
    objects = project["objects"]
    target = objects.pop(UPSTREAM_TARGET)
    target_id = identifier("OctronTelegram-target")
    objects[target_id] = target
    assert target["name"] == "Telegram"
    assert target["productType"] == "com.apple.product-type.application"
    root = objects.pop(project["rootObject"])
    project["rootObject"] = identifier("OctronTelegram-project")
    objects[project["rootObject"]] = root
    root["targets"] = [target_id]
    root["projectDirPath"] = ""
    objects[root["mainGroup"]].update({"path": str(ROOT), "sourceTree": "<absolute>"})
    for item in objects.values():
        if item.get("sourceTree") == "SOURCE_ROOT":
            item["path"] = str(ROOT / item.get("path", ""))
            item["sourceTree"] = "<absolute>"
        if item.get("isa") == "XCLocalSwiftPackageReference":
            item["relativePath"] = os.path.relpath(ROOT / item["relativePath"], OUTPUT)
    target["name"] = "OctronTelegram"
    target["productType"] = "com.apple.product-type.framework"
    target["productName"] = "Telegram"
    target["dependencies"] = []
    product = objects[target["productReference"]]
    product["path"] = "Telegram.framework"
    product["explicitFileType"] = "wrapper.framework"

    excluded_products = {"FirebaseAnalytics", "FirebaseCrashlytics"}
    target["packageProductDependencies"] = [
        key for key in target["packageProductDependencies"]
        if objects[key]["productName"] not in excluded_products
    ]
    root["packageReferences"] = [
        key for key in root["packageReferences"]
        if "firebase" not in objects[key].get("repositoryURL", "").lower()
        and "GoogleAppMeasurement" not in objects[key].get("repositoryURL", "")
    ]

    def retained_file(key):
        item = objects[key]
        reference = objects.get(item.get("fileRef", ""), {})
        package = objects.get(item.get("productRef", ""), {})
        name = reference.get("path", reference.get("name", ""))
        return (Path(name).name not in {
            "Sparkle.framework", "MainMenu.xib", "dsa_pub_prod.pem",
            "AppUpdateViewController.swift", "CheckAppStoreUpdate.swift",
        } and package.get("productName") not in excluded_products)

    phases = []
    for key in target["buildPhases"]:
        phase = objects[key]
        if phase["isa"] in {
            "PBXSourcesBuildPhase", "PBXResourcesBuildPhase", "PBXFrameworksBuildPhase",
        }:
            phase["files"] = [item for item in phase["files"] if retained_file(item)]
            phases.append(key)
    assert len(phases) == 3
    target["buildPhases"] = phases
    add_host_files(objects, target)
    configure_build_settings(objects, target)

    OUTPUT.mkdir(parents=True, exist_ok=True)
    project_path = OUTPUT / "OctronTelegram.xcodeproj"
    project_path.mkdir(exist_ok=True)
    (project_path / "project.pbxproj").write_bytes(plistlib.dumps(project))
    write_workspace(project_path, target_id)


def add_host_files(objects, target):
    header = identifier("OctronTelegram.h")
    build_header = identifier("OctronTelegram.h-build")
    headers_phase = identifier("OctronTelegram-headers")
    assert all(key not in objects for key in [header, build_header, headers_phase])
    objects[header] = {
        "isa": "PBXFileReference", "lastKnownFileType": "sourcecode.c.h",
        "path": str(ROOT / "OctronTelegram" / "OctronTelegram.h"),
        "sourceTree": "<absolute>",
    }
    objects[build_header] = {"isa": "PBXBuildFile", "fileRef": header,
                             "settings": {"ATTRIBUTES": ["Public"]}}
    objects[headers_phase] = {
        "isa": "PBXHeadersBuildPhase", "buildActionMask": 2147483647,
        "files": [build_header], "runOnlyForDeploymentPostprocessing": 0,
    }
    target["buildPhases"].insert(0, headers_phase)
    umbrella = identifier("Telegram.h")
    build_umbrella = identifier("Telegram.h-build")
    assert umbrella not in objects and build_umbrella not in objects
    objects[umbrella] = {
        "isa": "PBXFileReference", "lastKnownFileType": "sourcecode.c.h",
        "path": str(ROOT / "OctronTelegram" / "Telegram.h"), "sourceTree": "<absolute>",
    }
    objects[build_umbrella] = {
        "isa": "PBXBuildFile", "fileRef": umbrella,
        "settings": {"ATTRIBUTES": ["Public"]},
    }
    objects[headers_phase]["files"].append(build_umbrella)


def configure_build_settings(objects, target):
    for key in objects[target["buildConfigurationList"]]["buildConfigurations"]:
        settings = objects[key]["buildSettings"]
        for name in ["INFOPLIST_FILE", "CODE_SIGN_ENTITLEMENTS",
                     "ASSETCATALOG_COMPILER_APPICON_NAME", "SWIFT_OBJC_BRIDGING_HEADER"]:
            settings.pop(name, None)
        settings.update({
            "SRCROOT": str(ROOT), "PROJECT_DIR": str(ROOT),
            "PRODUCT_NAME": "Telegram", "PRODUCT_MODULE_NAME": "Telegram",
            "PRODUCT_BUNDLE_IDENTIFIER": "io.quattrobit.octron.telegram",
            "GENERATE_INFOPLIST_FILE": "YES", "DEFINES_MODULE": "YES",
            "MODULEMAP_FILE": str(ROOT / "OctronTelegram" / "module.modulemap"),
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) OCTRON_EMBEDDED",
            "SWIFT_INSTALL_OBJC_HEADER": "NO", "ENABLE_DEBUG_DYLIB": "NO",
            "SKIP_INSTALL": "NO", "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES": "NO",
            "MACH_O_TYPE": "mh_dylib", "DYLIB_COMPATIBILITY_VERSION": "1",
            "DYLIB_CURRENT_VERSION": "1", "INSTALL_PATH": "$(LOCAL_LIBRARY_DIR)/Frameworks",
            "LD_DYLIB_INSTALL_NAME": "@rpath/$(EXECUTABLE_PATH)",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@loader_path/../../..", "/usr/lib/swift"],
        })


def write_workspace(project_path, target_id):
    schemes = project_path / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    (schemes / "OctronTelegram.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="Telegram.framework" BlueprintName="OctronTelegram" ReferencedContainer="container:OctronTelegram.xcodeproj"/>
      </BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
</Scheme>
''')
    workspace = OUTPUT / "OctronTelegram.xcworkspace"
    workspace.mkdir(exist_ok=True)
    references = [
        "absolute:" + str(project_path),
        "absolute:" + str(ROOT / "submodules/CodeSyntax/CodeSyntax/CodeSyntax.xcodeproj"),
        "absolute:" + str(ROOT / "submodules/RLottie_Xcode/RLottie_Xcode.xcodeproj"),
    ]
    files = "\n".join('  <FileRef location="' + escape(path, {'"': "&quot;"}) + '"/>'
                      for path in references)
    (workspace / "contents.xcworkspacedata").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0">\n'
        + files + "\n</Workspace>\n")


if __name__ == "__main__":
    configure()
