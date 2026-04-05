/*
 * Hanulim
 *
 * http://code.google.com/p/hanulim
 */

import Foundation

autoreleasepool {
    let args = CommandLine.arguments

    guard args.count > 1 else { exit(0) }

    let cmd = args[1]
    let remaining = Array(args.dropFirst(2))

    switch cmd.lowercased() {
    case "import":
        ATImport().doWithArguments(remaining)
    default:
        NSLog("unknown command: %@", cmd)
    }
}
