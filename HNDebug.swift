/*
 * Hanulim
 *
 * http://code.google.com/p/hanulim
 */

import Foundation

func HNLog(_ message: @autoclosure () -> String) {
#if DEBUG
    NSLog("%@", message())
#endif
}
