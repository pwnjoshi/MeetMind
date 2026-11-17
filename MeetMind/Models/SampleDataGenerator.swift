import Foundation
import SwiftData

@MainActor
public final class SampleDataGenerator {
    
    public static func populateSampleData(context: ModelContext) {
        let speakers = createSampleSpeakers()
        for speaker in speakers {
            context.insert(speaker)
        }
        
        let folders = createSampleFolders()
        for folder in folders {
            context.insert(folder)
        }
        
        let tags = createSampleTags()
        for tag in tags {
            context.insert(tag)
        }
        
        let sampleFolder = folders.first
        let sampleTags: [Tag] = tags.count >= 2 ? [tags[0], tags[1]] : []
        let completedMeeting = createSampleMeeting(
            speakers: speakers,
            folder: sampleFolder,
            tags: sampleTags
        )
        context.insert(completedMeeting)
        
        let scheduledFolder = folders.count > 1 ? folders[1] : sampleFolder
        let scheduledTags: [Tag] = tags.count > 4 ? [tags[4]] : []
        let upcomingMeeting = createScheduledMeeting(
            speakers: Array(speakers.prefix(2)),
            folder: scheduledFolder,
            tags: scheduledTags
        )
        context.insert(upcomingMeeting)
        
        if let primarySpeaker = speakers.first {
            let recordingMeeting = createRecordingMeeting(
                speaker: primarySpeaker
            )
            context.insert(recordingMeeting)
        }
    }
    
    public static func createSampleSpeakers() -> [Speaker] {
        return [
            Speaker(name: "Sarah Connor", email: "sarah.connor@meetmind.ai", role: "Product Lead", avatarColorHex: "#3B82F6"),
            Speaker(name: "Alex Rivera", email: "alex.rivera@meetmind.ai", role: "Engineering Lead", avatarColorHex: "#10B981"),
            Speaker(name: "Dr. Marcus Vance", email: "marcus.vance@meetmind.ai", role: "AI Scientist", avatarColorHex: "#8B5CF6"),
            Speaker(name: "Elena Rostova", email: "elena.rostova@meetmind.ai", role: "Design Director", avatarColorHex: "#F59E0B")
        ]
    }
    
    public static func createSampleFolders() -> [Folder] {
        return [
            Folder(name: "Product & Strategy", iconName: "briefcase.fill", colorHex: "#3B82F6"),
            Folder(name: "Engineering Architecture", iconName: "cpu.fill", colorHex: "#10B981"),
            Folder(name: "Design System & UX", iconName: "paintpalette.fill", colorHex: "#8B5CF6")
        ]
    }
    
    public static func createSampleTags() -> [Tag] {
        return [
            Tag(name: "Q4 Roadmap", colorHex: "#3B82F6"),
            Tag(name: "AI Architecture", colorHex: "#8B5CF6"),
            Tag(name: "High Priority", colorHex: "#EF4444"),
            Tag(name: "Design Review", colorHex: "#F59E0B"),
            Tag(name: "Team Standup", colorHex: "#10B981")
        ]
    }
    
    public static func createSampleMeeting(
        speakers: [Speaker] = createSampleSpeakers(),
        folder: Folder? = nil,
        tags: [Tag] = []
    ) -> Meeting {
        let meeting = Meeting(
            title: "Q4 AI Strategy & Architecture Review",
            createdAt: Date().addingTimeInterval(-7200),
            duration: 2715.0, // 45m 15s
            status: .completed,
            audioFileURL: URL(fileURLWithPath: "/tmp/sample_audio_q4.m4a"),
            audioQuality: .high,
            isFavorite: true,
            templateName: "Team Standup",
            folder: folder
        )
        meeting.tags = tags
        for speaker in speakers {
            meeting.addParticipant(speaker)
        }
        
        let speaker0 = speakers.indices.contains(0) ? speakers[0] : nil
        let speaker1 = speakers.indices.contains(1) ? speakers[1] : nil
        let speaker2 = speakers.indices.contains(2) ? speakers[2] : nil
        let speaker3 = speakers.indices.contains(3) ? speakers[3] : nil
        
        // Transcripts
        let seg1 = TranscriptSegment(
            text: "Welcome everyone to our Q4 AI architecture sync. Today we're reviewing the on-device transcription engine and natural language summarizer.",
            startTime: 0.0,
            endTime: 35.0,
            confidence: 0.98,
            speaker: speaker0
        )
        let seg2 = TranscriptSegment(
            text: "Alex, how are the audio tap latency benchmarks looking with AVAudioEngine?",
            startTime: 35.0,
            endTime: 48.0,
            confidence: 0.95,
            speaker: speaker0
        )
        let seg3 = TranscriptSegment(
            text: "We benchmarked the dual-stream buffer tap at 16kHz PCM. Latency is consistently under 15ms, and AAC compression at 64kbps preserves exceptional speech intelligibility.",
            startTime: 48.0,
            endTime: 95.0,
            confidence: 0.99,
            speaker: speaker1
        )
        let seg4 = TranscriptSegment(
            text: "On the intelligence side, Apple NaturalLanguage framework sentence embeddings allow 100% offline extractive summaries without incurring cloud latency or subscription costs.",
            startTime: 95.0,
            endTime: 165.0,
            confidence: 0.96,
            speaker: speaker2
        )
        let seg5 = TranscriptSegment(
            text: "From a UX perspective, audio scrubbing with 0.75x to 2.0x playback needs instant pitch correction so voices remain clear and natural.",
            startTime: 165.0,
            endTime: 230.0,
            confidence: 0.97,
            speaker: speaker3
        )
        let seg6 = TranscriptSegment(
            text: "Agreed. Let's make sure the action items export seamlessly to iOS Reminders with priority and due date mapped.",
            startTime: 230.0,
            endTime: 290.0,
            confidence: 0.99,
            speaker: speaker1
        )
        meeting.addTranscriptSegment(seg1)
        meeting.addTranscriptSegment(seg2)
        meeting.addTranscriptSegment(seg3)
        meeting.addTranscriptSegment(seg4)
        meeting.addTranscriptSegment(seg5)
        meeting.addTranscriptSegment(seg6)
        
        // Summary
        let summary = Summary(
            executiveSummary: "The leadership team aligned on the Q4 MeetMind architectural specifications. AVAudioEngine dual-tap pipeline verified with sub-15ms latency. The group approved a dual-engine summarization strategy combining Apple NaturalLanguage offline extraction with structured LLM capability, and mandated full Reminders sync and multi-page PDF minutes export.",
            keyPoints: [
                "Dual-stream AVAudioEngine tap achieves sub-15ms input latency.",
                "Apple NaturalLanguage framework handles offline extractive summaries with zero privacy leaks.",
                "Sticky player bar integrates variable speed (0.75x–2.0x) with pitch correction and tap-to-seek.",
                "SwiftData schema establishes strict cascade deletion for child models and nullify rules for folders."
            ],
            keyDecisions: [
                "Adopt SwiftData with strict cascade deletion for child entities and nullify for folders.",
                "Standardize AAC audio at 64kbps default with 128kbps high-fidelity option.",
                "Deploy Apple NaturalLanguage rule-based parser for offline action item detection."
            ],
            generatedAt: Date().addingTimeInterval(-3600),
            modelVersion: "Apple-NaturalLanguage-Extractive-v1"
        )
        meeting.summary = summary
        
        // Action Items
        let act1 = ActionItem(
            title: "Finalize AVAudioEngine dual-stream input tap pipeline",
            taskDescription: "Ensure PCM buffer stream connects directly to SFSpeechAudioBufferRecognitionRequest and AAC file writer.",
            isCompleted: false,
            priority: .urgent,
            dueDate: Date().addingTimeInterval(86400),
            assignee: speaker1
        )
        let act2 = ActionItem(
            title: "Implement 32-bar 60Hz live waveform visualizer",
            taskDescription: "Transform RMS power levels to normalized linear dB range (-60dB to 0dB).",
            isCompleted: false,
            priority: .high,
            dueDate: Date().addingTimeInterval(172800),
            assignee: speaker3
        )
        let act3 = ActionItem(
            title: "Configure Apple Reminders EventKit synchronization",
            taskDescription: "Export meeting action items into the native iOS Reminders app with due dates.",
            isCompleted: false,
            priority: .medium,
            dueDate: Date().addingTimeInterval(259200),
            assignee: speaker1
        )
        let act4 = ActionItem(
            title: "Prepare presentation slides for executive review",
            taskDescription: "Summarize architectural milestones and latency benchmarks.",
            isCompleted: true,
            priority: .low,
            dueDate: Date().addingTimeInterval(-86400),
            completedAt: Date().addingTimeInterval(-4000),
            assignee: speaker0
        )
        meeting.addActionItem(act1)
        meeting.addActionItem(act2)
        meeting.addActionItem(act3)
        meeting.addActionItem(act4)
        
        // Notes
        let note1 = Note(
            content: "Key architecture requirement: audio buffer tap latency must remain under 20ms.",
            timestamp: 48.0,
            isBookmark: false
        )
        let note2 = Note(
            content: "Milestone approval confirmed by Sarah.",
            timestamp: 165.0,
            isBookmark: true
        )
        let note3 = Note(
            content: "Captured whiteboard diagram of dual-engine summarization flow.",
            timestamp: 230.0,
            imageAttachmentPath: "whiteboard_sample_01.jpg",
            isBookmark: false
        )
        meeting.addNote(note1)
        meeting.addNote(note2)
        meeting.addNote(note3)
        
        return meeting
    }
    
    public static func createScheduledMeeting(
        speakers: [Speaker] = createSampleSpeakers(),
        folder: Folder? = nil,
        tags: [Tag] = []
    ) -> Meeting {
        let meeting = Meeting(
            title: "Sprint 42 Planning & Estimation",
            createdAt: Date(),
            scheduledStartTime: Date().addingTimeInterval(3600), // starts in 1 hour
            duration: 0,
            status: .scheduled,
            audioFileURL: nil,
            audioQuality: .standard,
            isFavorite: false,
            templateName: "Team Standup",
            folder: folder
        )
        meeting.tags = tags
        for speaker in speakers {
            meeting.addParticipant(speaker)
        }
        return meeting
    }
    
    public static func createRecordingMeeting(
        speaker: Speaker = createSampleSpeakers()[0]
    ) -> Meeting {
        let meeting = Meeting(
            title: "Spontaneous Design Critique",
            createdAt: Date(),
            scheduledStartTime: nil,
            duration: 125.0,
            status: .recording,
            audioFileURL: URL(fileURLWithPath: "/tmp/current_recording.m4a"),
            audioQuality: .high,
            isFavorite: false,
            templateName: "Brainstorm"
        )
        meeting.addParticipant(speaker)
        return meeting
    }
}
