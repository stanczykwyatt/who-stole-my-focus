import Foundation
import Testing
@testable import FocusCore

@Suite("CSV")
struct CSVExportTests {
    let utc = TimeZone(identifier: "UTC")!

    @Test func headerAndOneRow() {
        var event = Fixture.event(Fixture.updater, at: 0, from: Fixture.xcode, heldFor: 2.04)
        event.input = Fixture.typed(0.15)
        event.cause = .typing
        let lines = CSVExport.csv([event], timeZone: utc).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[0] == "Time,App,Part Of,Bundle ID,Path,Took Focus From,What Happened,Why,Seconds Since Input,Seconds In Front")
        #expect(lines[1] == "2027-01-15T08:00:00Z,SyncHelper,CloudSync,com.example.sync.helper,/Applications/CloudSync.app/Contents/Library/LoginItems/SyncHelper.app,Xcode,Stole focus,typing,0.1,2.0")
        #expect(lines.count == 3 && lines[2].isEmpty)
    }

    @Test func timesCarryTheirOffset() {
        let central = TimeZone(identifier: "America/Chicago")!
        let csv = CSVExport.csv([Fixture.event(Fixture.updater, at: 0)], timeZone: central)
        #expect(csv.contains("2027-01-15T02:00:00-06:00"))
    }

    @Test func missingValuesAreEmpty() {
        let app = AppInfo(name: "Bare")
        let event = FocusEvent(date: Fixture.start, app: app, pid: 1, previous: nil, input: Fixture.idle, cause: .none, verdict: .stole)
        let row = CSVExport.csv([event], timeZone: utc).split(separator: "\n")[1]
        #expect(row == "2027-01-15T08:00:00Z,Bare,,,,,Stole focus,none,60.0,")
    }

    @Test func quotesFieldsThatNeedIt() {
        #expect(CSVExport.field("plain") == "plain")
        #expect(CSVExport.field("a,b") == "\"a,b\"")
        #expect(CSVExport.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSVExport.field("two\nlines") == "\"two\nlines\"")
        #expect(CSVExport.field("windows\r\nline") == "\"windows\r\nline\"")
        #expect(CSVExport.field(" padded ") == "\" padded \"")
        #expect(CSVExport.field("") == "")
    }

    @Test func namesThatLookLikeFormulasOpenAsText() {
        #expect(CSVExport.field("=HYPERLINK(\"x\")") == "\"'=HYPERLINK(\"\"x\"\")\"")
        #expect(CSVExport.field("+1") == "'+1")
        #expect(CSVExport.field("-cmd") == "'-cmd")
        #expect(CSVExport.field("@sum") == "'@sum")
        #expect(CSVExport.field("\tTab") == "'\tTab")
        #expect(CSVExport.field("Safe=") == "Safe=")
    }

    @Test func homeFolderIsShortenedInPaths() {
        let event = Fixture.event(AppInfo(name: "Tool", path: "/Users/sam/Applications/Tool.app"), at: 0)
        #expect(CSVExport.csv([event], timeZone: utc, home: "/Users/sam").contains(",~/Applications/Tool.app,"))
    }

    @Test func emptyLogIsJustTheHeader() {
        #expect(CSVExport.csv([]) == CSVExport.header.joined(separator: ",") + "\n")
    }
}
