import AVFoundation
import SoundAnalysis
import Foundation

// Offline observation only: no recording, network requests, or playback control.
// Usage: analyze-audio-cues <session-directory> <output-directory>
final class Observer: NSObject, SNResultsObserving {
    var windows: [[String: Any]] = []
    var failure: Error?
    var completed = false
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let scores = Dictionary(uniqueKeysWithValues: result.classifications.map { ($0.identifier, $0.confidence) })
        windows.append(["start": result.timeRange.start.seconds,
                        "duration": result.timeRange.duration.seconds, "scores": scores])
    }
    func request(_ request: SNRequest, didFailWithError error: Error) { failure = error }
    func requestDidComplete(_ request: SNRequest) { completed = true }
}
func analyze(_ source: URL, output: URL) throws {
    let metadataURL = source.deletingPathExtension().appendingPathExtension("json")
    let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL))
    let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
    request.overlapFactor = 0.5
    let observer = Observer()
    let analyzer = try SNAudioFileAnalyzer(url: source)
    try analyzer.add(request, withObserver: observer)
    analyzer.analyze() // Synchronous file analysis; observer remains strongly retained.
    if let error = observer.failure { throw error }
    guard observer.completed, !observer.windows.isEmpty else {
        throw NSError(domain: "AudioCueAnalysis", code: 1, userInfo: [NSLocalizedDescriptionKey: "No completed classifications for \(source.lastPathComponent)"])
    }
    let result: [String: Any] = ["file": source.lastPathComponent,
        "classifier": "Apple SoundAnalysis version1", "windowDuration": request.windowDuration.seconds,
        "overlapFactor": request.overlapFactor, "metadata": metadata,
        "note": "Sound-class scores are not commercial probabilities. Times refer to WAV audio, which omits missing intervals; do not assume partial-clip markers occur at 20 seconds.",
        "windows": observer.windows]
    try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        .write(to: output.appendingPathComponent(source.deletingPathExtension().lastPathComponent + "-cues.json"), options: .atomic)
    print("Analyzed \(source.lastPathComponent): \(observer.windows.count) windows")
}
do {
    guard CommandLine.arguments.count == 3 else {
        throw NSError(domain: "AudioCueAnalysis", code: 2, userInfo: [NSLocalizedDescriptionKey: "Usage: analyze-audio-cues <session-directory> <output-directory>"])
    }
    let source = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let files = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "wav" }.sorted { $0.path < $1.path }
    guard !files.isEmpty else { throw NSError(domain: "AudioCueAnalysis", code: 3, userInfo: [NSLocalizedDescriptionKey: "No WAV clips found"] ) }
    for file in files { try analyze(file, output: output) }
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
