import Foundation
import Darwin
public enum HomePaths {
    /// The login home, including when the UI app runs in its original App Sandbox.
    public static var userHome: String {
        getpwuid(getuid()).flatMap { $0.pointee.pw_dir }.map { String(cString: $0) } ?? NSHomeDirectory()
    }
}
