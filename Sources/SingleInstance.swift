import Foundation
import Darwin

/// The descriptor stays open for the owner's lifetime. The kernel releases the
/// lock after a crash; the presence of an old lock file never prevents launch.
final class SingleInstanceLock {
    private let descriptor: Int32
    let isOwner: Bool

    init(fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        descriptor = open(fileURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            isOwner = true
        } else {
            let code = errno
            close(descriptor)
            guard code == EWOULDBLOCK else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
            isOwner = false
        }
    }

    deinit {
        if isOwner { close(descriptor) }
    }
}
