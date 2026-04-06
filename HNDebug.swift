/*
 * Hanulim
 *
 * http://code.google.com/p/hanulim
 */

import Foundation

private let hnLogURL = URL(fileURLWithPath: "/tmp/hanulim.log")
private let hnLogQueue = DispatchQueue(label: "org.cocomelo.inputmethod.Hanulim.log")

func HNLog(_ message: @autoclosure () -> String) {
#if DEBUG
    let text = "\(Date()): \(message())\n"
    hnLogQueue.async {
        if let data = text.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: hnLogURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: hnLogURL)
            }
        }
    }
#endif
}
