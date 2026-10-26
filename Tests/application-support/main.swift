import Foundation

let fileManager = FileManager.default
let work = fileManager.temporaryDirectory.appendingPathComponent("commercial-breaker-support-\(UUID())")
defer {
    try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: work.path)
    try? fileManager.removeItem(at: work)
}

func scenario(_ name: String) throws -> (old: URL, new: URL) {
    let base = work.appendingPathComponent(name)
    try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
    return (base.appendingPathComponent(legacyApplicationSupportDirectoryName),
            base.appendingPathComponent(applicationSupportDirectoryName))
}

func write(_ text: String, to url: URL) throws {
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

assert(applicationSupportDirectoryName == "CommercialBreaker")

// Old only: moved with its nested contents.
do {
    let (old, new) = try scenario("old-only")
    try write("history", to: old.appendingPathComponent("automatic-1.jsonl"))
    try write("clip", to: old.appendingPathComponent("recordings/abc/clip.wav"))
    var reports: [String] = []
    migrateApplicationSupportDirectory(from: old, to: new) { reports.append($0) }
    assert(read(new.appendingPathComponent("automatic-1.jsonl")) == "history")
    assert(read(new.appendingPathComponent("recordings/abc/clip.wav")) == "clip")
    assert(!fileManager.fileExists(atPath: old.path))
    assert(reports.isEmpty)
}

// Both exist: nothing changes and nothing merges.
do {
    let (old, new) = try scenario("both")
    try write("old", to: old.appendingPathComponent("old.txt"))
    try write("new", to: new.appendingPathComponent("new.txt"))
    var reports: [String] = []
    migrateApplicationSupportDirectory(from: old, to: new) { reports.append($0) }
    assert(read(old.appendingPathComponent("old.txt")) == "old")
    assert(read(new.appendingPathComponent("new.txt")) == "new")
    assert(!fileManager.fileExists(atPath: new.appendingPathComponent("old.txt").path))
    assert(!fileManager.fileExists(atPath: old.appendingPathComponent("new.txt").path))
    assert(reports.isEmpty)
}

// Neither exists: no-op.
do {
    let (old, new) = try scenario("neither")
    var reports: [String] = []
    migrateApplicationSupportDirectory(from: old, to: new) { reports.append($0) }
    assert(!fileManager.fileExists(atPath: old.path))
    assert(!fileManager.fileExists(atPath: new.path))
    assert(reports.isEmpty)
}

// New only: untouched.
do {
    let (old, new) = try scenario("new-only")
    try write("new", to: new.appendingPathComponent("new.txt"))
    migrateApplicationSupportDirectory(from: old, to: new) { _ in }
    assert(read(new.appendingPathComponent("new.txt")) == "new")
}

// A failed move is reported, and the old data stays where it was.
do {
    let (old, new) = try scenario("failure")
    try write("history", to: old.appendingPathComponent("automatic-1.jsonl"))
    try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: old.deletingLastPathComponent().path)
    var reports: [String] = []
    migrateApplicationSupportDirectory(from: old, to: new) { reports.append($0) }
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: old.deletingLastPathComponent().path)
    assert(reports.count == 1 && reports[0].contains("Could not move"), "expected one failure report, got \(reports)")
    assert(read(old.appendingPathComponent("automatic-1.jsonl")) == "history")
    assert(!fileManager.fileExists(atPath: new.path))
}

print("Application Support migration checks passed: move, no merge, no-op, reported failure")
