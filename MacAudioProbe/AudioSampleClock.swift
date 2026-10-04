import Foundation

/// Maps audio's first-frame timestamps into the same monotonic clock used by markers.
/// Host clock conversion is fixed once per session; callback scheduling never moves audio.
struct AudioSampleClock {
    enum ClockError: Error { case invalidTimestamp }
    private let hostToUptime: Double
    private var anchorSample: Int64?
    private var anchorUptime = 0.0
    private var previousEnd: Int64?
    private var rate: Double?

    init(hostNowSeconds: Double, uptimeNow: Double) {
        hostToUptime = uptimeNow - hostNowSeconds
    }

    mutating func endUptime(sampleTime: Int64, hostSeconds: Double,
                            frameCount: Int, sampleRate: Double) throws -> Double {
        guard frameCount > 0, sampleRate.isFinite, sampleRate > 0,
              hostSeconds.isFinite, hostToUptime.isFinite else { throw ClockError.invalidTimestamp }
        let (sampleEnd, overflow) = sampleTime.addingReportingOverflow(Int64(frameCount))
        guard !overflow else { throw ClockError.invalidTimestamp }
        let hostStart = hostSeconds + hostToUptime
        guard hostStart.isFinite else { throw ClockError.invalidTimestamp }

        let reset = rate != sampleRate || anchorSample == nil || previousEnd.map { sampleTime < $0 } == true
        if reset {
            anchorSample = sampleTime
            anchorUptime = hostStart
        } else if let anchorSample {
            let expected = anchorUptime + (Double(sampleTime) - Double(anchorSample)) / sampleRate
            // A stopped/restarted device can retain sample position while host time jumps.
            // Re-anchor only a material host-clock discontinuity; ordinary callback jitter
            // is irrelevant because this is AVAudioTime, not callback arrival time.
            if abs(hostStart - expected) > 0.1 {
                self.anchorSample = sampleTime
                anchorUptime = hostStart
            }
        }
        rate = sampleRate
        previousEnd = sampleEnd
        guard let anchorSample else { throw ClockError.invalidTimestamp }
        // Forward sample-position gaps are retained, never packed together.
        return anchorUptime + (Double(sampleEnd) - Double(anchorSample)) / sampleRate
    }
}
