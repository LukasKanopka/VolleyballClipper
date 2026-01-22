import Foundation

final class SecurityScopedAccess {
    private let url: URL
    private var isAccessing = false

    init(url: URL) {
        self.url = url
    }

    func start() -> Bool {
        guard !isAccessing else { return true }
        isAccessing = url.startAccessingSecurityScopedResource()
        return isAccessing
    }

    func stop() {
        guard isAccessing else { return }
        url.stopAccessingSecurityScopedResource()
        isAccessing = false
    }
}

