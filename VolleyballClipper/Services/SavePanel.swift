import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

enum SavePanel {
    @MainActor
    static func pickMovieDestination(defaultName: String) async -> URL? {
        #if canImport(AppKit)
        return await withCheckedContinuation { continuation in
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.movie]
            panel.nameFieldStringValue = defaultName + ".mov"
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
        #else
        return nil
        #endif
    }
}

enum OpenPanel {
    @MainActor
    static func pickOutputDirectory() async -> URL? {
        #if canImport(AppKit)
        return await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
        #else
        return nil
        #endif
    }
}
