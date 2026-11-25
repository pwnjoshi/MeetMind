import Foundation

/// A stretch of continuous speech inside an audio file, in seconds from the start of the file.
struct SpeechRegion: Equatable, Sendable {
    var start: Double
    var end: Double
    var duration: Double { end - start }
}

/// Splits a recording into speech regions that are each decoded in one language.
/// Pure and deterministic: it works on frame energies only, so it is tested without a model.
enum SpeechRegionPlanner {
    struct Parameters: Equatable, Sendable {
        /// Length of one energy frame.
        var frameSeconds: Double = 0.05
        /// Speech separated by less silence than this is one region.
        var mergeGap: Double = 0.6
        /// Speech spans shorter than this are clicks or breaths and are dropped.
        var minSpeech: Double = 0.25
        /// A region shorter than this is joined to a neighbour when the gap is at most `shortMergeGap`.
        /// Every region costs one encoder pass, so this bounds the cost of many short utterances.
        var shortRegion: Double = 2.0
        var shortMergeGap: Double = 1.2
        /// Longest region. Whisper decodes at most 30 seconds per window.
        var maxRegion: Double = 25.0
        /// Context kept around a region, never more than half of the neighbouring gap.
        var padding: Double = 0.2

        static let standard = Parameters()
    }

    /// Below this peak energy (RMS of float samples) the audio is treated as silence.
    static let silencePeak: Float = 0.004
    static let silenceFloor: Float = 0.002

    // MARK: - Energies

    /// RMS energy of consecutive frames of `frameLength` samples. The last frame may be shorter.
    static func frameEnergies(_ samples: [Float], frameLength: Int) -> [Float] {
        guard frameLength > 0, !samples.isEmpty else { return [] }
        var result: [Float] = []
        result.reserveCapacity(samples.count / frameLength + 1)
        var index = 0
        while index < samples.count {
            let end = min(index + frameLength, samples.count)
            var sum: Float = 0
            var k = index
            while k < end {
                sum += samples[k] * samples[k]
                k += 1
            }
            result.append((sum / Float(end - index)).squareRoot())
            index = end
        }
        return result
    }

    /// Marks frames above an adaptive threshold between the quiet floor and the loud peak.
    /// Returns all false when even the peak is too quiet to be speech.
    static func speechMask(energies: [Float]) -> [Bool] {
        guard !energies.isEmpty else { return [] }
        let sorted = energies.sorted()
        func percentile(_ fraction: Double) -> Float {
            sorted[min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * fraction)))]
        }
        let floorLevel = percentile(0.10)
        let peak = percentile(0.95)
        guard peak >= silencePeak else { return Array(repeating: false, count: energies.count) }
        // Nonstop sound with no quiet floor to compare against: every frame is speech.
        if peak <= floorLevel * 2.5 { return Array(repeating: true, count: energies.count) }
        let threshold = max(floorLevel * 2.5, floorLevel + 0.2 * (peak - floorLevel), silenceFloor)
        return energies.map { $0 > threshold }
    }

    // MARK: - Regions

    /// Consecutive true frames as regions.
    static func spans(mask: [Bool], frameSeconds: Double) -> [SpeechRegion] {
        var result: [SpeechRegion] = []
        var open: Int?
        for (index, active) in mask.enumerated() {
            if active {
                if open == nil { open = index }
            } else if let first = open {
                result.append(SpeechRegion(start: Double(first) * frameSeconds, end: Double(index) * frameSeconds))
                open = nil
            }
        }
        if let first = open {
            result.append(SpeechRegion(start: Double(first) * frameSeconds, end: Double(mask.count) * frameSeconds))
        }
        return result
    }

    /// Joins regions separated by a gap shorter than `maxGap`.
    static func merge(_ regions: [SpeechRegion], maxGap: Double) -> [SpeechRegion] {
        var result: [SpeechRegion] = []
        for region in regions.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, region.start - last.end < maxGap {
                result[result.count - 1].end = max(last.end, region.end)
            } else {
                result.append(region)
            }
        }
        return result
    }

    /// Joins each short region to its nearer neighbour when that gap is small and the result stays within `maxRegion`.
    static func mergeShort(_ regions: [SpeechRegion], shortRegion: Double, maxGap: Double,
                           maxRegion: Double) -> [SpeechRegion] {
        var current = regions
        var changed = true
        while changed {
            changed = false
            var index = 0
            while index < current.count {
                guard current[index].duration < shortRegion else { index += 1; continue }
                let before: Double? = index > 0 ? current[index].start - current[index - 1].end : nil
                let after: Double? = index + 1 < current.count ? current[index + 1].start - current[index].end : nil
                func fits(_ gap: Double?, _ first: Int, _ second: Int) -> Bool {
                    guard let gap = gap, gap <= maxGap else { return false }
                    return current[second].end - current[first].start <= maxRegion
                }
                let canBefore = fits(before, index - 1, index)
                let canAfter = fits(after, index, index + 1)
                if canBefore, !canAfter || (before ?? 0) <= (after ?? 0) {
                    current[index - 1].end = current[index].end
                    current.remove(at: index)
                    changed = true
                    break
                } else if canAfter {
                    current[index].end = current[index + 1].end
                    current.remove(at: index + 1)
                    changed = true
                    break
                }
                index += 1
            }
        }
        return current
    }

    /// The centre of the quietest frame in `[from, to]` (three-frame average), or nil when the range is empty.
    static func quietestTime(energies: [Float], frameSeconds: Double, from: Double, to: Double) -> Double? {
        guard frameSeconds > 0, !energies.isEmpty else { return nil }
        let low = max(0, Int((from / frameSeconds).rounded(.down)))
        let high = min(energies.count - 1, Int((to / frameSeconds).rounded(.down)))
        guard low <= high else { return nil }
        var bestIndex = low
        var bestValue = Float.greatestFiniteMagnitude
        for index in low...high {
            let left = energies[max(0, index - 1)]
            let right = energies[min(energies.count - 1, index + 1)]
            let value = (left + energies[index] + right) / 3
            if value <= bestValue {
                bestValue = value
                bestIndex = index
            }
        }
        return (Double(bestIndex) + 0.5) * frameSeconds
    }

    /// Cuts a region longer than `maxLength` at the quietest point in the second half of each piece.
    static func split(_ region: SpeechRegion, energies: [Float], frameSeconds: Double,
                      maxLength: Double) -> [SpeechRegion] {
        guard maxLength > 0, region.duration > maxLength else { return [region] }
        var pieces: [SpeechRegion] = []
        var cursor = region.start
        var rounds = 0
        while region.end - cursor > maxLength, rounds < 100_000 {
            rounds += 1
            let low = cursor + maxLength * 0.5
            let high = cursor + maxLength - frameSeconds
            var cut = cursor + maxLength
            if let quiet = quietestTime(energies: energies, frameSeconds: frameSeconds, from: low, to: high),
               quiet > cursor, quiet < cursor + maxLength {
                cut = quiet
            }
            pieces.append(SpeechRegion(start: cursor, end: cut))
            cursor = cut
        }
        pieces.append(SpeechRegion(start: cursor, end: region.end))
        return pieces
    }

    /// Adds context around each region. Padding never exceeds half the gap to a neighbour, so regions
    /// never overlap and pieces cut from one long region stay contiguous.
    static func pad(_ regions: [SpeechRegion], by padding: Double, duration: Double) -> [SpeechRegion] {
        var result: [SpeechRegion] = []
        for (index, region) in regions.enumerated() {
            let before = index > 0 ? (region.start - regions[index - 1].end) / 2 : region.start
            let after = index + 1 < regions.count ? (regions[index + 1].start - region.end) / 2 : duration - region.end
            let start = region.start - min(padding, max(0, before))
            let end = region.end + min(padding, max(0, after))
            result.append(SpeechRegion(start: max(0, start), end: min(duration, max(end, start))))
        }
        return result
    }

    /// Full plan: speech mask, gap merge, click removal, short-region joining, length cap, padding.
    static func plan(energies: [Float], parameters: Parameters = .standard) -> [SpeechRegion] {
        guard !energies.isEmpty, parameters.frameSeconds > 0 else { return [] }
        let duration = Double(energies.count) * parameters.frameSeconds
        let mask = speechMask(energies: energies)
        var regions = spans(mask: mask, frameSeconds: parameters.frameSeconds)
        regions = merge(regions, maxGap: parameters.mergeGap)
        regions = regions.filter { $0.duration >= parameters.minSpeech }
        regions = mergeShort(regions, shortRegion: parameters.shortRegion, maxGap: parameters.shortMergeGap,
                             maxRegion: parameters.maxRegion)
        var capped: [SpeechRegion] = []
        for region in regions {
            capped.append(contentsOf: split(region, energies: energies, frameSeconds: parameters.frameSeconds,
                                            maxLength: parameters.maxRegion))
        }
        return pad(capped, by: parameters.padding, duration: duration)
    }

    /// Finds substantial untranscribed intervals inside a speech region that
    /// already yielded some words. Empty regions are retried separately.
    static func missingIntervals(in region: SpeechRegion, covered: [SpeechRegion]) -> [SpeechRegion] {
        let coverage = covered.filter { $0.end > $0.start && $0.end > region.start && $0.start < region.end }
            .sorted { $0.start < $1.start }
        guard !coverage.isEmpty else { return [] }
        let minimumGap = 4.0
        var cursor = region.start
        var result: [SpeechRegion] = []
        for span in coverage {
            let start = max(region.start, span.start)
            if start - cursor >= minimumGap { result.append(SpeechRegion(start: cursor, end: start)) }
            cursor = max(cursor, min(region.end, span.end))
        }
        if region.end - cursor >= minimumGap { result.append(SpeechRegion(start: cursor, end: region.end)) }
        return result
    }

    // MARK: - Timestamps

    /// Moves a segment time range from region-relative to file-relative seconds. Times are first clamped to
    /// `[0, limit]` because a padded decode window can report times past the end of a short region.
    static func shifted(start: Double, end: Double, by offset: Double, limit: Double) -> (start: Double, end: Double) {
        let low = min(max(0, start), max(0, limit))
        let high = min(max(low, end), max(low, limit))
        return (low + offset, high + offset)
    }
}
