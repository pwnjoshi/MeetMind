import Foundation

/// Joins an English and a Hindi recognizer that hear the same audio into one caption stream.
///
/// Each recognizer reports into its own `CaptionChannelSink`, which stitches that recognizer's
/// partials and finals (so restarts never repeat words) and hands the hub finished phrases and
/// the open tail. The hub then:
/// - groups the phrases of both languages that overlap in audio time into one unit,
/// - waits until both languages have reported past the unit (or a short grace period, or the
///   other language was dropped),
/// - lets `LiveCaptionLanguageArbiter` pick the language, and commits only that language's words,
/// - shows the open (partial) text of the language that is currently winning.
/// Everything leaves through one downstream `CaptionResultSink`, whose stitcher removes
/// any remaining overlap, so no phrase is printed twice.
final class CaptionLanguageHub: @unchecked Sendable {
    private struct Phrase {
        let words: [CaptionWord]
        let start: TimeInterval
        let end: TimeInterval
        let arrival: Date

        init?(words: [CaptionWord], arrival: Date) {
            guard let first = words.first, let last = words.last else { return nil }
            self.words = words
            self.start = first.start
            self.end = max(last.end, first.start)
            self.arrival = arrival
        }
    }

    private struct Unit {
        var start: TimeInterval
        var end: TimeInterval
        var taken: [CaptionSpeechLanguage: [Int]]
    }

    /// How long a phrase waits for the other language before it is judged alone.
    private let graceSeconds: TimeInterval
    /// Audio-time lead of newer speech that also ends the wait.
    private let maximumLagSeconds: TimeInterval = 4.0
    private let coverTolerance: TimeInterval = 0.4
    private let overlapTolerance: TimeInterval = 0.15
    private let maximumUnitSeconds: TimeInterval = 25

    private let lock = NSLock()
    private let downstream: any CaptionResultSink
    private var arbiter: LiveCaptionLanguageArbiter
    private var queues: [CaptionSpeechLanguage: [Phrase]] = [.english: [], .hindi: []]
    private var opens: [CaptionSpeechLanguage: [CaptionWord]] = [.english: [], .hindi: []]
    private var committedEnd: [CaptionSpeechLanguage: TimeInterval] = [.english: 0, .hindi: 0]
    private var active: Set<CaptionSpeechLanguage>
    private var latestEnd: TimeInterval = 0
    private var frontier: TimeInterval = 0
    private var lastDisplayKey = ""

    init(downstream: any CaptionResultSink, languages: Set<CaptionSpeechLanguage> = [.english, .hindi],
         arbiter: LiveCaptionLanguageArbiter = LiveCaptionLanguageArbiter(), graceSeconds: TimeInterval = 1.6) {
        self.downstream = downstream
        self.active = languages
        self.arbiter = arbiter
        self.graceSeconds = graceSeconds
        // The hub already splits phrases; the downstream stitcher only removes overlap.
        downstream.setAutoCommit(nil)
    }

    func sink(for language: CaptionSpeechLanguage) -> CaptionChannelSink {
        CaptionChannelSink(language: language, hub: self)
    }

    // MARK: Input from the channels

    func receiveFinal(_ language: CaptionSpeechLanguage, words: [CaptionWord]) {
        lock.lock()
        defer { lock.unlock() }
        note(words, language: language, isFinal: true)
        let kept = trimToFrontier(words)
        if let phrase = Phrase(words: kept, arrival: Date()) {
            queues[language, default: []].append(phrase)
            scheduleTick()
        }
        opens[language] = []
        drain(force: false)
        publishOpen()
    }

    func receiveOpen(_ language: CaptionSpeechLanguage, words: [CaptionWord]) {
        lock.lock()
        defer { lock.unlock() }
        note(words, language: language, isFinal: false)
        opens[language] = trimToFrontier(words)
        drain(force: false)
        publishOpen()
    }

    /// The recognizer for `language` stopped (audio ended, or it was dropped after failing).
    func channelEnded(_ language: CaptionSpeechLanguage) {
        lock.lock()
        defer { lock.unlock() }
        active.remove(language)
        drain(force: active.isEmpty)
        publishOpen()
    }

    /// Judges everything that is still waiting. Call once all recognizers have returned.
    func finish() {
        lock.lock()
        defer { lock.unlock() }
        active.removeAll()
        drain(force: true)
    }

    func notice(_ message: String) {
        downstream.notice(message)
    }

    // MARK: Internals (call with `lock` held)

    private func note(_ words: [CaptionWord], language: CaptionSpeechLanguage, isFinal: Bool) {
        guard let last = words.last else { return }
        latestEnd = max(latestEnd, last.end)
        if isFinal {
            committedEnd[language] = max(committedEnd[language] ?? 0, last.end)
        }
    }

    /// Words whose middle lies before the already emitted audio were judged already.
    private func trimToFrontier(_ words: [CaptionWord]) -> [CaptionWord] {
        words.filter { ($0.start + $0.end) / 2 >= frontier }
    }

    private func scheduleTick() {
        let delay = graceSeconds + 0.05
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.tick()
        }
    }

    private func tick() {
        lock.lock()
        defer { lock.unlock() }
        drain(force: false)
        publishOpen()
    }

    private func drain(force: Bool) {
        while let unit = nextUnit() {
            guard force || isReady(unit) else { break }
            emit(unit)
        }
    }

    /// The earliest phrase plus every phrase of either language that overlaps it in time.
    private func nextUnit() -> Unit? {
        var earliest: (language: CaptionSpeechLanguage, index: Int, phrase: Phrase)?
        for language in CaptionSpeechLanguage.allCases {
            guard let phrase = queues[language]?.first else { continue }
            if earliest == nil || phrase.start < (earliest?.phrase.start ?? .infinity) {
                earliest = (language, 0, phrase)
            }
        }
        guard let seed = earliest else { return nil }

        var unit = Unit(start: seed.phrase.start, end: seed.phrase.end, taken: [seed.language: [seed.index]])
        var changed = true
        while changed {
            changed = false
            for language in CaptionSpeechLanguage.allCases {
                let phrases = queues[language] ?? []
                for (index, phrase) in phrases.enumerated() {
                    if unit.taken[language]?.contains(index) == true { continue }
                    let overlaps = phrase.start < unit.end - overlapTolerance && phrase.end > unit.start + overlapTolerance
                    let span = max(unit.end, phrase.end) - min(unit.start, phrase.start)
                    guard overlaps, span <= maximumUnitSeconds else { continue }
                    unit.taken[language, default: []].append(index)
                    unit.start = min(unit.start, phrase.start)
                    unit.end = max(unit.end, phrase.end)
                    changed = true
                }
            }
        }
        return unit
    }

    private func isReady(_ unit: Unit) -> Bool {
        let now = Date()
        var oldest = now
        for (language, indexes) in unit.taken {
            for index in indexes {
                if let phrase = queues[language]?[index], phrase.arrival < oldest { oldest = phrase.arrival }
            }
        }
        let waitedLongEnough = now.timeIntervalSince(oldest) >= graceSeconds
        let newerSpeech = latestEnd - unit.end > maximumLagSeconds

        for language in active {
            let contributed = !(unit.taken[language] ?? []).isEmpty
            let covered = contributed || (committedEnd[language] ?? 0) >= unit.end - coverTolerance
            if !covered && !(waitedLongEnough || newerSpeech) { return false }
        }
        return true
    }

    private func emit(_ unit: Unit) {
        var candidates: [CaptionSpeechLanguage: [CaptionWord]] = [:]
        for language in CaptionSpeechLanguage.allCases {
            let phrases = queues[language] ?? []
            var words: [CaptionWord] = []
            for index in (unit.taken[language] ?? []).sorted() where index < phrases.count {
                words.append(contentsOf: phrases[index].words)
            }
            if words.isEmpty {
                // This recognizer has not finished a phrase here; use its partial if it has one.
                words = (opens[language] ?? []).filter {
                    let middle = ($0.start + $0.end) / 2
                    return middle >= unit.start - overlapTolerance && middle <= unit.end + overlapTolerance
                }
            }
            candidates[language] = words
        }

        let english = candidates[.english] ?? []
        let hindi = candidates[.hindi] ?? []
        let decision = arbiter.decide(english: english, hindi: hindi)
        var winner = decision.language == .english ? english : hindi
        if winner.isEmpty { winner = decision.language == .english ? hindi : english }
        if !winner.isEmpty {
            downstream.commit(winner)
        }

        for language in CaptionSpeechLanguage.allCases {
            let taken = Set(unit.taken[language] ?? [])
            var remaining: [Phrase] = []
            for (index, phrase) in (queues[language] ?? []).enumerated() where !taken.contains(index) {
                remaining.append(phrase)
            }
            queues[language] = remaining
        }
        frontier = max(frontier, unit.end)
        for language in CaptionSpeechLanguage.allCases {
            queues[language] = (queues[language] ?? []).filter { $0.end > frontier }
            opens[language] = trimToFrontier(opens[language] ?? [])
        }
        lastDisplayKey = ""
    }

    /// Shows the partial of the language that currently wins, including phrases still waiting
    /// for their verdict so the caption never goes blank while the other recognizer catches up.
    private func publishOpen() {
        var display: [CaptionSpeechLanguage: [CaptionWord]] = [:]
        for language in CaptionSpeechLanguage.allCases {
            var words: [CaptionWord] = []
            for phrase in queues[language] ?? [] { words.append(contentsOf: phrase.words) }
            words.append(contentsOf: opens[language] ?? [])
            display[language] = words
        }
        let english = display[.english] ?? []
        let hindi = display[.hindi] ?? []
        guard !english.isEmpty || !hindi.isEmpty else { return }

        let chosen = arbiter.preview(english: english, hindi: hindi)
        var words = chosen == .english ? english : hindi
        if words.isEmpty { words = chosen == .english ? hindi : english }
        guard !words.isEmpty else { return }

        let key = words.map(\.text).joined(separator: " ")
        guard key != lastDisplayKey else { return }
        lastDisplayKey = key
        downstream.updateOpen(words)
    }
}

/// One recognizer's view of the session. Stitches its own partials and finals, then reports
/// finished phrases and the open tail to the hub.
final class CaptionChannelSink: CaptionResultSink, @unchecked Sendable {
    let language: CaptionSpeechLanguage
    private let hub: CaptionLanguageHub
    private let lock = NSLock()
    private var stitcher = LiveCaptionStitcher()

    init(language: CaptionSpeechLanguage, hub: CaptionLanguageHub) {
        self.language = language
        self.hub = hub
    }

    func setAutoCommit(_ policy: LiveCaptionStitcher.AutoCommitPolicy?) {
        lock.lock()
        stitcher.autoCommit = policy
        lock.unlock()
    }

    func updateOpen(_ words: [CaptionWord]) {
        lock.lock()
        let chunks = stitcher.updateOpen(words)
        let open = stitcher.openWords
        lock.unlock()
        deliver(chunks: chunks, open: open)
    }

    func commit(_ words: [CaptionWord]) {
        lock.lock()
        let chunk = stitcher.commit(words)
        lock.unlock()
        deliver(chunks: chunk.map { [$0] } ?? [], open: [])
    }

    func notice(_ message: String) {
        hub.notice(message)
    }

    /// Tells the hub this recognizer is done (audio ended or it was dropped).
    func end() {
        hub.channelEnded(language)
    }

    private func deliver(chunks: [LiveTranscriptChunk], open: [CaptionWord]) {
        for chunk in chunks where chunk.isFinal {
            let words = chunk.segments.map {
                CaptionWord(text: $0.text, start: $0.startTime, end: $0.endTime, confidence: $0.confidence)
            }
            if !words.isEmpty { hub.receiveFinal(language, words: words) }
        }
        hub.receiveOpen(language, words: open)
    }
}
