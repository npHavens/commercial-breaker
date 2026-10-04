/// Selects frames by video time, including the first frame after each capture restart.
struct FrameSampler {
    let interval: Double
    private var lastSaved: Double?

    init(interval: Double) {
        precondition(interval > 0)
        self.interval = interval
    }

    func isDue(_ time: Double) -> Bool {
        guard time.isFinite else { return false }
        guard let lastSaved else { return true }
        return time < lastSaved || time - lastSaved >= interval
    }

    mutating func didSave(_ time: Double) { lastSaved = time }
    mutating func reset() { lastSaved = nil }
}
