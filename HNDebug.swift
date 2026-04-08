/*
 * Hanulim
 *
 * Original Objective-C code - https://github.com/han9kin/hanulim
 *
 * Debug logging utilities.
 *
 * `HNLog` is a thin wrapper around `NSLog`. Messages are written to the
 * unified logging system and appear in Console.app under the process name
 * "Hanulim".
 *
 * The function body is compiled only when the DEBUG preprocessor flag is set
 * (i.e. in Debug build configurations). In Release builds the call site is
 * still compiled but the body is a no-op, so there is zero runtime cost and
 * no log output in production.
 *
 * The `@autoclosure` parameter means the message string is only evaluated
 * (and any interpolation performed) when the DEBUG branch is actually taken,
 * avoiding unnecessary string construction in release builds even if the
 * compiler cannot eliminate the call entirely.
 */

import Foundation

func HNLog(_ message: @autoclosure () -> String) {
#if DEBUG
    NSLog("%@", message())
#endif
}
