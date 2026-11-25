import Foundation
import OSLog

/// Joins English and Hindi recognizers that hear the same audio into one caption stream.
///
/// Final phrases wait here only for arbitration. They are never folded back into the mutable
/// preview. The downstream stream therefore consists of an immutable committed prefix and, at
/// most, one mutable phrase whose words are all after `frontier`.
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

    private struct PendingDecision {
        var start: TimeInterval
        var end: TimeInterval
        let language: CaptionSpeechLanguage
        let firstFinalArrival: Date
    }

    /// The first final waits at most this long for the other recognizer's final confidence.
    private let graceSeconds: TimeInterval
    private let maximumLagSeconds: TimeInterval = 4.0
    private let coverTolerance: TimeInterval = 0.4
    private let overlapTolerance: TimeInterval = 0.15
    private let phrasePause: TimeInterval = 0.9
    private let previewContinuationMargin: TimeInterval = 0.45
    private let maximumUnitSeconds: TimeInterval = 25

    private let lock = NSLock()
    private let downstream: any CaptionResultSink
    private var arbiter: LiveCaptionLanguageArbiter
    private var queues: [CaptionSpeechLanguage: [Phrase]] = [.english: [], .hindi: []]
    private var opens: [CaptionSpeechLanguage: [CaptionWord]] = [.english: [], .hindi: []]
    private var finalizedEnd: [CaptionSpeechLanguage: TimeInterval] = [.english: 0, .hindi: 0]
    private var active: Set<CaptionSpeechLanguage>
    private var latestEnd: TimeInterval = 0
    private var frontier: TimeInterval = 0
    private var pendingDecision: PendingDecision?
    private var previewLanguage: CaptionSpeechLanguage?
    private var previewStart: TimeInterval = 0
    private var previewEnd: TimeInterval = 0
    private var lastDisplayKey = ""
    private var hasPublishedOpen = false
    private var tickScheduled = false

    // Content-free operational metrics. Never include recognized text in this logger.
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MeetMind", category: "LiveCaptions")
    private var committedPhraseCount = 0
    private var languageSwitchCount = 0
    private var ignoredLateAlternateCount = 0
    private var totalDecisionDelay: TimeInterval = 0
    private var lastMetricsLogAt = Date.distantPast

    init(downstream: any CaptionResultSink, languages: Set<CaptionSpeechLanguage> = [.english, .hindi],
         arbiter: LiveCaptionLanguageArbiter = LiveCaptionLanguageArbiter(), graceSeconds: TimeInterval = 0.55) {
        self.downstream = downstream
        self.active = languages
        self.arbiter = arbiter
        self.graceSeconds = min(0.6, max(0, graceSeconds))
        // The hub owns phrase boundaries. The final downstream stitcher only removes overlap.
        downstream.setAutoCommit(nil)
    }

    func sink(for language: CaptionSpeechLanguage) -> CaptionChannelSink {
        CaptionChannelSink(language: language, hub: self)
    }

    // MARK: Input from the channels

    func receiveFinal(_ language: CaptionSpeechLanguage, words: [CaptionWord]) {
        lock.lock()
        defer { lock.unlock() }

        noteLatest(words)
        let kept = trimToFrontier(words)
        if !words.isEmpty, kept.isEmpty {
            ignoredLateAlternateCount += 1
            logMetrics()
            opens[language] = []
            publishOpen()
            return
        }
        if let phrase = Phrase(words: kept, arrival: Date()) {
            queues[language, default: []].append(phrase)
            finalizedEnd[language] = max(finalizedEnd[language] ?? 0, phrase.end)
            scheduleTick()
        }
        opens[language] = []
        drain(force: false)
        publishOpen()
    }

    func receiveOpen(_ language: CaptionSpeechLanguage, words: [CaptionWord]) {
        lock.lock()
        defer { lock.unlock() }

        noteLatest(words)
        let kept = trimToFrontier(words)
        if !words.isEmpty, kept.isEmpty {
            ignoredLateAlternateCount += 1
            logMetrics()
        }
        opens[language] = kept
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

    /// Judges everything still waiting. Call once all recognizers have returned.
    func finish() {
        lock.lock()
        defer { lock.unlock() }
        active.removeAll()
        drain(force: true)
        clearPublishedOpen()
    }

    func notice(_ message: String) {
        downstream.notice(message)
    }

    // MARK: Internals (call with `lock` held)

    private func noteLatest(_ words: [CaptionWord]) {
        guard let last = words.last else { return }
        latestEnd = max(latestEnd, last.end)
    }

    /// Words whose midpoint lies before immutable committed audio are already decided.
    private func trimToFrontier(_ words: [CaptionWord]) -> [CaptionWord] {
        words.filter { ($0.start + $0.end) / 2 >= frontier }
    }

    private func scheduleTick() {
        guard !tickScheduled else { return }
        tickScheduled = true
        let delay = graceSeconds + 0.02
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.tick()
        }
    }

    private func tick() {
        lock.lock()
        tickScheduled = false
        drain(force: false)
        publishOpen()
        if queues.values.contains(where: { !$0.isEmpty }) {
            scheduleTick()
        }
        lock.unlock()
    }

    private func drain(force: Bool) {
        while let unit = nextUnit() {
            lockDecision(for: unit)
            guard force || isReady(unit) else { break }
            emit(unit)
        }
    }

    /// The earliest final phrase plus every final phrase that overlaps it in audio time.
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
                for (index, phrase) in (queues[language] ?? []).enumerated() {
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

    /// Hold the preview steady while the alternate recognizer finishes. Choose the
    /// committed text after the grace window, using both final candidates if available.
    private func lockDecision(for unit: Unit) {
        if let pending = pendingDecision,
           rangesOverlap(pending.start, pending.end, unit.start, unit.end) {
            pendingDecision?.start = min(pending.start, unit.start)
            pendingDecision?.end = max(pending.end, unit.end)
            return
        }

        let candidates = candidates(for: unit)
        let language = arbiter.preview(english: candidates[.english] ?? [], hindi: candidates[.hindi] ?? [])
        let arrival = firstArrival(in: unit) ?? Date()
        pendingDecision = PendingDecision(start: unit.start, end: unit.end, language: language,
                                          firstFinalArrival: arrival)
        // A final is pending, so its previous partial must no longer remain mutable in the UI.
        clearPublishedOpen()
    }

    private func isReady(_ unit: Unit) -> Bool {
        guard pendingDecision != nil else { return false }
        let now = Date()
        let arrival = firstArrival(in: unit) ?? now
        let waitedLongEnough = now.timeIntervalSince(arrival) >= graceSeconds
        let newerSpeech = latestEnd - unit.end > maximumLagSeconds

        for language in active {
            let contributed = !(unit.taken[language] ?? []).isEmpty
            let covered = contributed || (finalizedEnd[language] ?? 0) >= unit.end - coverTolerance
            if !covered && !(waitedLongEnough || newerSpeech) { return false }
        }
        return true
    }

    private func firstArrival(in unit: Unit) -> Date? {
        var oldest: Date?
        for (language, indexes) in unit.taken {
            for index in indexes {
                guard let phrase = queues[language]?[index] else { continue }
                if let oldestArrival = oldest {
                    if phrase.arrival < oldestArrival { oldest = phrase.arrival }
                } else {
                    oldest = phrase.arrival
                }
            }
        }
        return oldest
    }

    private func candidates(for unit: Unit) -> [CaptionSpeechLanguage: [CaptionWord]] {
        var result: [CaptionSpeechLanguage: [CaptionWord]] = [:]
        for language in CaptionSpeechLanguage.allCases {
            let phrases = queues[language] ?? []
            var words: [CaptionWord] = []
            for index in (unit.taken[language] ?? []).sorted() where index < phrases.count {
                words.append(contentsOf: phrases[index].words)
            }
            if words.isEmpty {
                words = (opens[language] ?? []).filter {
                    let midpoint = ($0.start + $0.end) / 2
                    return midpoint >= unit.start - overlapTolerance && midpoint <= unit.end + overlapTolerance
                }
            }
            result[language] = words
        }
        return result
    }

    /// Replace a consecutive Hindi-script rendering of an English clause only
    /// when timestamps and multiple neighboring word matches support the swap.
    static func mixedClause(english: [CaptionWord], hindi: [CaptionWord]) -> [CaptionWord]? {
        let boundaries = hindi.indices.filter { LiveCaptionLexicon.hindiFunctionWords.contains(hindi[$0].comparisonKey) }
        guard boundaries.count >= 2, english.count >= 3 else { return nil }
        var result: [CaptionWord] = []
        var cursor = 0
        var switched = false
        for (left, right) in zip(boundaries, boundaries.dropFirst()) where right - left >= 4 {
            let span = (left + 1)..<right
            let original = Array(hindi[span])
            guard let first = original.first, let last = original.last else { continue }
            let replacement = english.filter {
                let midpoint = ($0.start + $0.end) / 2
                return midpoint >= first.start && midpoint <= last.end && $0.confidence >= 0.75
            }
            guard replacement.count >= 3,
                  let englishStart = replacement.first?.start, let englishEnd = replacement.last?.end,
                  abs(englishStart - first.start) <= 0.35, abs(englishEnd - last.end) <= 0.35 else { continue }
            let englishKeys = replacement.map(\.comparisonKey)
            let englishEvidence = LiveCaptionLanguageArbiter.evidence(english: replacement, hindi: [])
            guard englishEvidence.englishProbability >= 0.65 else { continue }
            let anchored = original.filter { word in
                let skeleton = LiveCaptionLexicon.devanagariSkeleton(word.comparisonKey)
                return skeleton.count >= 2 && englishKeys.contains { LiveCaptionLexicon.englishSkeleton($0) == skeleton }
            }
            guard anchored.count >= 2, anchored.count * 2 >= original.count else { continue }
            result.append(contentsOf: restoreLoanwords(english: english, hindi: Array(hindi[cursor..<span.lowerBound])))
            result.append(contentsOf: replacement)
            cursor = span.upperBound
            switched = true
        }
        guard switched else { return nil }
        result.append(contentsOf: restoreLoanwords(english: english, hindi: Array(hindi[cursor...])))
        return result
    }

    private static func restoreLoanwords(english: [CaptionWord], hindi: [CaptionWord]) -> [CaptionWord] {
        return hindi.map { word in
            // Keep the Hindi syntax and use the concurrent English spelling
            // only for the same recognized loanword at the same audio time.
            guard LiveCaptionLexicon.englishLoanwords.contains(word.comparisonKey) else { return word }
            let skeleton = LiveCaptionLexicon.devanagariSkeleton(word.comparisonKey)
            guard skeleton.count >= 3 else { return word }
            let midpoint = (word.start + word.end) / 2
            let matches = english.filter {
                $0.confidence >= 0.75 && $0.start <= midpoint && $0.end >= midpoint
                    && LiveCaptionLexicon.englishSkeleton($0.comparisonKey) == skeleton
            }
            guard matches.count == 1, let match = matches.first else { return word }
            var mixed = word
            mixed.text = match.text.trimmingCharacters(in: .punctuationCharacters)
            mixed.text.append(contentsOf: word.text.reversed().prefix(while: { $0.isPunctuation }).reversed())
            return mixed
        }
    }

    private func emit(_ unit: Unit) {
        let alternatives = candidates(for: unit)
        let english = (unit.taken[.english] ?? []).isEmpty ? [] : alternatives[.english] ?? []
        let hindi = (unit.taken[.hindi] ?? []).isEmpty ? [] : alternatives[.hindi] ?? []
        let decision = arbiter.decide(english: english, hindi: hindi)
        let mixed = Self.mixedClause(english: english, hindi: hindi)
        let winner = mixed ?? (decision.language == .english ? english : Self.restoreLoanwords(english: english, hindi: hindi))
        let pending = pendingDecision
        if !winner.isEmpty {
            downstream.commit(winner)
            committedPhraseCount += 1
            if decision.switched { languageSwitchCount += 1 }
            if let arrival = pending?.firstFinalArrival {
                totalDecisionDelay += max(0, Date().timeIntervalSince(arrival))
            }
        }

        for language in CaptionSpeechLanguage.allCases {
            let taken = Set(unit.taken[language] ?? [])
            queues[language] = (queues[language] ?? []).enumerated().compactMap { index, phrase in
                taken.contains(index) ? nil : phrase
            }
        }

        // Advance by audio, not text. This suppresses late alternate-language finals and
        // overlapping recognizer restarts even when their spelling differs.
        frontier = max(frontier, unit.end)
        for language in CaptionSpeechLanguage.allCases {
            queues[language] = (queues[language] ?? []).compactMap { phrase in
                Phrase(words: trimToFrontier(phrase.words), arrival: phrase.arrival)
            }
            opens[language] = trimToFrontier(opens[language] ?? [])
        }
        pendingDecision = nil
        previewLanguage = nil
        previewStart = frontier
        previewEnd = frontier
        clearPublishedOpen()
        logMetrics(force: true)
    }

    /// Emits only the latest current open unit. Queued finals are deliberately absent.
    private func publishOpen() {
        let current = currentOpenCandidates()
        let english = current[.english] ?? []
        let hindi = current[.hindi] ?? []
        guard !english.isEmpty || !hindi.isEmpty else {
            clearPublishedOpen()
            return
        }

        let all = english + hindi
        let start = all.map(\.start).min() ?? frontier
        let end = all.map(\.end).max() ?? start
        let continuesPreview = previewLanguage != nil && start <= previewEnd + previewContinuationMargin

        let evidence = LiveCaptionLanguageArbiter.evidence(english: english, hindi: hindi,
                                                           configuration: arbiter.configuration)
        var chosen: CaptionSpeechLanguage
        if let pending = pendingDecision,
           rangesOverlap(pending.start, pending.end, start, end) {
            chosen = pending.language
        } else if continuesPreview, let currentLanguage = previewLanguage {
            chosen = LiveCaptionLanguageArbiter.resolve(evidence: evidence, current: currentLanguage,
                                                        configuration: arbiter.configuration)
        } else {
            chosen = arbiter.preview(english: english, hindi: hindi)
        }

        // Once a phrase has a language, a weak or missing alternate cannot rewrite it. A clear
        // arbiter margin can switch an unfinalized phrase; a pause starts a freely chosen phrase.
        var words = chosen == .english ? english : hindi
        if words.isEmpty, !continuesPreview, pendingDecision == nil {
            chosen = chosen == .english ? .hindi : .english
            words = chosen == .english ? english : hindi
        }
        guard !words.isEmpty else {
            clearPublishedOpen()
            return
        }

        previewLanguage = chosen
        previewStart = continuesPreview ? min(previewStart, start) : start
        previewEnd = max(end, words.last?.end ?? end)
        let key = "\(chosen.rawValue):" + words.map(\.text).joined(separator: " ")
        guard key != lastDisplayKey else { return }
        lastDisplayKey = key
        hasPublishedOpen = true
        downstream.updateOpen(words)
    }

    /// Takes the suffix after the latest real pause, then pairs only candidates that overlap the
    /// most recent recognizer result. This keeps one mutable phrase even when a recognizer's
    /// partial contains its full session hypothesis.
    private func currentOpenCandidates() -> [CaptionSpeechLanguage: [CaptionWord]] {
        var phrases: [CaptionSpeechLanguage: [CaptionWord]] = [:]
        for language in CaptionSpeechLanguage.allCases {
            phrases[language] = currentPhrase(in: trimToFrontier(opens[language] ?? []))
        }
        guard let anchor = phrases.values.filter({ !$0.isEmpty }).max(by: {
            ($0.last?.end ?? 0) < ($1.last?.end ?? 0)
        }), let anchorFirst = anchor.first, let anchorLast = anchor.last else { return phrases }

        let anchorStart = anchorFirst.start
        let anchorEnd = anchorLast.end
        for language in CaptionSpeechLanguage.allCases {
            guard let words = phrases[language], let first = words.first, let last = words.last else { continue }
            if !rangesOverlap(first.start, last.end, anchorStart, anchorEnd) {
                phrases[language] = []
            }
        }
        return phrases
    }

    private func currentPhrase(in words: [CaptionWord]) -> [CaptionWord] {
        guard words.count > 1 else { return words }
        var startIndex = 0
        for index in 1..<words.count where words[index].start - words[index - 1].end >= phrasePause {
            startIndex = index
        }
        return Array(words[startIndex...])
    }

    private func rangesOverlap(_ firstStart: TimeInterval, _ firstEnd: TimeInterval,
                               _ secondStart: TimeInterval, _ secondEnd: TimeInterval) -> Bool {
        firstStart < secondEnd + overlapTolerance && firstEnd > secondStart - overlapTolerance
    }

    private func clearPublishedOpen() {
        guard hasPublishedOpen || !lastDisplayKey.isEmpty else { return }
        hasPublishedOpen = false
        lastDisplayKey = ""
        downstream.clearOpen()
    }

    private func logMetrics(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastMetricsLogAt) >= 1 else { return }
        lastMetricsLogAt = now
        let average = committedPhraseCount == 0 ? 0 : totalDecisionDelay / Double(committedPhraseCount)
        logger.info("caption_metrics committed=\(self.committedPhraseCount, privacy: .public) switches=\(self.languageSwitchCount, privacy: .public) ignored_late=\(self.ignoredLateAlternateCount, privacy: .public) avg_delay_ms=\(Int(average * 1000), privacy: .public)")
    }
}

/// One recognizer's view of the session. It stitches its own restarts before reporting to the hub.
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

    func clearOpen() {
        lock.lock()
        stitcher.clearOpen()
        lock.unlock()
        hub.receiveOpen(language, words: [])
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
