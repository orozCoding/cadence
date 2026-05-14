import UniformTypeIdentifiers

extension UTType {
    // In-app drag type for task reorder and cross-period moves.
    // Using a custom type instead of plain-text ensures external-app drops
    // are rejected at the type-check level, preventing false-positive
    // success animations when non-task text is dropped onto task rows or sidebar rows.
    // importedAs (not exportedAs) avoids requiring a UTExportedTypeDeclarations
    // Info.plist entry while producing an identical UTType identifier for DnD matching.
    static let cadenceTaskID = UTType(importedAs: "com.orozcoding.cadence.task-id")
}
