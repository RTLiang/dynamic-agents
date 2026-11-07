#!/usr/bin/env python3
"""Generate the dependency-free macOS app + Widget extension Xcode project."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent.parent
objects = {}

def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def obj(identifier, isa, **fields):
    key = uid(identifier)
    objects[key] = dict(isa=isa, **fields)
    return key

class Ref(str):
    pass

def ref(name):
    return Ref(uid(name))

def serialize(value, indent=0):
    if isinstance(value, Ref):
        return str(value)
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (indent + 1) + json.dumps(k) + " = " + serialize(v, indent + 1) + ";\n" for k, v in value.items()) + "\t" * indent + "}"
    if isinstance(value, list):
        return "(" + ", ".join(serialize(v, indent) for v in value) + ("," if value else "") + ")"
    return json.dumps(str(value))

app_sources = sorted(str(p.relative_to(ROOT)) for directory in ["Sources/AgentCore", "Sources/DynamicAgents"] for p in (ROOT / directory).rglob("*.swift"))
widget_sources = [
    "Sources/AgentCore/Agent.swift", "Sources/AgentCore/AgentActivityState.swift",
    "Sources/AgentCore/Localization.swift", "Sources/AgentCore/AgentHandoff.swift",
    "Sources/DynamicAgents/Shared/AgentActivityAttributes.swift",
    "Sources/DynamicAgents/Shared/ActivityPanel.swift",
    "WidgetExtension/AgentLiveActivityWidget.swift",
]
helper_sources = ["HandoffHelper/DynamicAgentsHandoff.swift", "Sources/AgentCore/AgentHandoff.swift", "Sources/AgentCore/Localization.swift", "Sources/AgentCore/Agent.swift", "Sources/AgentCore/AgentActivityState.swift", "Sources/AgentCore/AgentActivityService.swift", "Sources/DynamicAgents/Shared/AgentActivityAttributes.swift", "Sources/DynamicAgents/LiveActivityController.swift"]
all_files = sorted(set(app_sources + widget_sources + helper_sources + ["Resources/Handoff-Info.plist", "Resources/Info.plist", "Resources/Widget-Info.plist", "Resources/App.entitlements", "Resources/Widget.entitlements", "Resources/AppIcon.icon", "Sources/AgentCore/Resources/desktop-hook.py"]))
for path in all_files:
    file_type = "sourcecode.swift" if path.endswith(".swift") else ("folder.iconcomposer.icon" if path.endswith(".icon") else ("text.script.python" if path.endswith(".py") else "text.plist.xml"))
    obj(path, "PBXFileReference", lastKnownFileType=file_type, path=path, sourceTree="SOURCE_ROOT")
for name, extension, file_type in [("DynamicAgents", "app", "wrapper.application"), ("DynamicAgentsWidgets", "appex", "wrapper.app-extension"), ("DynamicAgentsHandoff", "app", "wrapper.application")]:
    obj(name + "-product", "PBXFileReference", explicitFileType=file_type, path=name + "." + extension, sourceTree="BUILT_PRODUCTS_DIR")
obj("products", "PBXGroup", children=[ref("DynamicAgents-product"), ref("DynamicAgentsWidgets-product"), ref("DynamicAgentsHandoff-product")], name="Products", sourceTree="<group>")
localized_resources = ["Localizable.strings", "Localizable.stringsdict", "InfoPlist.strings"]
for name in localized_resources:
    children = []
    for language in ["en", "zh-Hans"]:
        path = f"Sources/AgentCore/Resources/{language}.lproj/{name}"
        obj(path, "PBXFileReference", lastKnownFileType="text.plist.strings" if name.endswith(".strings") else "text.plist.stringsdict", name=language, path=path, sourceTree="SOURCE_ROOT")
        children.append(ref(path))
    obj(name, "PBXVariantGroup", children=children, name=name, sourceTree="<group>")
obj("main", "PBXGroup", children=[ref(p) for p in all_files] + [ref(p) for p in localized_resources] + [ref("products")], sourceTree="<group>")

for target, sources in [("DynamicAgents", app_sources), ("DynamicAgentsWidgets", widget_sources), ("DynamicAgentsHandoff", helper_sources)]:
    for path in sources:
        obj(target + path, "PBXBuildFile", fileRef=ref(path))
    obj(target + "-sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=[ref(target + p) for p in sources], runOnlyForDeploymentPostprocessing=0)
    obj(target + "-frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
    resources = []
    for name in localized_resources:
        obj(target + name, "PBXBuildFile", fileRef=ref(name))
        resources.append(ref(target + name))
    if target != "DynamicAgentsWidgets":
        obj(target + "-icon-build", "PBXBuildFile", fileRef=ref("Resources/AppIcon.icon"))
        resources.append(ref(target + "-icon-build"))
    if target == "DynamicAgents":
        obj("desktop-hook-resource", "PBXBuildFile", fileRef=ref("Sources/AgentCore/Resources/desktop-hook.py"))
        resources.append(ref("desktop-hook-resource"))
    obj(target + "-resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0)

obj("embed-file", "PBXBuildFile", fileRef=ref("DynamicAgentsWidgets-product"), settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
obj("embed", "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="", dstSubfolderSpec=13, files=[ref("embed-file")], name="Embed App Extensions", runOnlyForDeploymentPostprocessing=0)
obj("proxy", "PBXContainerItemProxy", containerPortal=ref("project"), proxyType=1, remoteGlobalIDString=ref("DynamicAgentsWidgets"), remoteInfo="DynamicAgentsWidgets")
obj("dependency", "PBXTargetDependency", target=ref("DynamicAgentsWidgets"), targetProxy=ref("proxy"))
obj("helper-embed-file", "PBXBuildFile", fileRef=ref("DynamicAgentsHandoff-product"), settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
obj("helper-embed", "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="Contents/Helpers", dstSubfolderSpec=1, files=[ref("helper-embed-file")], name="Embed Handoff Helper", runOnlyForDeploymentPostprocessing=0)
obj("helper-proxy", "PBXContainerItemProxy", containerPortal=ref("project"), proxyType=1, remoteGlobalIDString=ref("DynamicAgentsHandoff"), remoteInfo="DynamicAgentsHandoff")
obj("helper-dependency", "PBXTargetDependency", target=ref("DynamicAgentsHandoff"), targetProxy=ref("helper-proxy"))

for target in ["DynamicAgents", "DynamicAgentsWidgets", "DynamicAgentsHandoff"]:
    is_app = target == "DynamicAgents"
    is_extension = target == "DynamicAgentsWidgets"
    phases = [ref(target + "-sources"), ref(target + "-frameworks"), ref(target + "-resources")]
    if is_app:
        phases.append(ref("helper-embed"))
    elif not is_extension:
        phases.append(ref("embed"))
    dependencies = [ref("helper-dependency")] if is_app else [] if is_extension else [ref("dependency")]
    obj(target, "PBXNativeTarget", buildConfigurationList=ref(target + "-configs"), buildPhases=phases, buildRules=[], dependencies=dependencies, name=target, productName=target, productReference=ref(target + "-product"), productType="com.apple.product-type.app-extension" if is_extension else "com.apple.product-type.application")
    settings = {
        "PRODUCT_NAME": target,
        "PRODUCT_BUNDLE_IDENTIFIER": "dev.local.dynamicagents" + ("" if is_app else ".handoff.widgets" if is_extension else ".handoff"),
        "INFOPLIST_FILE": "Resources/Info.plist" if is_app else "Resources/Widget-Info.plist" if is_extension else "Resources/Handoff-Info.plist",
        "GENERATE_INFOPLIST_FILE": "NO", "CODE_SIGN_STYLE": "Automatic",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
        "ENABLE_HARDENED_RUNTIME": "YES",
    }
    if not is_extension:
        settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
    if is_app:
        settings["CODE_SIGN_ENTITLEMENTS"] = "Resources/App.entitlements"
    if is_extension:
        settings.update({"APPLICATION_EXTENSION_API_ONLY": "YES", "SKIP_INSTALL": "YES", "CODE_SIGN_ENTITLEMENTS": "Resources/Widget.entitlements", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) WIDGET_EXTENSION"})
    if not is_app and not is_extension:
        settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "$(inherited) ACTIVITY_SERVICE"
    for config in ["Debug", "Release"]:
        obj(target + config, "XCBuildConfiguration", buildSettings=settings, name=config)
    obj(target + "-configs", "XCConfigurationList", buildConfigurations=[ref(target + c) for c in ["Debug", "Release"]], defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

for config in ["Debug", "Release"]:
    settings = {
        "SDKROOT": "macosx", "MACOSX_DEPLOYMENT_TARGET": "27.3", "SWIFT_VERSION": "6.0",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) NATIVE_LIVE_ACTIVITIES" + (" DEBUG" if config == "Debug" else ""),
        "CLANG_ENABLE_MODULES": "YES", "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O",
        "DEBUG_INFORMATION_FORMAT": "dwarf" if config == "Debug" else "dwarf-with-dsym",
        "ONLY_ACTIVE_ARCH": "YES" if config == "Debug" else "NO",
    }
    obj("project" + config, "XCBuildConfiguration", buildSettings=settings, name=config)
obj("project-configs", "XCConfigurationList", buildConfigurations=[ref("project" + c) for c in ["Debug", "Release"]], defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
obj("project", "PBXProject", attributes={"LastUpgradeCheck": "2730"}, buildConfigurationList=ref("project-configs"), compatibilityVersion="Xcode 14.0", developmentRegion="en", knownRegions=["en", "zh-Hans", "Base"], mainGroup=ref("main"), productRefGroup=ref("products"), projectDirPath="", projectRoot="", targets=[ref("DynamicAgents"), ref("DynamicAgentsWidgets"), ref("DynamicAgentsHandoff")])
project = ROOT / "DynamicAgents.xcodeproj"
project.mkdir(exist_ok=True)
(project / "project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize(dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=ref("project"))) + "\n")
schemes = project / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
(schemes / "DynamicAgents.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2730" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('DynamicAgents')}" BuildableName="DynamicAgents.app" BlueprintName="DynamicAgents" ReferencedContainer="container:DynamicAgents.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('DynamicAgents')}" BuildableName="DynamicAgents.app" BlueprintName="DynamicAgents" ReferencedContainer="container:DynamicAgents.xcodeproj"/></BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(project)
