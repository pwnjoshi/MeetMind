import XCTest
import SwiftUI
import SwiftData
@testable import MeetMind

@MainActor
final class MeetingDetailViewTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var detailVM: MeetingDetailViewModel!
    private var meeting: Meeting!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainerFactory.createInMemoryContainer()
        context = container.mainContext
        
        meeting = Meeting(title: "Architecture Strategy", duration: 1800, status: .completed)
        let summary = Summary(
            executiveSummary: "Agreed on migrating to SwiftData and Observation macro.",
            keyPoints: ["Discussed schema migrations", "Reviewed concurrency guidelines"],
            keyDecisions: ["SwiftData is chosen for persistence", "Target iOS 17+"]
        )
        meeting.summary = summary
        let action = ActionItem(title: "Complete schema migration", priority: .urgent)
        meeting.addActionItem(action)
        let seg = TranscriptSegment(text: "Hello everyone, let's begin the review.", startTime: 0.0, endTime: 4.5)
        meeting.addTranscriptSegment(seg)
        context.insert(meeting)
        
        detailVM = MeetingDetailViewModel(meeting: meeting, modelContext: context)
    }
    
    override func tearDownWithError() throws {
        detailVM = nil
        meeting = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }
    
    func test_meetingDetailView_initialization() throws {
        let view = MeetingDetailView(viewModel: detailVM)
        XCTAssertNotNil(view)
        XCTAssertEqual(view.viewModel.headerTitle, "Architecture Strategy")
        XCTAssertEqual(view.viewModel.selectedTab, .summary)
    }
    
    func test_meetingDetailHeaderView_callbacks() throws {
        var renamed = false
        var exported = false
        var askedAI = false
        var deleted = false
        let header = MeetingDetailHeaderView(
            title: "Architecture Strategy",
            durationText: "30:00",
            statusTitle: "Completed",
            onRename: { renamed = true },
            onExport: { exported = true },
            onAskAI: { askedAI = true },
            onDelete: { deleted = true }
        )
        XCTAssertNotNil(header)
        XCTAssertEqual(header.title, "Architecture Strategy")
        
        header.onRename()
        XCTAssertTrue(renamed)
        header.onExport()
        XCTAssertTrue(exported)
        header.onAskAI()
        XCTAssertTrue(askedAI)
        header.onDelete()
        XCTAssertTrue(deleted)
    }
    
    func test_meetingDetailTabBarView_selection() throws {
        var selectedTab: MeetingDetailTab = .summary
        let bar = MeetingDetailTabBarView(selectedTab: .summary) { tab in
            selectedTab = tab
        }
        XCTAssertNotNil(bar)
        XCTAssertEqual(bar.selectedTab, .summary)
        bar.onSelectTab(.transcript)
        XCTAssertEqual(selectedTab, .transcript)
    }
    
    func test_stickyAudioPlayerBar_controls() throws {
        var didToggle = false
        var soughtTime: TimeInterval = 0
        var didSkipBack = false
        var didSkipForward = false
        var didCycle = false
        
        let bar = StickyAudioPlayerBar(
            currentTime: 120,
            totalDuration: 1800,
            isPlaying: true,
            playbackRate: 1.0,
            onTogglePlayPause: { didToggle = true },
            onSeek: { soughtTime = $0 },
            onSkipBackward: { didSkipBack = true },
            onSkipForward: { didSkipForward = true },
            onCycleRate: { didCycle = true }
        )
        XCTAssertNotNil(bar)
        XCTAssertEqual(bar.currentTime, 120)
        XCTAssertEqual(bar.totalDuration, 1800)
        XCTAssertTrue(bar.isPlaying)
        
        bar.onTogglePlayPause()
        XCTAssertTrue(didToggle)
        bar.onSeek(300)
        XCTAssertEqual(soughtTime, 300)
        bar.onSkipBackward()
        XCTAssertTrue(didSkipBack)
        bar.onSkipForward()
        XCTAssertTrue(didSkipForward)
        bar.onCycleRate()
        XCTAssertTrue(didCycle)
    }
    
    func test_askAIAssistantSheet_rendering() throws {
        let citation = AICitation(timestamp: 120, formattedTimecode: "02:00", snippet: "SwiftData migration")
        let response = AIAnswerResponse(answer: "Migration completed on Friday", citations: [citation])
        let history = [("When was migration finished?", response)]
        
        var askedPrompt: String? = nil
        var soughtCitation: AICitation? = nil
        var didDismiss = false
        
        let sheet = AskAIAssistantSheet(
            history: history,
            onAsk: { askedPrompt = $0 },
            onSeekToCitation: { soughtCitation = $0 },
            onDismiss: { didDismiss = true }
        )
        XCTAssertNotNil(sheet)
        XCTAssertEqual(sheet.history.count, 1)
        
        sheet.onAsk("Next question")
        XCTAssertEqual(askedPrompt, "Next question")
        sheet.onSeekToCitation(citation)
        XCTAssertEqual(soughtCitation?.formattedTimecode, "02:00")
        sheet.onDismiss()
        XCTAssertTrue(didDismiss)
    }
    
    func test_meetingExportSheet_rendering() throws {
        var didExportPDF = false
        var didExportMD = false
        var didDismiss = false
        
        let sheet = MeetingExportSheet(
            onExportPDF: { didExportPDF = true; return Data("PDF".utf8) },
            onExportMarkdown: { didExportMD = true; return "# Markdown" },
            onExportEmailDraft: { EmailDraft(subject: "Minutes", body: "Draft") },
            onDismiss: { didDismiss = true }
        )
        XCTAssertNotNil(sheet)
        
        _ = sheet.onExportPDF()
        XCTAssertTrue(didExportPDF)
        _ = sheet.onExportMarkdown()
        XCTAssertTrue(didExportMD)
        let draft = sheet.onExportEmailDraft()
        XCTAssertEqual(draft.subject, "Minutes")
        sheet.onDismiss()
        XCTAssertTrue(didDismiss)
    }
}
