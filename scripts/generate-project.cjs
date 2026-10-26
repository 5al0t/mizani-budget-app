// Deterministic Xcode project generation, runnable on Windows or macOS. No dependencies.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
let sequence = 0;
const id = () => (++sequence).toString(16).toUpperCase().padStart(24, '0');
const quote = s => '"' + String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
const objects = [];
const add = (key, body) => objects.push(`\t\t${key} = { ${body} };`);
const project = id(), group = id(), appGroup = id(), testGroup = id(), products = id();
const appTarget = id(), testTarget = id(), appProduct = id(), testProduct = id();
const appSources = id(), appResources = id(), appFrameworks = id(), testSources = id(), testResources = id(), testFrameworks = id();
const proxy = id(), dependency = id();
const walk = folder => fs.readdirSync(folder, { withFileTypes: true }).flatMap(e => e.isDirectory() ? walk(path.join(folder, e.name)) : [path.join(folder, e.name)]).sort();
const swiftFiles = walk(path.join(root, 'Mizani')).filter(f => f.endsWith('.swift')).map(f => path.relative(path.join(root, 'Mizani'), f).replaceAll('\\', '/'));
const testFiles = walk(path.join(root, 'MizaniTests')).filter(f => f.endsWith('.swift')).map(f => path.basename(f));
const appChildren = [], testChildren = [], sources = [], resources = [], tests = [];
function file(name, type, children, builds) {
  const ref = id(); children.push(ref);
  add(ref, `isa = PBXFileReference; lastKnownFileType = ${quote(type)}; path = ${quote(name)}; sourceTree = "<group>";`);
  if (builds) { const build = id(); builds.push(build); add(build, `isa = PBXBuildFile; fileRef = ${ref};`); }
}
swiftFiles.forEach(f => file(f, 'sourcecode.swift', appChildren, sources));
file('Info.plist', 'text.plist.xml', appChildren);
file('Resources/core.js', 'sourcecode.javascript', appChildren, resources);
file('Resources/PrivacyInfo.xcprivacy', 'text.xml', appChildren, resources);
file('Resources/Assets.xcassets', 'folder.assetcatalog', appChildren, resources);
testFiles.forEach(f => file(f, 'sourcecode.swift', testChildren, tests));
add(appProduct, 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Mizani.app; sourceTree = BUILT_PRODUCTS_DIR;');
add(testProduct, 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = MizaniTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;');
const list = values => '(' + values.map(v => v + ',').join(' ') + ')';
add(group, `isa = PBXGroup; children = ${list([appGroup, testGroup, products])}; sourceTree = "<group>";`);
add(appGroup, `isa = PBXGroup; children = ${list(appChildren)}; path = Mizani; sourceTree = "<group>";`);
add(testGroup, `isa = PBXGroup; children = ${list(testChildren)}; path = MizaniTests; sourceTree = "<group>";`);
add(products, `isa = PBXGroup; children = ${list([appProduct, testProduct])}; name = Products; sourceTree = "<group>";`);
for (const [key, type, files] of [[appSources, 'PBXSourcesBuildPhase', sources], [appResources, 'PBXResourcesBuildPhase', resources], [appFrameworks, 'PBXFrameworksBuildPhase', []], [testSources, 'PBXSourcesBuildPhase', tests], [testResources, 'PBXResourcesBuildPhase', []], [testFrameworks, 'PBXFrameworksBuildPhase', []]])
  add(key, `isa = ${type}; buildActionMask = 2147483647; files = ${list(files)}; runOnlyForDeploymentPostprocessing = 0;`);
const configs = (settings, debugExtra = '') => {
  const debug = id(), release = id(), configList = id();
  add(debug, `isa = XCBuildConfiguration; buildSettings = { ${settings} ${debugExtra} }; name = Debug;`);
  add(release, `isa = XCBuildConfiguration; buildSettings = { ${settings} SWIFT_COMPILATION_MODE = wholemodule; SWIFT_OPTIMIZATION_LEVEL = "-O"; }; name = Release;`);
  add(configList, `isa = XCConfigurationList; buildConfigurations = ${list([debug, release])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;`);
  return configList;
};
const shared = 'SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES;';
const projectConfig = configs(shared, 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; ENABLE_TESTABILITY = YES; DEBUG_INFORMATION_FORMAT = dwarf;');
const appConfig = configs('PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = com.example.mizani; INFOPLIST_FILE = Mizani/Info.plist; GENERATE_INFOPLIST_FILE = NO; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 0.1.0; TARGETED_DEVICE_FAMILY = 1; CODE_SIGN_STYLE = Automatic; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks"); SUPPORTS_MACCATALYST = NO;', 'ENABLE_TESTABILITY = YES; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;');
const testConfig = configs('PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = com.example.mizani.tests; GENERATE_INFOPLIST_FILE = YES; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Mizani.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Mizani"; BUNDLE_LOADER = "$(TEST_HOST)"; TARGETED_DEVICE_FAMILY = 1; CODE_SIGN_STYLE = Automatic;');
add(proxy, `isa = PBXContainerItemProxy; containerPortal = ${project}; proxyType = 1; remoteGlobalIDString = ${appTarget}; remoteInfo = Mizani;`);
add(dependency, `isa = PBXTargetDependency; target = ${appTarget}; targetProxy = ${proxy};`);
add(appTarget, `isa = PBXNativeTarget; buildConfigurationList = ${appConfig}; buildPhases = ${list([appSources, appFrameworks, appResources])}; buildRules = (); dependencies = (); name = Mizani; productName = Mizani; productReference = ${appProduct}; productType = "com.apple.product-type.application";`);
add(testTarget, `isa = PBXNativeTarget; buildConfigurationList = ${testConfig}; buildPhases = ${list([testSources, testFrameworks, testResources])}; buildRules = (); dependencies = ${list([dependency])}; name = MizaniTests; productName = MizaniTests; productReference = ${testProduct}; productType = "com.apple.product-type.bundle.unit-test";`);
add(project, `isa = PBXProject; attributes = { BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = { ${appTarget} = { CreatedOnToolsVersion = 16.0; }; ${testTarget} = { CreatedOnToolsVersion = 16.0; TestTargetID = ${appTarget}; }; }; }; buildConfigurationList = ${projectConfig}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ar; hasScannedForEncodings = 0; knownRegions = (ar, en, Base); mainGroup = ${group}; productRefGroup = ${products}; projectDirPath = ""; projectRoot = ""; targets = ${list([appTarget, testTarget])};`);
const pbx = '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + objects.join('\n') + `\n\t};\n\trootObject = ${project};\n}\n`;
const scheme = `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${appTarget}" BuildableName="Mizani.app" BlueprintName="Mizani" ReferencedContainer="container:Mizani.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${testTarget}" BuildableName="MizaniTests.xctest" BlueprintName="MizaniTests" ReferencedContainer="container:Mizani.xcodeproj"/></TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${appTarget}" BuildableName="Mizani.app" BlueprintName="Mizani" ReferencedContainer="container:Mizani.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${appTarget}" BuildableName="Mizani.app" BlueprintName="Mizani" ReferencedContainer="container:Mizani.xcodeproj"/></BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>\n`;
for (const [name, content] of [['Mizani.xcodeproj/project.pbxproj', pbx], ['Mizani.xcodeproj/xcshareddata/xcschemes/Mizani.xcscheme', scheme]]) {
  const target = path.join(root, name);
  if (process.argv.includes('--check')) { if (!fs.existsSync(target) || fs.readFileSync(target, 'utf8') !== content) throw new Error('Regenerate: ' + name); }
  else { fs.mkdirSync(path.dirname(target), { recursive: true }); fs.writeFileSync(target, content); }
}
console.log(`Xcode project: ${swiftFiles.length} app source files, ${testFiles.length} test source file(s).`);
