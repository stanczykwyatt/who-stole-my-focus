import Testing
@testable import FocusCore

@Suite("Apps")
struct AppInfoTests {
    @Test func keyPrefersBundleIDThenPathThenName() {
        #expect(AppInfo(name: "A", bundleID: "com.a", path: "/A.app").key == "com.a")
        #expect(AppInfo(name: "A", path: "/A.app").key == "/A.app")
        #expect(AppInfo(name: "A").key == "A")
    }

    @Test func helperInsideAnAppNamesItsApp() {
        #expect(Fixture.updater.containingAppName == "CloudSync")
        let agent = AppInfo(name: "agent", path: "/Applications/Logi Options+.app/Contents/Frameworks/agent.app")
        #expect(agent.containingAppName == "Logi Options+")
    }

    @Test func helperTwoLevelsDownNamesTheOutermostApp() {
        let helper = AppInfo(name: "Renderer", path: "/Applications/Big.app/Contents/Frameworks/Engine.app/Contents/Helpers/Renderer.app")
        #expect(helper.containingAppName == "Big")
    }

    @Test func executableInsideAnAppNamesItsApp() {
        let tool = AppInfo(name: "updater", path: "/Applications/Tool.app/Contents/MacOS/updater")
        #expect(tool.containingAppName == "Tool")
    }

    @Test func ordinaryAppsHaveNoContainer() {
        #expect(Fixture.xcode.containingAppName == nil)
        #expect(AppInfo(name: "Xcode", path: "/Applications/Xcode.app/").containingAppName == nil)
        #expect(Fixture.securityAgent.containingAppName == nil)
        #expect(AppInfo(name: "Nameless").containingAppName == nil)
    }

    @Test func extensionCaseDoesntMatter() {
        let helper = AppInfo(name: "Helper", path: "/Applications/Old.APP/Contents/Helper.app")
        #expect(helper.containingAppName == "Old")
    }

    @Test func containerWithTheSameNameIsntRepeated() {
        let helper = AppInfo(name: "Mail", path: "/Applications/Mail.app/Contents/Mail.app")
        #expect(helper.containingAppName == nil)
    }

    @Test func folderNamedDotAppIsNotAnApp() {
        let odd = AppInfo(name: "Odd", path: "/Volumes/.app/Odd.app")
        #expect(odd.containingAppName == nil)
    }
}

@Suite("System apps")
struct SystemAppsTests {
    @Test func everyEntryIsABundleIDWithADescription() {
        for (id, description) in SystemApps.descriptions {
            #expect(id.hasPrefix("com.apple."))
            // Used mid-sentence, as in "SecurityAgent is macOS asking for your password."
            #expect(!description.isEmpty)
            #expect(!description.hasSuffix("."))
        }
    }

    @Test func ignoredByDefaultAreSystemScreensWithNames() {
        #expect(SystemApps.ignoredByDefault.isSubset(of: Set(SystemApps.descriptions.keys)))
        #expect(SystemApps.ignoredByDefault == Set(SystemApps.ignoredDefaultNames.keys))
    }

    @Test func passwordPromptIsAnInterruption() {
        #expect(SystemApps.isInterruption(Fixture.securityAgent))
        #expect(!SystemApps.isInterruption(Fixture.xcode))
        #expect(!SystemApps.isInterruption(AppInfo(name: "No ID")))
    }
}
