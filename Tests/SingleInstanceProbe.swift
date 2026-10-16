import Foundation
import Darwin

@main
struct SingleInstanceProbe {
    static func main() throws {
        let lock = try SingleInstanceLock(fileURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        guard lock.isOwner else { exit(23) }
        if CommandLine.arguments.contains("--hold") {
            print("ready")
            fflush(stdout)
            _ = readLine()
        }
        withExtendedLifetime(lock) {}
    }
}
