import Foundation

let applicationSupportDirectoryName = "CommercialBreaker"
let legacyApplicationSupportDirectoryName = "SkyboxAudioProbe"

/// Moves the pre-rename support directory to its new name. Does nothing unless the old
/// directory exists and the new one does not, so it never merges. A failed move is reported
/// and the old directory is left in place.
func migrateApplicationSupportDirectory(from old: URL, to new: URL,
                                        report: (String) -> Void = { NSLog("%@", $0) }) {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: old.path), !fileManager.fileExists(atPath: new.path) else { return }
    do {
        try fileManager.moveItem(at: old, to: new)
    } catch {
        report("Could not move \(old.path) to \(new.path): \(error.localizedDescription)")
    }
}

/// Runs the migration under the user's Application Support folder. Call once at launch,
/// before any model resolves a log or recording path.
func migrateUserApplicationSupportDirectory() {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
    migrateApplicationSupportDirectory(from: base.appendingPathComponent(legacyApplicationSupportDirectoryName),
                                       to: base.appendingPathComponent(applicationSupportDirectoryName))
}
