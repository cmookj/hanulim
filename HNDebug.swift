/*
 * Hanulim
 *
 * Copyright (C) 2007-2017  Sanghyuk Suh <han9kin@mac.com>
 * Copyright (C) 2026  Changmook Chun <cmookj@duck.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
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
