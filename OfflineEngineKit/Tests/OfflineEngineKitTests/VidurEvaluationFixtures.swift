import Foundation
@testable import OfflineEngineKit

/// Four synthetic meetings (English, Hindi/Hinglish in Devanagari) used to measure Vidur's instant tiers.
/// "Today" is Friday 21 November 2025, 10:00 UTC. Weeks start on Monday.
enum VidurEvalFixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        return calendar.date(from: parts)!
    }

    static let now = date(2025, 11, 21, 10)
    static let selfNames = ["Neha Sharma"]

    static let hiringID = UUID()
    static let launchID = UUID()
    static let weeklyID = UUID()
    static let designID = UUID()

    /// 4 Nov, English. Older than two weeks.
    static var hiringReview: VidurMeetingRecord {
        VidurMeetingRecord(
            id: hiringID, title: "Hiring review", date: date(2025, 11, 4), duration: 1_800,
            attendees: ["Neha Sharma", "Arjun Mehta"], attendanceRecorded: true,
            agenda: ["Backend openings"],
            summary: "The team agreed to open two backend roles next quarter.",
            decisions: [VidurMeetingLine(text: "Hire two backend engineers in Q1", timestamp: 200,
                                         quote: "We should hire two backend engineers next quarter", speaker: "Arjun Mehta")],
            tasks: [
                VidurMeetingTask(title: "Post the backend job description", owner: "Arjun Mehta",
                                 dueDate: date(2025, 11, 7, 17), timestamp: 230),
                VidurMeetingTask(title: "Schedule interviews", owner: "Neha Sharma", isCompleted: true, timestamp: 250)
            ],
            turns: [
                VidurMeetingTurn(text: "Let's talk about the openings.", start: 180, speaker: "Neha Sharma"),
                VidurMeetingTurn(text: "We should hire two backend engineers next quarter, the salary range is fixed.",
                                 start: 200, speaker: "Arjun Mehta"),
                VidurMeetingTurn(text: "Arjun, please post the job description this week.", start: 230, speaker: "Neha Sharma")
            ])
    }

    /// 10 Nov (last week), English.
    static var launchReadiness: VidurMeetingRecord {
        VidurMeetingRecord(
            id: launchID, title: "Launch readiness", date: date(2025, 11, 10), duration: 2_400,
            attendees: ["Neha Sharma", "Pawan Kumar", "Maya Rao"], absent: ["Arjun Mehta"], attendanceRecorded: true,
            agenda: ["Launch date", "Vendor selection", "Budget"],
            summary: "The team fixed the launch date for 20 November and picked the Pune vendor. Budget approval is still pending.",
            discussion: ["Launch checklist owners were agreed", "Marketing budget needs a number"],
            decisions: [
                VidurMeetingLine(text: "Launch on 20 November", timestamp: 95, quote: "we launch on 20 November", speaker: "Neha Sharma"),
                VidurMeetingLine(text: "Go with the Pune vendor", timestamp: 140, quote: "let's go with the Pune vendor", speaker: "Pawan Kumar")
            ],
            openIssues: [VidurMeetingLine(text: "Budget for marketing is not decided", timestamp: 300,
                                          quote: "the marketing budget is still not decided", speaker: "Maya Rao")],
            tasks: [
                VidurMeetingTask(title: "Prepare the agenda", owner: "Pawan Kumar", dueDate: date(2025, 11, 14, 17), timestamp: 330),
                VidurMeetingTask(title: "Send the presentation to the client", owner: "Neha Sharma",
                                 dueDate: date(2025, 11, 21, 12), timestamp: 335),
                VidurMeetingTask(title: "Share the launch checklist", owner: "Maya Rao", dueDate: date(2025, 11, 24, 9), timestamp: 340),
                VidurMeetingTask(title: "Book the launch venue", owner: "Pawan Kumar", isCompleted: true, timestamp: 345)
            ],
            turns: [
                VidurMeetingTurn(text: "Hi everyone, let's start. Today we need to fix the launch date, pick a vendor and discuss the budget.",
                                 start: 0, speaker: "Neha Sharma"),
                VidurMeetingTurn(text: "I think the Pune vendor is better and their price is also lower.", start: 20, speaker: "Pawan Kumar"),
                VidurMeetingTurn(text: "Okay, we launch on 20 November. That is final.", start: 95, speaker: "Neha Sharma"),
                VidurMeetingTurn(text: "Agreed, let's go with the Pune vendor.", start: 140, speaker: "Pawan Kumar"),
                VidurMeetingTurn(text: "The marketing budget is still not decided, we need a number from finance.", start: 300, speaker: "Maya Rao"),
                VidurMeetingTurn(text: "Pawan, please prepare the agenda by Friday. I will send the presentation to the client.",
                                 start: 330, speaker: "Neha Sharma"),
                VidurMeetingTurn(text: "We will meet again next Monday to review the budget.", start: 360, speaker: "Pawan Kumar")
            ])
    }

    /// 19 Nov, Hindi and Hinglish, mostly in Devanagari.
    static var weeklySync: VidurMeetingRecord {
        VidurMeetingRecord(
            id: weeklyID, title: "Weekly sync", date: date(2025, 11, 19), duration: 900,
            attendees: ["Neha Sharma", "Pawan Kumar", "Arjun Mehta"], absent: ["Maya Rao"], attendanceRecorded: true,
            summary: "वेंडर पेमेंट और बजट पर चर्चा हुई। प्राइसिंग पेज शुक्रवार तक लाइव होगा।",
            discussion: ["इनवॉइस चेक करना बाकी है"],
            decisions: [VidurMeetingLine(text: "वेंडर पेमेंट शुक्रवार तक क्लियर होगा", timestamp: 60,
                                         quote: "वेंडर पेमेंट शुक्रवार तक क्लियर करना है", speaker: "नेहा")],
            openIssues: [VidurMeetingLine(text: "बजट अभी तय नहीं हुआ", timestamp: 75,
                                          quote: "बजट अभी तय नहीं हुआ है", speaker: "Neha Sharma")],
            tasks: [
                VidurMeetingTask(title: "वेंडर पेमेंट क्लियर करना", owner: "पवन", dueDate: date(2025, 11, 21, 17), timestamp: 30,
                                 quote: "वेंडर पेमेंट शुक्रवार तक क्लियर करना है"),
                VidurMeetingTask(title: "Send pricing page copy", owner: "Neha Sharma", dueText: "kal tak", timestamp: 120),
                VidurMeetingTask(title: "Update the invoice tracker", owner: "Arjun Mehta", dueDate: date(2025, 11, 26, 9), timestamp: 130)
            ],
            turns: [
                VidurMeetingTurn(text: "आज का एजेंडा वेंडर पेमेंट, बजट और प्राइसिंग पेज है।", start: 0, speaker: "Neha Sharma"),
                VidurMeetingTurn(text: "वेंडर पेमेंट शुक्रवार तक क्लियर करना है। इनवॉइस भी चेक करना होगा।", start: 30, speaker: "Pawan Kumar"),
                VidurMeetingTurn(text: "बजट अभी तय नहीं हुआ है, अगली मीटिंग में बात करेंगे।", start: 75, speaker: "Neha Sharma"),
                VidurMeetingTurn(text: "Pricing page ka copy main kal tak bhej dunga.", start: 120, speaker: "Arjun Mehta")
            ])
    }

    /// 20 Nov (yesterday), English. The last meeting.
    static var designReview: VidurMeetingRecord {
        VidurMeetingRecord(
            id: designID, title: "Design review", date: date(2025, 11, 20), duration: 1_390,
            attendees: ["Maya Rao", "Neha Sharma"], attendanceRecorded: true,
            summary: "Reviewed the new onboarding design; two changes requested.",
            decisions: [VidurMeetingLine(text: "Ship the simplified onboarding screen", timestamp: 40,
                                         quote: "let's ship the simplified onboarding screen", speaker: "Maya Rao")],
            tasks: [VidurMeetingTask(title: "Revise onboarding screen copy", owner: "Maya Rao", dueDate: date(2025, 11, 25, 9), timestamp: 10,
                                     quote: "I will revise the onboarding copy by Tuesday")],
            turns: [
                VidurMeetingTurn(text: "I will revise the onboarding copy by Tuesday.", start: 10, speaker: "Maya Rao"),
                VidurMeetingTurn(text: "The new design looks cleaner, let's ship the simplified onboarding screen.", start: 40, speaker: "Neha Sharma")
            ])
    }

    static var all: [VidurMeetingRecord] { [designReview, hiringReview, weeklySync, launchReadiness] }
}

/// One question with what a correct answer must contain.
struct VidurEvalCase {
    let id: String
    let question: String
    var history: [VidurChatTurn] = []
    /// Every one of these must appear in the answer text (case-insensitive).
    var contains: [String] = []
    /// At least one of these must appear.
    var containsAny: [String] = []
    var excludes: [String] = []
    var confidences: Set<VidurQuickConfidenceExpectation> = [.complete, .partial]
    var sourceMeetings: [String] = []
    var people: [String] = []
    var intent: VidurQuickIntent?
    var needsSource = true
}

enum VidurQuickConfidenceExpectation: Hashable {
    case complete, partial, notFound

    init(_ value: VidurQuickConfidence) {
        switch value {
        case .complete: self = .complete
        case .partial: self = .partial
        case .notFound: self = .notFound
        }
    }
}

enum VidurEvalCases {
    static var all: [VidurEvalCase] {
        let promiseHistory = [VidurChatTurn(question: "What did Pawan promise last week?", answer: "Pawan Kumar has 1 open task from last week.")]
        let decideHistory = [VidurChatTurn(question: "What did we decide about the vendor?", answer: "1 decision in Launch readiness.")]
        return [
            VidurEvalCase(id: "decide-all", question: "What did we decide?",
                          contains: ["5 decisions across 4 meetings", "Pune vendor", "onboarding"],
                          confidences: [.complete], sourceMeetings: ["Launch readiness", "Design review"], intent: .decisions),
            VidurEvalCase(id: "decide-last-meeting", question: "What did we decide in the last meeting?",
                          contains: ["1 decision in Design review", "simplified onboarding screen"],
                          excludes: ["Pune"], confidences: [.complete], sourceMeetings: ["Design review"], intent: .decisions),
            VidurEvalCase(id: "decide-launch", question: "What did we decide on launch?",
                          contains: ["Launch on 20 November"], excludes: ["onboarding"], confidences: [.complete],
                          sourceMeetings: ["Launch readiness"], intent: .decisions),
            VidurEvalCase(id: "person-promise-last-week", question: "What did Pawan promise last week?",
                          contains: ["Pawan Kumar has 1 open task", "last week", "Prepare the agenda"],
                          excludes: ["vendor payment"], confidences: [.complete], sourceMeetings: ["Launch readiness"],
                          people: ["Pawan Kumar"], intent: .tasks),
            VidurEvalCase(id: "person-owes-me", question: "What does Maya owe me?",
                          contains: ["Maya Rao has 2 open tasks", "Share the launch checklist", "Revise onboarding screen copy"],
                          confidences: [.complete], people: ["Maya Rao"], intent: .tasks),
            VidurEvalCase(id: "my-tasks", question: "What are my tasks?",
                          contains: ["You have 2 open tasks", "Send the presentation to the client", "Send pricing page copy"],
                          excludes: ["Schedule interviews"], confidences: [.complete], intent: .tasks),
            VidurEvalCase(id: "due-this-week", question: "Which tasks are due this week?",
                          contains: ["2 open tasks due this week", "Send the presentation to the client", "वेंडर पेमेंट क्लियर करना"],
                          excludes: ["Share the launch checklist"], confidences: [.complete], intent: .tasks),
            VidurEvalCase(id: "overdue", question: "Any overdue tasks?",
                          contains: ["2 overdue tasks", "Prepare the agenda", "Post the backend job description"],
                          confidences: [.complete], intent: .tasks),
            VidurEvalCase(id: "open-tasks", question: "Open tasks",
                          contains: ["8 open tasks", "and 2 more"], confidences: [.complete], intent: .tasks),
            VidurEvalCase(id: "pending-for-person", question: "What is pending for Arjun?",
                          contains: ["Arjun Mehta has 2 open tasks", "Update the invoice tracker", "Post the backend job description"],
                          confidences: [.complete], people: ["Arjun Mehta"], intent: .tasks),
            VidurEvalCase(id: "hinglish-person-tasks", question: "Pawan ka kaam kya hai?",
                          contains: ["Pawan Kumar has 2 open tasks", "Prepare the agenda", "वेंडर पेमेंट क्लियर करना"],
                          confidences: [.complete], people: ["Pawan Kumar"], intent: .tasks),
            VidurEvalCase(id: "hinglish-neha-tasks", question: "Neha ka kaam kya hai?",
                          contains: ["Neha Sharma has 2 open tasks", "Send the presentation to the client"],
                          confidences: [.complete], intent: .tasks),
            VidurEvalCase(id: "hinglish-deadline-topic", question: "Pawan ka vendor payment kab tak clear karna hai?",
                          contains: ["Pawan Kumar has 1 task with a due date", "वेंडर पेमेंट क्लियर करना", "21 Nov"],
                          excludes: ["Prepare the agenda"], confidences: [.complete], intent: .tasks),
            VidurEvalCase(id: "hinglish-last-decision", question: "Pichli meeting mein kya tay hua?",
                          contains: ["Ship the simplified onboarding screen"], confidences: [.complete],
                          sourceMeetings: ["Design review"], intent: .decisions),
            VidurEvalCase(id: "decisions-by-person", question: "What did Neha decide?",
                          contains: ["2 decisions across 2 meetings involving Neha Sharma", "Launch on 20 November", "वेंडर पेमेंट"],
                          confidences: [.complete], intent: .decisions),
            VidurEvalCase(id: "decisions-count-last-week", question: "How many decisions were made last week?",
                          contains: ["2 decisions in Launch readiness"], confidences: [.complete], intent: .decisions),
            VidurEvalCase(id: "open-issues", question: "Which open issues are there?",
                          contains: ["2 open issues across 2 meetings", "Budget for marketing is not decided"],
                          confidences: [.complete], intent: .openIssues),
            VidurEvalCase(id: "who-raised-concern", question: "Who raised the budget concern?",
                          contains: ["Budget for marketing is not decided"], confidences: [.complete],
                          people: ["Maya Rao"], intent: .openIssues),
            VidurEvalCase(id: "attended-last-meeting", question: "Who attended the last meeting?",
                          contains: ["Design review", "Present (2)", "Maya Rao", "Neha Sharma"], confidences: [.complete],
                          intent: .attendees),
            VidurEvalCase(id: "absent-named-meeting", question: "Who was absent from Launch readiness?",
                          contains: ["Absent (1): Arjun Mehta"], excludes: ["Present"], confidences: [.complete], intent: .absent),
            VidurEvalCase(id: "attended-and-absent", question: "Who attended and who was absent from Launch readiness?",
                          contains: ["Present (3)", "Absent (1): Arjun Mehta"], confidences: [.complete], intent: .attendees),
            VidurEvalCase(id: "was-person-present", question: "Was Pawan present in the Weekly sync?",
                          contains: ["Yes, Pawan Kumar was at Weekly sync"], confidences: [.complete], intent: .attendees),
            VidurEvalCase(id: "agenda", question: "What was on the agenda for Launch readiness?",
                          contains: ["Vendor selection", "Launch date"], confidences: [.complete], intent: .agenda),
            VidurEvalCase(id: "summary-this-week", question: "Summarize this week",
                          contains: ["2 meetings this week", "Weekly sync", "Design review"], confidences: [.complete], intent: .summary),
            VidurEvalCase(id: "summary-last-meeting", question: "Summarize the last meeting",
                          contains: ["Design review", "Reviewed the new onboarding design"], confidences: [.complete],
                          sourceMeetings: ["Design review"], intent: .summary),
            VidurEvalCase(id: "last-meeting-about", question: "What was the last meeting about?",
                          contains: ["Design review", "onboarding"], confidences: [.complete], intent: .summary),
            VidurEvalCase(id: "summary-named", question: "Summarize Weekly sync",
                          contains: ["Weekly sync (19 Nov)"], confidences: [.complete], sourceMeetings: ["Weekly sync"], intent: .summary),
            VidurEvalCase(id: "next-meeting", question: "When is the next meeting?",
                          contains: ["No date for the next meeting is recorded", "Weekly sync", "Neha Sharma said"],
                          confidences: [.partial], sourceMeetings: ["Weekly sync"], intent: .nextMeeting),
            VidurEvalCase(id: "duration", question: "How long was the last meeting?",
                          contains: ["Design review", "23 min 10 s"], confidences: [.complete], intent: .duration, needsSource: false),
            VidurEvalCase(id: "meeting-date", question: "When was the Launch readiness meeting?",
                          contains: ["Monday 10 November 2025"], confidences: [.complete], intent: .date, needsSource: false),
            VidurEvalCase(id: "meeting-count", question: "How many meetings did we have this week?",
                          contains: ["2 meetings this week", "Weekly sync", "Design review"], confidences: [.complete],
                          intent: .meetingList, needsSource: false),
            VidurEvalCase(id: "person-said-topic", question: "What did Pawan say about the vendor?",
                          contains: ["Pawan Kumar said about vendor"], confidences: [.complete, .partial],
                          sourceMeetings: ["Launch readiness"], people: ["Pawan Kumar"], intent: .topic),
            VidurEvalCase(id: "hinglish-person-said-topic", question: "Pawan ne vendor ke baare mein kya kaha?",
                          contains: ["Pawan Kumar said about vendor"], sourceMeetings: ["Launch readiness"], intent: .topic),
            VidurEvalCase(id: "devanagari-question", question: "वेंडर पेमेंट का क्या हुआ?",
                          containsAny: ["वेंडर पेमेंट"], sourceMeetings: ["Weekly sync"], intent: .topic),
            VidurEvalCase(id: "budget-approved", question: "Was the budget approved?",
                          containsAny: ["not decided", "तय नहीं", "pending"], intent: .topic),
            VidurEvalCase(id: "discussed-pricing", question: "What did we discuss about pricing?",
                          contains: ["pricing"], sourceMeetings: ["Weekly sync"], intent: .topic),
            VidurEvalCase(id: "discussed-pune-vendor", question: "What was discussed about the Pune vendor?",
                          contains: ["Pune vendor"], sourceMeetings: ["Launch readiness"], intent: .topic),
            VidurEvalCase(id: "person-hiring", question: "What did Arjun say about hiring?",
                          contains: ["Arjun Mehta said about hiring", "backend engineers"], sourceMeetings: ["Hiring review"],
                          people: ["Arjun Mehta"], intent: .topic),
            VidurEvalCase(id: "who-said", question: "Who said we should hire backend engineers?",
                          contains: ["Arjun Mehta"], sourceMeetings: ["Hiring review"], intent: .topic),
            VidurEvalCase(id: "follow-up-person", question: "and Neha?", history: promiseHistory,
                          contains: ["Neha Sharma has 1 open task from last week", "Send the presentation to the client"],
                          confidences: [.complete], people: ["Neha Sharma"], intent: .tasks),
            VidurEvalCase(id: "follow-up-topic", question: "what about the budget?", history: decideHistory,
                          containsAny: ["not decided", "तय नहीं", "pending"], intent: .topic),
            VidurEvalCase(id: "not-found-decision", question: "What did we decide about the Mars rover?",
                          contains: ["mars rover"], confidences: [.notFound], needsSource: false),
            VidurEvalCase(id: "not-found-why", question: "Why did the Mars rover launch fail?",
                          contains: ["couldn\u{2019}t find anything about"], confidences: [.notFound], needsSource: false)
        ]
    }
}
