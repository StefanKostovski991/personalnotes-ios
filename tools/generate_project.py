#!/usr/bin/env python3
"""Generate PersonalNotes.xcodeproj for the iOS app.

XcodeGen/Tuist are not installed, and the project is small with a stable layout, so the Xcode
project is generated from this script instead of being hand-edited. That keeps it reviewable and
means adding a Swift file is followed by one command:

    python3 tools/generate_project.py

Layout:

    PersonalNotes.xcodeproj   generated
    PersonalNotes/            app target (Swift + Assets + Resources/Info.plist)
    PersonalNotesTests/       unit test bundle, hosted by the app
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = "PersonalNotes"
TEST_TARGET = "PersonalNotesTests"
BUNDLE_ID = "com.kostovskiapps.personalnotes"
DEPLOYMENT_TARGET = "17.0"

# ---------------------------------------------------------------------------
# identifiers: deterministic 24-hex ids so regenerating produces a small diff
# ---------------------------------------------------------------------------

_counter: dict[str, int] = {}


def oid(seed: str) -> str:
    _counter[seed] = _counter.get(seed, 0) + 1
    digest = 0
    for char in f"{seed}#{_counter[seed]}":
        digest = (digest * 131 + ord(char)) & 0xFFFFFFFFFFFFFFFF
    return f"{digest:024X}"


def quoted(value: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_./+$-]+", value or ""):
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def settings_block(items: list[tuple[str, str]], indent: str = "\t\t\t\t") -> str:
    return "\n".join(f"{indent}{key} = {quoted(value)};" for key, value in sorted(items))


# ---------------------------------------------------------------------------
# file discovery and grouping
# ---------------------------------------------------------------------------


class Node:
    """A directory group in the Xcode navigator."""

    def __init__(self, path: Path, group_id: str) -> None:
        self.path = path
        self.id = group_id
        self.children: list[Node] = []
        self.files: list[tuple[str, str]] = []  # (fileRefId, displayName)


def file_type(path: Path) -> str:
    return {
        ".swift": "sourcecode.swift",
        ".xcassets": "folder.assetcatalog",
        ".plist": "text.plist.xml",
        ".json": "text.json",
    }.get(path.suffix, "text")


def build_tree(root: Path, include: list[Path], refs: dict[Path, str]) -> Node:
    """Builds a group tree containing exactly the given files."""
    base = Node(root, oid(f"group:{root.name}"))
    for path in include:
        relative = path.relative_to(root)
        node = base
        for part in relative.parts[:-1]:
            found = next((c for c in node.children if c.path.name == part), None)
            if found is None:
                found = Node(node.path / part, oid(f"group:{node.path.name}/{part}"))
                node.children.append(found)
            node = found
        node.files.append((refs[path], path.name))
    return base


def render_tree(node: Node, is_root: bool, indent: str = "\t\t") -> str:
    children = list(node.children) + [None] * len(node.files)
    lines = [f"{indent}{node.id} /* {node.path.name} */ = {{", f"{indent}\tisa = PBXGroup;", f"{indent}\tchildren = ("]
    for child in node.children:
        lines.append(f"{indent}\t\t{child.id} /* {child.path.name} */,")
    for ref, name in node.files:
        lines.append(f"{indent}\t\t{ref} /* {name} */,")
    lines.append(f"{indent}\t);")
    if is_root:
        lines.append(f"{indent}\tname = {quoted(node.path.name)};")
    else:
        # Children carry only their own path component; the parent group supplies the prefix.
        lines.append(f"{indent}\tpath = {quoted(node.path.name)};")
        lines.append(f'{indent}\tsourceTree = "<group>";')
    lines.append(f"{indent}}};")
    for child in node.children:
        lines.append(render_tree(child, is_root=False, indent=indent))
    return "\n".join(filter(bool, lines))


def walk_files(node: Node) -> list[tuple[str, str]]:
    files = list(node.files)
    for child in node.children:
        files.extend(walk_files(child))
    return files


# ---------------------------------------------------------------------------
# project assembly
# ---------------------------------------------------------------------------


def scheme_xml(app_target: str, test_target: str, ui_test_target: str) -> str:
    """Shared scheme, so `xcodebuild -scheme` works from a clean checkout."""
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target}"
               BuildableName = "{APP}.app"
               BlueprintName = "{APP}"
               ReferencedContainer = "container:{APP}.xcodeproj" />
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{test_target}"
               BuildableName = "{TEST_TARGET}.xctest"
               BlueprintName = "{TEST_TARGET}"
               ReferencedContainer = "container:{APP}.xcodeproj" />
         </TestableReference>
         <TestableReference skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{ui_test_target}"
               BuildableName = "PersonalNotesUITests.xctest"
               BlueprintName = "PersonalNotesUITests"
               ReferencedContainer = "container:{APP}.xcodeproj" />
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "{APP}.app"
            BlueprintName = "{APP}"
            ReferencedContainer = "container:{APP}.xcodeproj" />
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "{APP}.app"
            BlueprintName = "{APP}"
            ReferencedContainer = "container:{APP}.xcodeproj" />
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug" />
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES" />
</Scheme>
"""


def main() -> None:
    app_root = ROOT / APP
    test_root = ROOT / TEST_TARGET

    plist = app_root / "Resources" / "Info.plist"
    plist.parent.mkdir(parents=True, exist_ok=True)
    if not plist.exists():
        raise SystemExit(f"missing {plist.relative_to(ROOT)}")

    app_files = sorted(
        p for p in app_root.rglob("*")
        if (p.is_file() or p.suffix == ".xcassets")
        and p.suffix in {".swift", ".xcassets", ".plist"}
        and not p.name.startswith(".")
        and not any(part.startswith(".") for part in p.relative_to(app_root).parts)
    )
    app_swift = [p for p in app_files if p.suffix == ".swift"]
    # Info.plist is named by INFOPLIST_FILE and processed by the build system; copying it as a
    # resource too makes two tasks write the same output.
    app_resources = [
        p for p in app_files
        if p.suffix != ".swift" and p != app_root / "Resources" / "Info.plist"
    ]
    test_swift = sorted(p for p in test_root.rglob("*.swift") if p.is_file())
    ui_test_root = ROOT / "PersonalNotesUITests"
    ui_test_swift = sorted(p for p in ui_test_root.rglob("*.swift") if p.is_file()) if ui_test_root.exists() else []
    print(f"  ui test sources: {len(ui_test_swift)}")

    if not app_swift:
        raise SystemExit("no Swift sources under PersonalNotes/")

    # One stable id per file, created up front and shared by the group tree and the build phases.
    file_refs: dict[Path, str] = {p: oid(f"fileref:{p}") for p in app_files + test_swift + ui_test_swift}
    app_tree = build_tree(app_root, app_files, file_refs)
    test_tree = build_tree(test_root, test_swift, file_refs)
    ui_test_tree = build_tree(ui_test_root, ui_test_swift, file_refs) if ui_test_swift else None

    source_builds = [(oid(f"buildfile:{p}"), file_refs[p]) for p in app_swift]
    resource_builds = [(oid(f"resbuild:{p}"), file_refs[p]) for p in app_resources]
    test_builds = [(oid(f"testbuild:{p}"), file_refs[p]) for p in test_swift]
    ui_test_builds = [(oid(f"uitestbuild:{p}"), file_refs[p]) for p in ui_test_swift]

    build_file_lines = [
        f"\t\t{b} /* {p.name} */ = {{isa = PBXBuildFile; fileRef = {file_refs[p]} /* {p.name} */; }};"
        for (b, _), p in zip(
            source_builds + resource_builds + test_builds + ui_test_builds,
            app_swift + app_resources + test_swift + ui_test_swift,
        )
    ]

    fileref_lines = [
        f"\t\t{file_refs[p]} /* {p.name} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type(p)}; path = {quoted(p.name)}; sourceTree = \"<group>\"; }};"
        for p in app_files + test_swift + ui_test_swift
    ]

    project_id = oid("project")
    app_target = oid("target:app")
    test_target = oid("target:tests")
    ui_test_target = oid("target:uitests")
    products_group = oid("group:Products")
    app_product = oid("product:app")
    test_product = oid("product:tests")
    ui_test_product = oid("product:uitests")
    sources_phase = oid("phase:sources")
    resources_phase = oid("phase:resources")
    frameworks_phase = oid("phase:frameworks")
    test_sources_phase = oid("phase:testsources")
    test_frameworks_phase = oid("phase:testframeworks")
    proxy_id = oid("proxy")
    dependency_id = oid("dependency")

    project_debug, project_release = oid("cfg:project:debug"), oid("cfg:project:release")
    app_debug, app_release = oid("cfg:app:debug"), oid("cfg:app:release")
    test_debug, test_release = oid("cfg:tests:debug"), oid("cfg:tests:release")
    project_cfg_list = oid("cfglist:project")
    app_cfg_list = oid("cfglist:app")
    test_cfg_list = oid("cfglist:tests")
    ui_test_debug, ui_test_release = oid("cfg:uitests:debug"), oid("cfg:uitests:release")
    ui_test_cfg_list = oid("cfglist:uitests")
    ui_test_sources_phase = oid("phase:uitestsources")
    ui_test_frameworks_phase = oid("phase:uitestframeworks")
    ui_test_dependency = oid("dependency:uitests")
    ui_test_proxy = oid("proxy:uitests")

    common = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": "1,2",
    }
    project_debug_settings = dict(common, **{
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    })
    project_release_settings = dict(common, **{
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_NS_ASSERTIONS": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": "-O",
        "VALIDATE_PRODUCT": "YES",
    })
    app_settings = dict(common, **{
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "2",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": f"{APP}/Resources/Info.plist",
        "MARKETING_VERSION": "1.1",
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_STRICT_CONCURRENCY": "minimal",
    })
    test_settings = dict(common, **{
        "BUNDLE_LOADER": "$(TEST_HOST)",
        "GENERATE_INFOPLIST_FILE": "YES",
        "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.tests",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "TEST_HOST": f"$(BUILT_PRODUCTS_DIR)/{APP}.app/{APP}",
    })
    ui_test_settings = dict(common, **{
        "GENERATE_INFOPLIST_FILE": "YES",
        "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.uitests",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "TEST_TARGET_NAME": APP,
    })

    def config(config_id: str, name: str, settings: dict[str, str]) -> str:
        return (
            f"\t\t{config_id} /* {name} */ = {{\n"
            f"\t\t\tisa = XCBuildConfiguration;\n"
            f"\t\t\tbuildSettings = {{\n{settings_block(list(settings.items()))}\n\t\t\t}};\n"
            f"\t\t\tname = {name};\n"
            f"\t\t}};"
        )

    def configuration_list(list_id: str, owner: str, debug: str, release: str) -> str:
        return (
            f"\t\t{list_id} /* Build configuration list for {owner} */ = {{\n"
            f"\t\t\tisa = XCConfigurationList;\n"
            f"\t\t\tbuildConfigurations = (\n"
            f"\t\t\t\t{debug} /* Debug */,\n"
            f"\t\t\t\t{release} /* Release */,\n"
            f"\t\t\t);\n"
            f"\t\t\tdefaultConfigurationIsVisible = 0;\n"
            f"\t\t\tdefaultConfigurationName = Release;\n"
            f"\t\t}};"
        )

    pbx_build_files = "\n".join(build_file_lines)
    resources_phase_files = "\n".join(
        f"\t\t\t\t{b} /* {p.name} */," for (b, _), p in zip(resource_builds, app_resources)
    )
    sources_phase_files = "\n".join(
        f"\t\t\t\t{b} /* {p.name} */," for (b, _), p in zip(source_builds, app_swift)
    )
    test_phase_files = "\n".join(
        f"\t\t\t\t{b} /* {p.name} */," for (b, _), p in zip(test_builds, test_swift)
    )
    ui_test_phase_files = "\n".join(
        f"\t\t\t\t{b} /* {p.name} */," for (b, _), p in zip(ui_test_builds, ui_test_swift)
    )
    pbx_filerefs = "\n".join(fileref_lines)
    app_group = render_tree(app_tree, is_root=False)
    test_group = render_tree(test_tree, is_root=False)
    ui_test_group = render_tree(ui_test_tree, is_root=False) if ui_test_tree else ""
    ui_test_group_ref = (
        f"\t\t\t\t{ui_test_tree.id} /* PersonalNotesUITests */,\n" if ui_test_tree else ""
    )
    root_group = oid("group:root")

    pbxproj = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{pbx_build_files}
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{proxy_id} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {project_id} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {app_target};
			remoteInfo = {APP};
		}};
		{ui_test_proxy} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {project_id} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {app_target};
			remoteInfo = {APP};
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
{pbx_filerefs}
		{app_product} /* {APP}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP}.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{test_product} /* {TEST_TARGET}.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {TEST_TARGET}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
		{ui_test_product} /* PersonalNotesUITests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = PersonalNotesUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{frameworks_phase} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{test_frameworks_phase} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ui_test_frameworks_phase} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{root_group} = {{
			isa = PBXGroup;
			children = (
				{app_tree.id} /* {APP} */,
				{test_tree.id} /* {TEST_TARGET} */,
{ui_test_group_ref}				{products_group} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{products_group} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{app_product} /* {APP}.app */,
				{test_product} /* {TEST_TARGET}.xctest */,
				{ui_test_product} /* PersonalNotesUITests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
{app_group}
{test_group}
{ui_test_group}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{app_target} /* {APP} */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {app_cfg_list} /* Build configuration list for PBXNativeTarget "{APP}" */;
			buildPhases = (
				{sources_phase} /* Sources */,
				{frameworks_phase} /* Frameworks */,
				{resources_phase} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = {APP};
			productName = {APP};
			productReference = {app_product} /* {APP}.app */;
			productType = "com.apple.product-type.application";
		}};
		{test_target} /* {TEST_TARGET} */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {test_cfg_list} /* Build configuration list for PBXNativeTarget "{TEST_TARGET}" */;
			buildPhases = (
				{test_sources_phase} /* Sources */,
				{test_frameworks_phase} /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
				{dependency_id} /* PBXTargetDependency */,
			);
			name = {TEST_TARGET};
			productName = {TEST_TARGET};
			productReference = {test_product} /* {TEST_TARGET}.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		}};
		{ui_test_target} /* PersonalNotesUITests */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {ui_test_cfg_list} /* Build configuration list for PBXNativeTarget "PersonalNotesUITests" */;
			buildPhases = (
				{ui_test_sources_phase} /* Sources */,
				{ui_test_frameworks_phase} /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
				{ui_test_dependency} /* PBXTargetDependency */,
			);
			name = PersonalNotesUITests;
			productName = PersonalNotesUITests;
			productReference = {ui_test_product} /* PersonalNotesUITests.xctest */;
			productType = "com.apple.product-type.bundle.ui-testing";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{project_id} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
				TargetAttributes = {{
					{app_target} = {{
						CreatedOnToolsVersion = 15.0;
					}};
					{test_target} = {{
						CreatedOnToolsVersion = 15.0;
						TestTargetID = {app_target};
					}};
				}};
			}};
			buildConfigurationList = {project_cfg_list} /* Build configuration list for PBXProject "{APP}" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {root_group};
			productRefGroup = {products_group} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{app_target} /* {APP} */,
				{test_target} /* {TEST_TARGET} */,
				{ui_test_target} /* PersonalNotesUITests */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{resources_phase} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{resources_phase_files}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{sources_phase} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{sources_phase_files}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{test_sources_phase} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{test_phase_files}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ui_test_sources_phase} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{ui_test_phase_files}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{dependency_id} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {app_target} /* {APP} */;
			targetProxy = {proxy_id} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
{config(project_debug, "Debug", project_debug_settings)}
{config(project_release, "Release", project_release_settings)}
{config(app_debug, "Debug", app_settings)}
{config(app_release, "Release", app_settings)}
{config(test_debug, "Debug", test_settings)}
{config(test_release, "Release", test_settings)}
{config(ui_test_debug, "Debug", ui_test_settings)}
{config(ui_test_release, "Release", ui_test_settings)}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
{configuration_list(project_cfg_list, f'PBXProject "{APP}"', project_debug, project_release)}
{configuration_list(app_cfg_list, f'PBXNativeTarget "{APP}"', app_debug, app_release)}
{configuration_list(test_cfg_list, f'PBXNativeTarget "{TEST_TARGET}"', test_debug, test_release)}
{configuration_list(ui_test_cfg_list, 'PBXNativeTarget "PersonalNotesUITests"', ui_test_debug, ui_test_release)}
/* End XCConfigurationList section */
	}};
	rootObject = {project_id} /* Project object */;
}}
"""

    project_dir = ROOT / f"{APP}.xcodeproj"
    project_dir.mkdir(exist_ok=True)
    (project_dir / "project.pbxproj").write_text(pbxproj, encoding="utf-8")

    schemes = project_dir / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    (schemes / f"{APP}.xcscheme").write_text(scheme_xml(app_target, test_target, ui_test_target), encoding="utf-8")
    print(f"wrote {project_dir.name}/project.pbxproj")
    print(f"  app sources:   {len(app_swift)}")
    print(f"  app resources: {len(app_resources)}")
    print(f"  test sources:  {len(test_swift)}")


if __name__ == "__main__":
    main()
