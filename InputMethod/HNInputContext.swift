/*
 * Hanulim
 *
 * http://code.google.com/p/hanulim
 */

import Foundation
import InputMethodKit

// MARK: - Protocol

protocol HNICUserDefaults: AnyObject {
    var usesSmartQuotationMarks: Bool { get }
    var inputsBackSlashInsteadOfWon: Bool { get }
    var handlesCapsLockAsShift: Bool { get }
    var commitsImmediately: Bool { get }
    var usesDecomposedUnicode: Bool { get }
}

// MARK: - Constants

private let hnKeyCodeMax = 51
private let hnBufferSize = 1024

// MARK: - Enums

private enum HNKeyboardLayoutType: Int {
    case jamo = 0
    case jaso
}

private enum HNKeyboardLayoutScope: Int {
    case modern = 0
    case archaic
}

private enum HNKeyType: Int {
    case symbol = 0
    case initial = 1
    case medial = 2
    case final_ = 3
    case diacritic = 4
}

// MARK: - Key Code Helpers

private func hnKeyType(_ conv: UInt16) -> Int  { Int(conv >> 8) }
private func hnKeyValue(_ conv: UInt16) -> UInt8 { UInt8(conv & 0xff) }

// MARK: - Keyboard Layout

private struct HNKeyboardLayout {
    let name: String
    let type: HNKeyboardLayoutType
    let scope: HNKeyboardLayoutScope
    let value: [UInt32]   // hnKeyCodeMax entries
}

// MARK: - Jaso Composition

private struct HNJasoComposition {
    /// counts[0] = modern count, counts[1] = archaic count
    let counts: [Int]
    let input: [UInt16]
    let output: [UInt8]

    func count(for scope: HNKeyboardLayoutScope) -> Int { counts[scope.rawValue] }
}

// MARK: - Character

private struct HNCharacter {
    static let nilValue: UInt8 = 0xff

    var type:      UInt8 = 0
    var initial:   UInt8 = nilValue
    var medial:    UInt8 = nilValue
    var final_:    UInt8 = nilValue
    var diacritic: UInt8 = nilValue

    /// CH_VAL[index] – index 0=type, 1=initial, 2=medial, 3=final, 4=diacritic
    subscript(index: Int) -> UInt8 {
        get {
            switch index {
            case 0: return type
            case 1: return initial
            case 2: return medial
            case 3: return final_
            case 4: return diacritic
            default: return 0
            }
        }
        set {
            switch index {
            case 0: type = newValue
            case 1: initial = newValue
            case 2: medial = newValue
            case 3: final_ = newValue
            case 4: diacritic = newValue
            default: break
            }
        }
    }

    mutating func clear() {
        type = 0
        initial = HNCharacter.nilValue
        medial   = HNCharacter.nilValue
        final_   = HNCharacter.nilValue
        diacritic = HNCharacter.nilValue
    }

    /// Sets type = aType, value[aType] = aValue.
    mutating func set(type aType: Int, value aValue: UInt8) {
        type = UInt8(aType)
        self[aType] = aValue
    }
}

// MARK: - Keyboard Layout Table

private let hnKeyboardLayoutTable: [HNKeyboardLayout] = [
    HNKeyboardLayout(
        name: "org.cocomelo.inputmethod.Hanulim.2standard",
        type: .jamo, scope: .modern,
        value: [
            0x01070107, // a  (00)
            0x01030103, // s  (01)
            0x010c010c, // d  (02)
            0x01060106, // f  (03)
            0x02090209, // h  (04)
            0x01130113, // g  (05)
            0x01100110, // z  (06)
            0x01110111, // x  (07)
            0x010f010f, // c  (08)
            0x01120112, // v  (09)
            0x00000000,
            0x02120212, // b  (11)
            0x01090108, // q  (12)
            0x010e010d, // w  (13)
            0x01050104, // e  (14)
            0x01020101, // r  (15)
            0x020d020d, // y  (16)
            0x010b010a, // t  (17)
            0x00010011, // 1  (18)
            0x00200012, // 2  (19)
            0x00030013, // 3  (20)
            0x00040014, // 4  (21)
            0x00240016, // 6  (22)
            0x00050015, // 5  (23)
            0x000b001d, // =  (24)
            0x00080019, // 9  (25)
            0x00060017, // 7  (26)
            0x0025000d, // -  (27)
            0x000a0018, // 8  (28)
            0x00090010, // 0  (29)
            0x00290023, // ]  (30)
            0x02040202, // o  (31)
            0x02070207, // u  (32)
            0x00270021, // [  (33)
            0x02030203, // i  (34)
            0x02080206, // p  (35)
            0x00000000,
            0x02150215, // l  (37)
            0x02050205, // j  (38)
            0x00020007, // '  (39)
            0x02010201, // k  (40)
            0x001a001b, // ;  (41)
            0x0028002f, // \  (42)
            0x001c000c, // ,  (43)
            0x001f000f, // /  (44)
            0x020e020e, // n  (45)
            0x02130213, // m  (46)
            0x001e000e, // .  (47)
            0x00000000,
            0x00000000,
            0x002a0026, // `  (50)
        ]
    ),
    HNKeyboardLayout(
        name: "org.cocomelo.inputmethod.Hanulim.2archaic",
        type: .jamo, scope: .archaic,
        value: [
            0x01410107, // a  (00)
            0x015e0103, // s  (01)
            0x014d010c, // d  (02)
            0x011b0106, // f  (03)
            0x02230209, // h  (04)
            0x015a0113, // g  (05)
            0x013d0110, // z  (06)
            0x013f0111, // x  (07)
            0x014f010f, // c  (08)
            0x01510112, // v  (09)
            0x00000000,
            0x01550212, // b  (11)
            0x01090108, // q  (12)
            0x010e010d, // w  (13)
            0x01050104, // e  (14)
            0x01020101, // r  (15)
            0x0402020d, // y  (16)
            0x010b010a, // t  (17)
            0x00010011, // 1  (18)
            0x00200012, // 2  (19)
            0x00030013, // 3  (20)
            0x00040014, // 4  (21)
            0x00240016, // 6  (22)
            0x00050015, // 5  (23)
            0x000b001d, // =  (24)
            0x00080019, // 9  (25)
            0x00060017, // 7  (26)
            0x0025000d, // -  (27)
            0x000a0018, // 8  (28)
            0x00090010, // 0  (29)
            0x00290023, // ]  (30)
            0x02040202, // o  (31)
            0x04010207, // u  (32)
            0x00270021, // [  (33)
            0x02030203, // i  (34)
            0x02080206, // p  (35)
            0x00000000,
            0x02340215, // l  (37)
            0x02000205, // j  (38)
            0x00020007, // '  (39)
            0x023e0201, // k  (40)
            0x001a001b, // ;  (41)
            0x0028002f, // \  (42)
            0x001c000c, // ,  (43)
            0x001f000f, // /  (44)
            0x0156020e, // n  (45)
            0x02130213, // m  (46)
            0x001e000e, // .  (47)
            0x00000000,
            0x00000000,
            0x002a0026, // `  (50)
        ]
    ),
    HNKeyboardLayout(
        name: "org.cocomelo.inputmethod.Hanulim.3final",
        type: .jaso, scope: .modern,
        value: [
            0x03070315, // a  (00)
            0x03060304, // s  (01)
            0x030b0215, // d  (02)
            0x030a0201, // f  (03)
            0x00100103, // h  (04)
            0x02040213, // g  (05)
            0x03170310, // z  (06)
            0x03120301, // x  (07)
            0x03180206, // c  (08)
            0x03030209, // v  (09)
            0x00000000,
            0x001f020e, // b  (11)
            0x031a0313, // q  (12)
            0x03190308, // w  (13)
            0x03050207, // e  (14)
            0x030f0202, // r  (15)
            0x00150106, // y  (16)
            0x030c0205, // t  (17)
            0x0302031b, // 1  (18)
            0x03090314, // 2  (19)
            0x03160311, // 3  (20)
            0x030e020d, // 4  (21)
            0x001d0203, // 6  (22)
            0x030d0212, // 5  (23)
            0x000b001e, // =  (24)
            0x0007020e, // 9  (25)
            0x002c0208, // 7  (26)
            0x001b0009, // -  (27)
            0x002d0214, // 8  (28)
            0x002a0110, // 0  (29)
            0x000f001c, // ]  (30)
            0x0018010f, // o  (31)
            0x00160104, // u  (32)
            0x00050008, // [  (33)
            0x00170107, // i  (34)
            0x00190112, // p  (35)
            0x00000000,
            0x0013010d, // l  (37)
            0x0011010c, // j  (38)
            0x002b0111, // '  (39)
            0x00120101, // k  (40)
            0x00140108, // ;  (41)
            0x002f001a, // \  (42)
            0x000c000c, // ,  (43)
            0x00010209, // /  (44)
            0x000d010a, // n  (45)
            0x00020113, // m  (46)
            0x000e000e, // .  (47)
            0x00000000,
            0x00000000,
            0x002e000a, // `  (50)
        ]
    ),
    HNKeyboardLayout(
        name: "org.cocomelo.inputmethod.Hanulim.390",
        type: .jaso, scope: .modern,
        value: [
            0x03070315, // a  (00)
            0x03060304, // s  (01)
            0x03090215, // d  (02)
            0x03020201, // f  (03)
            0x00070103, // h  (04)
            0x000f0213, // g  (05)
            0x03170310, // z  (06)
            0x03120301, // x  (07)
            0x030a0206, // c  (08)
            0x030f0209, // v  (09)
            0x00000000,
            0x0001020e, // b  (11)
            0x031a0313, // q  (12)
            0x03190308, // w  (13)
            0x03180207, // e  (14)
            0x02040202, // r  (15)
            0x001c0106, // y  (16)
            0x001b0205, // t  (17)
            0x0316031b, // 1  (18)
            0x00200314, // 2  (19)
            0x00030311, // 3  (20)
            0x0004020d, // 4  (21)
            0x00240203, // 6  (22)
            0x00050212, // 5  (23)
            0x000b001d, // =  (24)
            0x0008020e, // 9  (25)
            0x00060208, // 7  (26)
            0x0025000d, // -  (27)
            0x000a0214, // 8  (28)
            0x00090110, // 0  (29)
            0x00290023, // ]  (30)
            0x0019010f, // o  (31)
            0x00170104, // u  (32)
            0x00270021, // [  (33)
            0x00180107, // i  (34)
            0x001e0112, // p  (35)
            0x00000000,
            0x0016010d, // l  (37)
            0x0014010c, // j  (38)
            0x00020111, // '  (39)
            0x00150101, // k  (40)
            0x001a0108, // ;  (41)
            0x0028002f, // \  (42)
            0x0012000c, // ,  (43)
            0x001f0209, // /  (44)
            0x0010010a, // n  (45)
            0x00110113, // m  (46)
            0x0013000e, // .  (47)
            0x00000000,
            0x00000000,
            0x002a0026, // `  (50)
        ]
    ),
    HNKeyboardLayout(
        name: "org.cocomelo.inputmethod.Hanulim.3noshift",
        type: .jaso, scope: .modern,
        value: [
            0x03150315, // a  (00)
            0x00210304, // s  (01)
            0x00230215, // d  (02)
            0x02010201, // f  (03)
            0x00070103, // h  (04)
            0x000f0213, // g  (05)
            0x000d0310, // z  (06)
            0x001d0301, // x  (07)
            0x002f0206, // c  (08)
            0x02090209, // v  (09)
            0x00000000,
            0x0001020e, // b  (11)
            0x03130313, // q  (12)
            0x03080308, // w  (13)
            0x02070207, // e  (14)
            0x02020202, // r  (15)
            0x001c0106, // y  (16)
            0x001b0205, // t  (17)
            0x0001031b, // 1  (18)
            0x00200314, // 2  (19)
            0x00030311, // 3  (20)
            0x0004020d, // 4  (21)
            0x00240203, // 6  (22)
            0x00050212, // 5  (23)
            0x000b0317, // =  (24)
            0x00080110, // 9  (25)
            0x00060208, // 7  (26)
            0x00250316, // -  (27)
            0x000a0214, // 8  (28)
            0x00090204, // 0  (29)
            0x0029031a, // ]  (30)
            0x0019010f, // o  (31)
            0x00170104, // u  (32)
            0x00270319, // [  (33)
            0x00180107, // i  (34)
            0x001e0112, // p  (35)
            0x00000000,
            0x0016010d, // l  (37)
            0x0014010c, // j  (38)
            0x00020111, // '  (39)
            0x00150101, // k  (40)
            0x001a0108, // ;  (41)
            0x00280318, // \  (42)
            0x0012000c, // ,  (43)
            0x001f0307, // /  (44)
            0x0010010a, // n  (45)
            0x00110113, // m  (46)
            0x0013000e, // .  (47)
            0x00000000,
            0x00000000,
            0x002a0026, // `  (50)
        ]
    ),
    HNKeyboardLayout(
        name: "org.cocomelo.inputmethod.Hanulim.393",
        type: .jaso, scope: .archaic,
        value: [
            0x03070315, // a  (00)
            0x03060304, // s  (01)
            0x03090215, // d  (02)
            0x03020201, // f  (03)
            0x00070103, // h  (04)
            0x023e0213, // g  (05)
            0x03170310, // z  (06)
            0x03120301, // x  (07)
            0x030a0206, // c  (08)
            0x030f0209, // v  (09)
            0x00000000,
            0x0001020e, // b  (11)
            0x031a0313, // q  (12)
            0x03190308, // w  (13)
            0x03180207, // e  (14)
            0x02040202, // r  (15)
            0x04020106, // y  (16)
            0x001b0205, // t  (17)
            0x0316031b, // 1  (18)
            0x03440314, // 2  (19)
            0x00030311, // 3  (20)
            0x0004020d, // 4  (21)
            0x00240203, // 6  (22)
            0x00050212, // 5  (23)
            0x000b001d, // =  (24)
            0x0008020e, // 9  (25)
            0x00060208, // 7  (26)
            0x0025000d, // -  (27)
            0x000a0214, // 8  (28)
            0x00090110, // 0  (29)
            0x00290023, // ]  (30)
            0x0156010f, // o  (31)
            0x04010104, // u  (32)
            0x00270021, // [  (33)
            0x01550107, // i  (34)
            0x001e0112, // p  (35)
            0x00000000,
            0x0151010d, // l  (37)
            0x014d010c, // j  (38)
            0x00020111, // '  (39)
            0x014f0101, // k  (40)
            0x001a0108, // ;  (41)
            0x0028002f, // \  (42)
            0x013d000c, // ,  (43)
            0x001f0209, // /  (44)
            0x0141010a, // n  (45)
            0x015a0113, // m  (46)
            0x013f000e, // .  (47)
            0x00000000,
            0x00000000,
            0x03490352, // `  (50)
        ]
    ),
]

// MARK: - Jaso Initial → Final Conversion Table

private let hnJasoInitialToFinal: [UInt8] = [
    0x00, // 00
    0x01, // 01 ㄱ
    0x02, // 02 ㄱㄱ
    0x04, // 03 ㄴ
    0x07, // 04 ㄷ
    0x5b, // 05 ㄷㄷ
    0x08, // 06 ㄹ
    0x10, // 07 ㅁ
    0x11, // 08 ㅂ
    0x74, // 09 ㅂㅂ
    0x13, // 0a ㅅ
    0x14, // 0b ㅅㅅ
    0x15, // 0c ㅇ
    0x16, // 0d ㅈ
    0x87, // 0e ㅈㅈ
    0x17, // 0f ㅊ
    0x18, // 10 ㅋ
    0x19, // 11 ㅌ
    0x1a, // 12 ㅍ
    0x1b, // 13 ㅎ
    0x1e, // 14 ㄴㄱ
    0x58, // 15 ㄴㄴ
    0x1f, // 16 ㄴㄷ
    0x00, // 17 ㄴㅂ
    0x23, // 18 ㄷㄱ
    0x26, // 19 ㄹㄴ
    0x29, // 1a ㄹㄹ
    0x0f, // 1b ㄹㅎ
    0x6b, // 1c ㄹㅇ
    0x35, // 1d ㅁㅂ
    0x3b, // 1e ㅁㅇ
    0x00, // 1f ㅂㄱ
    0x00, // 20 ㅂㄴ
    0x71, // 21 ㅂㄷ
    0x12, // 22 ㅂㅅ
    0x00, // 23 ㅂㅅㄱ
    0x75, // 24 ㅂㅅㄷ
    0x00, // 25 ㅂㅅㅂ
    0x00, // 26 ㅂㅅㅅ
    0x00, // 27 ㅂㅅㅈ
    0x76, // 28 ㅂㅈ
    0x77, // 29 ㅂㅊ
    0x00, // 2a ㅂㅌ
    0x3d, // 2b ㅂㅍ
    0x3f, // 2c ㅂㅇ
    0x00, // 2d ㅂㅂㅇ
    0x40, // 2e ㅅㄱ
    0x00, // 2f ㅅㄴ
    0x41, // 30 ㅅㄷ
    0x42, // 31 ㅅㄹ
    0x78, // 32 ㅅㅁ
    0x43, // 33 ㅅㅂ
    0x00, // 34 ㅅㅂㄱ
    0x00, // 35 ㅅㅅㅅ
    0x00, // 36 ㅅㅇ
    0x7d, // 37 ㅅㅈ
    0x7e, // 38 ㅅㅊ
    0x00, // 39 ㅅㅋ
    0x7f, // 3a ㅅㅌ
    0x00, // 3b ㅅㅍ
    0x80, // 3c ㅅㅎ
    0x00, // 3d
    0x00, // 3e
    0x00, // 3f
    0x00, // 40
    0x44, // 41 ㅿ
    0x00, // 42 ㅇㄱ
    0x00, // 43 ㅇㄷ
    0x00, // 44 ㅇㅁ
    0x00, // 45 ㅇㅂ
    0x00, // 46 ㅇㅅ
    0x00, // 47 ㅇㅿ
    0x00, // 48 ㅇㅇ
    0x00, // 49 ㅇㅈ
    0x00, // 4a ㅇㅊ
    0x00, // 4b ㅇㅌ
    0x00, // 4c ㅇㅍ
    0x49, // 4d ㆁ
    0x00, // 4e ㅈㅇ
    0x00, // 4f
    0x00, // 50
    0x00, // 51
    0x00, // 52
    0x00, // 53 ㅊㅋ
    0x00, // 54 ㅊㅎ
    0x00, // 55
    0x00, // 56
    0x4c, // 57 ㅍㅂ
    0x4d, // 58 ㅍㅇ
    0x00, // 59 ㅎㅎ
    0x52, // 5a ㆆ
    0x00, // 5b ㄱㄷ
    0x20, // 5c ㄴㅅ
    0x05, // 5d ㄴㅈ
    0x06, // 5e ㄴㅎ
    0x24, // 5f ㄷㄹ
    0x00, // 60 ㄷㅁ
    0x5d, // 61 ㄷㅂ
    0x5e, // 62 ㄷㅅ
    0x60, // 63 ㄷㅈ
    0x09, // 64 ㄹㄱ
    0x63, // 65 ㄹㄱㄱ
    0x27, // 66 ㄹㄷ
    0x00, // 67 ㄹㄷㄷ
    0x0a, // 68 ㄹㅁ
    0x0b, // 69 ㄹㅂ
    0x00, // 6a ㄹㅂㅂ
    0x2e, // 6b ㄹㅂㅇ
    0x0c, // 6c ㄹㅅ
    0x00, // 6d ㄹㅈ
    0x31, // 6e ㄹㅋ
    0x33, // 6f ㅁㄱ
    0x00, // 70 ㅁㄷ
    0x36, // 71 ㅁㅅ
    0x00, // 72 ㅂㅅㅌ
    0x00, // 73 ㅂㅋ
    0x3e, // 74 ㅂㅎ
    0x00, // 75 ㅅㅅㅂ
    0x00, // 76 ㅇㄹ
    0x00, // 77 ㅇㅎ
    0x00, // 78 ㅈㅈㅎ
    0x00, // 79 ㅌㅌ
    0x00, // 7a ㅍㅎ
    0x00, // 7b ㅎㅅ
    0x00, // 7c ㆆㆆ
]

// MARK: - Jaso Composition Tables

private let hnJasoCompositionInInitial: [UInt16] = [
    0x0101, 0x0404, 0x0808, 0x0a0a, 0x0d0d,
    // archaic
    0x0301, 0x0303, 0x0304, 0x0308, 0x0401, 0x0603, 0x0606, 0x0613, 0x060c, 0x0708,
    0x070c, 0x0801, 0x0803, 0x0804, 0x080a, 0x2201, 0x2204, 0x2208, 0x220a, 0x080b,
    0x220d, 0x080d, 0x080f, 0x0811, 0x0812, 0x080c, 0x090c, 0x0a01, 0x0a03, 0x0a04,
    0x0a06, 0x0a07, 0x0a08, 0x3301, 0x0a0b, 0x0b0a, 0x0a0c, 0x0a0d, 0x0a0f, 0x0a10,
    0x0a11, 0x0a12, 0x0a13, 0x3d3d, 0x3f3f, 0x0c01, 0x0c04, 0x0c07, 0x0c08, 0x0c0a,
    0x0c41, 0x0c0c, 0x0c0d, 0x0c0f, 0x0c11, 0x0c12, 0x0d0c, 0x4f4f, 0x5151, 0x0f10,
    0x0f13, 0x1208, 0x120c, 0x1313, 0x0104, 0x030a, 0x030d, 0x0313, 0x0406, 0x0407,
    0x0408, 0x040a, 0x040d, 0x0601, 0x0602, 0x6401, 0x0604, 0x0605, 0x6604, 0x0607,
    0x0608, 0x0609, 0x6908, 0x690c, 0x060a, 0x060d, 0x0610, 0x0701, 0x0704, 0x070a,
    0x2211, 0x0810, 0x0813, 0x0b08, 0x0c06, 0x0c13, 0x0e13, 0x1111, 0x1213, 0x130a,
    0x5a5a,
]

private let hnJasoCompositionOutInitial: [UInt8] = [
    0x02, 0x05, 0x09, 0x0b, 0x0e,
    // archaic
    0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d,
    0x1e, 0x1f, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x26,
    0x27, 0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e, 0x2f, 0x30,
    0x31, 0x32, 0x33, 0x34, 0x35, 0x35, 0x36, 0x37, 0x38, 0x39,
    0x3a, 0x3b, 0x3c, 0x3e, 0x40, 0x42, 0x43, 0x44, 0x45, 0x46,
    0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4e, 0x50, 0x52, 0x53,
    0x54, 0x57, 0x58, 0x59, 0x5b, 0x5c, 0x5d, 0x5e, 0x5f, 0x60,
    0x61, 0x62, 0x63, 0x64, 0x65, 0x65, 0x66, 0x67, 0x67, 0x68,
    0x69, 0x6a, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x71,
    0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x7b,
    0x7c,
]

private let hnJasoCompositionInMedial: [UInt16] = [
    0x0115, 0x0315, 0x0515, 0x0715, 0x0901, 0x0902, 0x0a15, 0x0915, 0x0e05, 0x0e06,
    0x0f15, 0x0e15, 0x1315,
    // archaic
    0x0109, 0x010e, 0x0309, 0x030d, 0x0509, 0x050e, 0x0513, 0x0709, 0x070e, 0x0905,
    0x0906, 0x1f15, 0x0908, 0x4815, 0x0909, 0x090e, 0x0d03, 0x0d04, 0x2415, 0x0d07,
    0x0d09, 0x0d15, 0x0e01, 0x0e02, 0x2915, 0x0f13, 0x0e08, 0x4d15, 0x0e0e, 0x1201,
    0x1205, 0x1206, 0x2f15, 0x1207, 0x1208, 0x3115, 0x120e, 0x1215, 0x130e, 0x1313,
    0x140e, 0x1501, 0x1503, 0x1509, 0x150e, 0x1513, 0x153e, 0x3e05, 0x3e0e, 0x3e15,
    0x3e3e, 0x0113, 0x030e, 0x0703, 0x0903, 0x0904, 0x4615, 0x0907, 0x2215, 0x0d01,
    0x0d02, 0x4a15, 0x0d05, 0x0e07, 0x1115, 0x1202, 0x2e15, 0x1209, 0x1301, 0x1305,
    0x1306, 0x5215, 0x1309, 0x3909, 0x3915, 0x1504, 0x1507, 0x1508, 0x5715, 0x3a15,
    0x150d, 0x1512, 0x1515, 0x3e01, 0x3e06, 0x3f15,
]

private let hnJasoCompositionOutMedial: [UInt8] = [
    0x02, 0x04, 0x06, 0x08, 0x0a, 0x0b, 0x0b, 0x0c, 0x0f, 0x10,
    0x10, 0x11, 0x14,
    // archaic
    0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
    0x20, 0x20, 0x21, 0x21, 0x22, 0x23, 0x24, 0x25, 0x25, 0x26,
    0x27, 0x28, 0x29, 0x2a, 0x2a, 0x2b, 0x2c, 0x2c, 0x2d, 0x2e,
    0x2f, 0x30, 0x30, 0x31, 0x32, 0x32, 0x33, 0x34, 0x35, 0x36,
    0x37, 0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x3f, 0x40, 0x41,
    0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x47, 0x48, 0x49, 0x4a,
    0x4b, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f, 0x4f, 0x50, 0x51, 0x52,
    0x53, 0x53, 0x54, 0x55, 0x56, 0x56, 0x57, 0x58, 0x58, 0x59,
    0x5a, 0x5b, 0x5c, 0x5d, 0x5e, 0x5e,
]

private let hnJasoCompositionInFinal: [UInt16] = [
    0x0101, 0x0113, 0x0416, 0x041b, 0x0801, 0x0810, 0x0811, 0x0813, 0x0819, 0x081a,
    0x081b, 0x1113, 0x1313,
    // archaic
    0x0108, 0x0301, 0x0401, 0x0407, 0x0413, 0x0444, 0x0419, 0x0701, 0x0708, 0x0803,
    0x0913, 0x0804, 0x0807, 0x271b, 0x0808, 0x0a01, 0x0a13, 0x0812, 0x0b13, 0x0b1b,
    0x0b15, 0x0814, 0x0844, 0x0818, 0x0852, 0x1001, 0x1008, 0x1011, 0x1013, 0x1014,
    0x3613, 0x1044, 0x1017, 0x101b, 0x1015, 0x1108, 0x111a, 0x111b, 0x1115, 0x1301,
    0x1307, 0x1308, 0x1311, 0x4901, 0x4902, 0x4501, 0x4949, 0x4918, 0x4913, 0x4944,
    0x1a11, 0x1a15, 0x1b04, 0x1b08, 0x1b10, 0x1b11, 0x0104, 0x0111, 0x0117, 0x0118,
    0x011b, 0x0404, 0x0408, 0x0417, 0x0707, 0x5b11, 0x0711, 0x0713, 0x5e01, 0x0716,
    0x0717, 0x0719, 0x0802, 0x0901, 0x091b, 0x2918, 0x0a1b, 0x0b07, 0x0b1a, 0x0849,
    0x321b, 0x0815, 0x1004, 0x6c04, 0x1010, 0x1012, 0x3513, 0x1016, 0x1107, 0x110e,
    0x3c1a, 0x1110, 0x1111, 0x1207, 0x1116, 0x1117, 0x1310, 0x4315, 0x1401, 0x1407,
    0x1344, 0x1316, 0x1317, 0x1319, 0x131b, 0x4411, 0x8115, 0x4910, 0x491b, 0x1611,
    0x1674, 0x8511, 0x1616, 0x1a13, 0x1a19,
]

private let hnJasoCompositionOutFinal: [UInt8] = [
    0x02, 0x03, 0x05, 0x06, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e,
    0x0f, 0x12, 0x14,
    // archaic
    0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25,
    0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x2c, 0x2d,
    0x2e, 0x2f, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
    0x37, 0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f, 0x40,
    0x41, 0x42, 0x43, 0x45, 0x46, 0x46, 0x47, 0x48, 0x4a, 0x4b,
    0x4c, 0x4d, 0x4e, 0x4f, 0x50, 0x51, 0x53, 0x54, 0x55, 0x56,
    0x57, 0x58, 0x59, 0x5a, 0x5b, 0x5c, 0x5d, 0x5e, 0x5f, 0x60,
    0x61, 0x62, 0x63, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
    0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x6f, 0x70, 0x71, 0x72,
    0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x7b,
    0x7c, 0x7d, 0x7e, 0x7f, 0x80, 0x81, 0x82, 0x83, 0x84, 0x85,
    0x86, 0x86, 0x87, 0x88, 0x89,
]

private let hnJasoCompositionTable: [HNJasoComposition] = [
    HNJasoComposition(counts: [0, 0], input: [], output: []),                                             // index 0: unused (Symbol)
    HNJasoComposition(counts: [5, 106], input: hnJasoCompositionInInitial, output: hnJasoCompositionOutInitial),  // Initial
    HNJasoComposition(counts: [13, 99], input: hnJasoCompositionInMedial, output: hnJasoCompositionOutMedial),   // Medial
    HNJasoComposition(counts: [13, 128], input: hnJasoCompositionInFinal, output: hnJasoCompositionOutFinal),    // Final
]

// MARK: - Unicode Tables

private let hnUnicodeSymbolMax = 0x30

private let hnUnicodeSymbol: [UInt16] = [
    0x0000, // 00 N/A
    0x0021, // 01 !
    0x0022, // 02 "
    0x0023, // 03 #
    0x0024, // 04 $
    0x0025, // 05 %
    0x0026, // 06 &
    0x0027, // 07 '
    0x0028, // 08 (
    0x0029, // 09 )
    0x002a, // 0a *
    0x002b, // 0b +
    0x002c, // 0c ,
    0x002d, // 0d -
    0x002e, // 0e .
    0x002f, // 0f /
    0x0030, // 10 0
    0x0031, // 11 1
    0x0032, // 12 2
    0x0033, // 13 3
    0x0034, // 14 4
    0x0035, // 15 5
    0x0036, // 16 6
    0x0037, // 17 7
    0x0038, // 18 8
    0x0039, // 19 9
    0x003a, // 1a :
    0x003b, // 1b ;
    0x003c, // 1c <
    0x003d, // 1d =
    0x003e, // 1e >
    0x003f, // 1f ?
    0x0040, // 20 @
    0x005b, // 21 [
    0x005c, // 22 \
    0x005d, // 23 ]
    0x005e, // 24 ^
    0x005f, // 25 _
    0x0060, // 26 `
    0x007b, // 27 {
    0x007c, // 28 |
    0x007d, // 29 }
    0x007e, // 2a ~
    0x00b7, // 2b ·
    0x201c, // 2c "
    0x201d, // 2d "
    0x203b, // 2e ※
    0xffe6, // 2f ￦
]

private let hnUnicodeJamoInitial: [UInt16] = [
    0x0000, // 00
    0x3131, // 01 ㄱ
    0x3132, // 02 ㄲ
    0x3134, // 03 ㄴ
    0x3137, // 04 ㄷ
    0x3138, // 05 ㄸ
    0x3139, // 06 ㄹ
    0x3141, // 07 ㅁ
    0x3142, // 08 ㅂ
    0x3143, // 09 ㅃ
    0x3145, // 0a ㅅ
    0x3146, // 0b ㅆ
    0x3147, // 0c ㅇ
    0x3148, // 0d ㅈ
    0x3149, // 0e ㅉ
    0x314a, // 0f ㅊ
    0x314b, // 10 ㅋ
    0x314c, // 11 ㅌ
    0x314d, // 12 ㅍ
    0x314e, // 13 ㅎ
]

private let hnUnicodeJamoMedial: [UInt16] = [
    0x0000, // 00
    0x314f, // 01 ㅏ
    0x3150, // 02 ㅐ
    0x3151, // 03 ㅑ
    0x3152, // 04 ㅒ
    0x3153, // 05 ㅓ
    0x3154, // 06 ㅔ
    0x3155, // 07 ㅕ
    0x3156, // 08 ㅖ
    0x3157, // 09 ㅗ
    0x3158, // 0a ㅘ
    0x3159, // 0b ㅙ
    0x315a, // 0c ㅚ
    0x315b, // 0d ㅛ
    0x315c, // 0e ㅜ
    0x315d, // 0f ㅝ
    0x315e, // 10 ㅞ
    0x315f, // 11 ㅟ
    0x3160, // 12 ㅠ
    0x3161, // 13 ㅡ
    0x3162, // 14 ㅢ
    0x3163, // 15 ㅣ
]

private let hnUnicodeJamoFinal: [UInt16] = [
    0x0000, // 00
    0x3131, // 01 ㄱ
    0x3132, // 02 ㄲ
    0x3133, // 03 ㄳ
    0x3134, // 04 ㄴ
    0x3135, // 05 ㄵ
    0x3136, // 06 ㄶ
    0x3137, // 07 ㄷ
    0x3139, // 08 ㄹ
    0x313a, // 09 ㄺ
    0x313b, // 0a ㄻ
    0x313c, // 0b ㄼ
    0x313d, // 0c ㄽ
    0x313e, // 0d ㄾ
    0x313f, // 0e ㄿ
    0x3140, // 0f ㅀ
    0x3141, // 10 ㅁ
    0x3142, // 11 ㅂ
    0x3144, // 12 ㅄ
    0x3145, // 13 ㅅ
    0x3146, // 14 ㅆ
    0x3147, // 15 ㅇ
    0x3148, // 16 ㅈ
    0x314a, // 17 ㅊ
    0x314b, // 18 ㅋ
    0x314c, // 19 ㅌ
    0x314d, // 1a ㅍ
    0x314e, // 1b ㅎ
]

private let hnUnicodeJamo: [[UInt16]] = [
    [],                    // index 0: unused
    hnUnicodeJamoInitial,  // HNKeyType.initial
    hnUnicodeJamoMedial,   // HNKeyType.medial
    hnUnicodeJamoFinal,    // HNKeyType.final_
]

private let hnUnicodeJasoInitial: [UInt16] = [
    0x115f, // 00
    0x1100, // 01 ㄱ
    0x1101, // 02 ㄱㄱ
    0x1102, // 03 ㄴ
    0x1103, // 04 ㄷ
    0x1104, // 05 ㄷㄷ
    0x1105, // 06 ㄹ
    0x1106, // 07 ㅁ
    0x1107, // 08 ㅂ
    0x1108, // 09 ㅂㅂ
    0x1109, // 0a ㅅ
    0x110a, // 0b ㅅㅅ
    0x110b, // 0c ㅇ
    0x110c, // 0d ㅈ
    0x110d, // 0e ㅈㅈ
    0x110e, // 0f ㅊ
    0x110f, // 10 ㅋ
    0x1110, // 11 ㅌ
    0x1111, // 12 ㅍ
    0x1112, // 13 ㅎ
    0x1113, // 14 ㄴㄱ
    0x1114, // 15 ㄴㄴ
    0x1115, // 16 ㄴㄷ
    0x1116, // 17 ㄴㅂ
    0x1117, // 18 ㄷㄱ
    0x1118, // 19 ㄹㄴ
    0x1119, // 1a ㄹㄹ
    0x111a, // 1b ㄹㅎ
    0x111b, // 1c ㄹㅇ
    0x111c, // 1d ㅁㅂ
    0x111d, // 1e ㅁㅇ
    0x111e, // 1f ㅂㄱ
    0x111f, // 20 ㅂㄴ
    0x1120, // 21 ㅂㄷ
    0x1121, // 22 ㅂㅅ
    0x1122, // 23 ㅂㅅㄱ
    0x1123, // 24 ㅂㅅㄷ
    0x1124, // 25 ㅂㅅㅂ
    0x1125, // 26 ㅂㅅㅅ
    0x1126, // 27 ㅂㅅㅈ
    0x1127, // 28 ㅂㅈ
    0x1128, // 29 ㅂㅊ
    0x1129, // 2a ㅂㅌ
    0x112a, // 2b ㅂㅍ
    0x112b, // 2c ㅂㅇ
    0x112c, // 2d ㅂㅂㅇ
    0x112d, // 2e ㅅㄱ
    0x112e, // 2f ㅅㄴ
    0x112f, // 30 ㅅㄷ
    0x1130, // 31 ㅅㄹ
    0x1131, // 32 ㅅㅁ
    0x1132, // 33 ㅅㅂ
    0x1133, // 34 ㅅㅂㄱ
    0x1134, // 35 ㅅㅅㅅ
    0x1135, // 36 ㅅㅇ
    0x1136, // 37 ㅅㅈ
    0x1137, // 38 ㅅㅊ
    0x1138, // 39 ㅅㅋ
    0x1139, // 3a ㅅㅌ
    0x113a, // 3b ㅅㅍ
    0x113b, // 3c ㅅㅎ
    0x113c, // 3d
    0x113d, // 3e
    0x113e, // 3f
    0x113f, // 40
    0x1140, // 41 ㅿ
    0x1141, // 42 ㅇㄱ
    0x1142, // 43 ㅇㄷ
    0x1143, // 44 ㅇㅁ
    0x1144, // 45 ㅇㅂ
    0x1145, // 46 ㅇㅅ
    0x1146, // 47 ㅇㅿ
    0x1147, // 48 ㅇㅇ
    0x1148, // 49 ㅇㅈ
    0x1149, // 4a ㅇㅊ
    0x114a, // 4b ㅇㅌ
    0x114b, // 4c ㅇㅍ
    0x114c, // 4d ㆁ
    0x114d, // 4e ㅈㅇ
    0x114e, // 4f
    0x114f, // 50
    0x1150, // 51
    0x1151, // 52
    0x1152, // 53 ㅊㅋ
    0x1153, // 54 ㅊㅎ
    0x1154, // 55
    0x1155, // 56
    0x1156, // 57 ㅍㅂ
    0x1157, // 58 ㅍㅇ
    0x1158, // 59 ㅎㅎ
    0x1159, // 5a ㆆ
    0x115a, // 5b ㄱㄷ
    0x115b, // 5c ㄴㅅ
    0x115c, // 5d ㄴㅈ
    0x115d, // 5e ㄴㅎ
    0x115e, // 5f ㄷㄹ
    0xa960, // 60 ㄷㅁ
    0xa961, // 61 ㄷㅂ
    0xa962, // 62 ㄷㅅ
    0xa963, // 63 ㄷㅈ
    0xa964, // 64 ㄹㄱ
    0xa965, // 65 ㄹㄱㄱ
    0xa966, // 66 ㄹㄷ
    0xa967, // 67 ㄹㄷㄷ
    0xa968, // 68 ㄹㅁ
    0xa969, // 69 ㄹㅂ
    0xa96a, // 6a ㄹㅂㅂ
    0xa96b, // 6b ㄹㅂㅇ
    0xa96c, // 6c ㄹㅅ
    0xa96d, // 6d ㄹㅈ
    0xa96e, // 6e ㄹㅋ
    0xa96f, // 6f ㅁㄱ
    0xa970, // 70 ㅁㄷ
    0xa971, // 71 ㅁㅅ
    0xa972, // 72 ㅂㅅㅌ
    0xa973, // 73 ㅂㅋ
    0xa974, // 74 ㅂㅎ
    0xa975, // 75 ㅅㅅㅂ
    0xa976, // 76 ㅇㄹ
    0xa977, // 77 ㅇㅎ
    0xa978, // 78 ㅈㅈㅎ
    0xa979, // 79 ㅌㅌ
    0xa97a, // 7a ㅍㅎ
    0xa97b, // 7b ㅎㅅ
    0xa97c, // 7c ㆆㆆ
]

private let hnUnicodeJasoMedial: [UInt16] = [
    0x1160, // 00
    0x1161, // 01 ㅏ
    0x1162, // 02 ㅏㅣ (ㅐ)
    0x1163, // 03 ㅑ
    0x1164, // 04 ㅑㅣ (ㅒ)
    0x1165, // 05 ㅓ
    0x1166, // 06 ㅓㅣ (ㅔ)
    0x1167, // 07 ㅕ
    0x1168, // 08 ㅕㅣ (ㅖ)
    0x1169, // 09 ㅗ
    0x116a, // 0a ㅗㅏ (ㅘ)
    0x116b, // 0b ㅗㅏㅣ (ㅙ)
    0x116c, // 0c ㅗㅣ (ㅚ)
    0x116d, // 0d ㅛ
    0x116e, // 0e ㅜ
    0x116f, // 0f ㅜㅓ (ㅝ)
    0x1170, // 10 ㅜㅓㅣ (ㅞ)
    0x1171, // 11 ㅜㅣ (ㅟ)
    0x1172, // 12 ㅠ
    0x1173, // 13 ㅡ
    0x1174, // 14 ㅡㅣ (ㅢ)
    0x1175, // 15 ㅣ
    0x1176, // 16 ㅏㅗ
    0x1177, // 17 ㅏㅜ
    0x1178, // 18 ㅑㅗ
    0x1179, // 19 ㅑㅛ
    0x117a, // 1a ㅓㅗ
    0x117b, // 1b ㅓㅜ
    0x117c, // 1c ㅓㅡ
    0x117d, // 1d ㅕㅗ
    0x117e, // 1e ㅕㅜ
    0x117f, // 1f ㅗㅓ
    0x1180, // 20 ㅗㅓㅣ
    0x1181, // 21 ㅗㅕㅣ
    0x1182, // 22 ㅗㅗ
    0x1183, // 23 ㅗㅜ
    0x1184, // 24 ㅛㅑ
    0x1185, // 25 ㅛㅏㅣ
    0x1186, // 26 ㅛㅕ
    0x1187, // 27 ㅛㅗ
    0x1188, // 28 ㅛㅣ
    0x1189, // 29 ㅜㅏ
    0x118a, // 2a ㅜㅏㅣ
    0x118b, // 2b ㅜㅓㅡ
    0x118c, // 2c ㅜㅕㅣ
    0x118d, // 2d ㅜㅜ
    0x118e, // 2e ㅠㅏ
    0x118f, // 2f ㅠㅓ
    0x1190, // 30 ㅠㅓㅣ
    0x1191, // 31 ㅠㅕ
    0x1192, // 32 ㅠㅕㅣ
    0x1193, // 33 ㅠㅜ
    0x1194, // 34 ㅠㅣ
    0x1195, // 35 ㅡㅜ
    0x1196, // 36 ㅡㅡ
    0x1197, // 37 ㅡㅣㅜ
    0x1198, // 38 ㅣㅏ
    0x1199, // 39 ㅣㅑ
    0x119a, // 3a ㅣㅗ
    0x119b, // 3b ㅣㅜ
    0x119c, // 3c ㅣㅡ
    0x119d, // 3d ㅣㆍ
    0x119e, // 3e ㆍ
    0x119f, // 3f ㆍㅓ
    0x11a0, // 40 ㆍㅜ
    0x11a1, // 41 ㆍㅣ
    0x11a2, // 42 ㆍㆍ
    0x11a3, // 43 ㅏㅡ
    0x11a4, // 44 ㅑㅜ
    0x11a5, // 45 ㅕㅑ
    0x11a6, // 46 ㅗㅑ
    0x11a7, // 47 ㅗㅑㅣ
    0xd7b0, // 48 ㅗㅕ
    0xd7b1, // 49 ㅗㅗㅣ
    0xd7b2, // 4a ㅛㅏ
    0xd7b3, // 4b ㅛㅏㅣ
    0xd7b4, // 4c ㅛㅓ
    0xd7b5, // 4d ㅜㅕ
    0xd7b6, // 4e ㅜㅣㅣ
    0xd7b7, // 4f ㅠㅏㅣ
    0xd7b8, // 50 ㅠㅗ
    0xd7b9, // 51 ㅡㅏ
    0xd7ba, // 52 ㅡㅓ
    0xd7bb, // 53 ㅡㅓㅣ
    0xd7bc, // 54 ㅡㅗ
    0xd7bd, // 55 ㅣㅑㅗ
    0xd7be, // 56 ㅣㅑㅣ
    0xd7bf, // 57 ㅣㅕ
    0xd7c0, // 58 ㅣㅕㅣ
    0xd7c1, // 59 ㅣㅗㅣ
    0xd7c2, // 5a ㅣㅛ
    0xd7c3, // 5b ㅣㅠ
    0xd7c4, // 5c ㅣㅣ
    0xd7c5, // 5d ㆍㅏ
    0xd7c6, // 5e ㆍㅓㅣ
]

private let hnUnicodeJasoFinal: [UInt16] = [
    0x0000, // 00
    0x11a8, // 01 ㄱ
    0x11a9, // 02 ㄱㄱ
    0x11aa, // 03 ㄱㅅ
    0x11ab, // 04 ㄴ
    0x11ac, // 05 ㄴㅈ
    0x11ad, // 06 ㄴㅎ
    0x11ae, // 07 ㄷ
    0x11af, // 08 ㄹ
    0x11b0, // 09 ㄹㄱ
    0x11b1, // 0a ㄹㅁ
    0x11b2, // 0b ㄹㅂ
    0x11b3, // 0c ㄹㅅ
    0x11b4, // 0d ㄹㅌ
    0x11b5, // 0e ㄹㅍ
    0x11b6, // 0f ㄹㅎ
    0x11b7, // 10 ㅁ
    0x11b8, // 11 ㅂ
    0x11b9, // 12 ㅂㅅ
    0x11ba, // 13 ㅅ
    0x11bb, // 14 ㅅㅅ
    0x11bc, // 15 ㅇ
    0x11bd, // 16 ㅈ
    0x11be, // 17 ㅊ
    0x11bf, // 18 ㅋ
    0x11c0, // 19 ㅌ
    0x11c1, // 1a ㅍ
    0x11c2, // 1b ㅎ
    0x11c3, // 1c ㄱㄹ
    0x11c4, // 1d ㄱㅅㄱ
    0x11c5, // 1e ㄴㄱ
    0x11c6, // 1f ㄴㄷ
    0x11c7, // 20 ㄴㅅ
    0x11c8, // 21 ㄴㅿ
    0x11c9, // 22 ㅅㅌ (note: original comment says ㅅㅌ)
    0x11ca, // 23 ㄷㄱ
    0x11cb, // 24 ㄷㄹ
    0x11cc, // 25 ㄹㄱㅅ
    0x11cd, // 26 ㄹㄴ
    0x11ce, // 27 ㄹㄷ
    0x11cf, // 28 ㄹㄷㅎ
    0x11d0, // 29 ㄹㄹ
    0x11d1, // 2a ㄹㅁㄱ
    0x11d2, // 2b ㄹㅁㅅ
    0x11d3, // 2c ㄹㅂㅅ
    0x11d4, // 2d ㄹㅂㅎ
    0x11d5, // 2e ㄹㅂㅇ
    0x11d6, // 2f ㄹㅅㅅ
    0x11d7, // 30 ㄹㅿ
    0x11d8, // 31 ㄹㅋ
    0x11d9, // 32 ㄹㆆ
    0x11da, // 33 ㅁㄱ
    0x11db, // 34 ㅁㄹ
    0x11dc, // 35 ㅁㅂ
    0x11dd, // 36 ㅁㅅ
    0x11de, // 37 ㅁㅅㅅ
    0x11df, // 38 ㅁㅿ
    0x11e0, // 39 ㅁㅊ
    0x11e1, // 3a ㅁㅎ
    0x11e2, // 3b ㅁㅇ
    0x11e3, // 3c ㅂㄹ
    0x11e4, // 3d ㅂㅍ
    0x11e5, // 3e ㅂㅎ
    0x11e6, // 3f ㅂㅇ
    0x11e7, // 40 ㅅㄱ
    0x11e8, // 41 ㅅㄷ
    0x11e9, // 42 ㅅㄹ
    0x11ea, // 43 ㅅㅂ
    0x11eb, // 44 ㅿ
    0x11ec, // 45 ㆁㄱ
    0x11ed, // 46 ㆁㄱㄱ
    0x11ee, // 47 ㆁㆁ
    0x11ef, // 48 ㆁㅋ
    0x11f0, // 49 ㆁ
    0x11f1, // 4a ㆁㅅ
    0x11f2, // 4b ㆁㅿ
    0x11f3, // 4c ㅍㅂ
    0x11f4, // 4d ㅍㅇ
    0x11f5, // 4e ㅎㄴ
    0x11f6, // 4f ㅎㄹ
    0x11f7, // 50 ㅎㅁ
    0x11f8, // 51 ㅎㅂ
    0x11f9, // 52 ㆆ
    0x11fa, // 53 ㄱㄴ
    0x11fb, // 54 ㄱㅂ
    0x11fc, // 55 ㄱㅊ
    0x11fd, // 56 ㄱㅋ
    0x11fe, // 57 ㄱㅎ
    0x11ff, // 58 ㄴㄴ
    0xd7cb, // 59 ㄴㄹ
    0xd7cc, // 5a ㄴㅊ
    0xd7cd, // 5b ㄷㄷ
    0xd7ce, // 5c ㄷㄷㅂ
    0xd7cf, // 5d ㄷㅂ
    0xd7d0, // 5e ㄷㅅ
    0xd7d1, // 5f ㄷㅅㄱ
    0xd7d2, // 60 ㄷㅈ
    0xd7d3, // 61 ㄷㅊ
    0xd7d4, // 62 ㄷㅌ
    0xd7d5, // 63 ㄹㄱㄱ
    0xd7d6, // 64 ㄹㄱㅎ
    0xd7d7, // 65 ㄹㄹㅋ
    0xd7d8, // 66 ㄹㅁㅎ
    0xd7d9, // 67 ㄹㅂㄷ
    0xd7da, // 68 ㄹㅂㅍ
    0xd7db, // 69 ㄹㆁ
    0xd7dc, // 6a ㄹㆆㅎ
    0xd7dd, // 6b ㄹㅇ
    0xd7de, // 6c ㅁㄴ
    0xd7df, // 6d ㅁㄴㄴ
    0xd7e0, // 6e ㅁㅁ
    0xd7e1, // 6f ㅁㅂㅅ
    0xd7e2, // 70 ㅁㅈ
    0xd7e3, // 71 ㅂㄷ
    0xd7e4, // 72 ㅂㄹㅍ
    0xd7e5, // 73 ㅂㅁ
    0xd7e6, // 74 ㅂㅂ
    0xd7e7, // 75 ㅂㅅㄷ
    0xd7e8, // 76 ㅂㅈ
    0xd7e9, // 77 ㅂㅊ
    0xd7ea, // 78 ㅅㅁ
    0xd7eb, // 79 ㅅㅂㅇ
    0xd7ec, // 7a ㅅㅅㄱ
    0xd7ed, // 7b ㅅㅅㄷ
    0xd7ee, // 7c ㅅㅿ
    0xd7ef, // 7d ㅅㅈ
    0xd7f0, // 7e ㅅㅊ
    0xd7f1, // 7f ㅅㅌ
    0xd7f2, // 80 ㅅㅎ
    0xd7f3, // 81 ㅿㅂ
    0xd7f4, // 82 ㅿㅂㅇ
    0xd7f5, // 83 ㆁㅁ
    0xd7f6, // 84 ㆁㅎ
    0xd7f7, // 85 ㅈㅂ
    0xd7f8, // 86 ㅈㅂㅂ
    0xd7f9, // 87 ㅈㅈ
    0xd7fa, // 88 ㅍㅅ
    0xd7fb, // 89 ㅍㅌ
]

private let hnUnicodeJaso: [[UInt16]] = [
    [],                    // index 0: unused
    hnUnicodeJasoInitial,  // HNKeyType.initial
    hnUnicodeJasoMedial,   // HNKeyType.medial
    hnUnicodeJasoFinal,    // HNKeyType.final_
]

// MARK: - Modifier key mask (equivalent to C static NSDeviceIndependentModifierFlagsMask & ~(shift | capsLock))

private let hnHandlableMask: UInt = {
    let all = NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
    let excluded = NSEvent.ModifierFlags([.shift, .capsLock]).rawValue
    return all & ~excluded
}()

// MARK: - HNInputContext

class HNInputContext {

    private static let romanModeID = "org.cocomelo.inputmethod.Hanulim.Roman"

    private var keyboardLayout: HNKeyboardLayout?
    var userDefaults: (any HNICUserDefaults)?

    /// True when the Roman (Latin bypass) mode is active.
    /// Set by setKeyboardLayout, which is called from setValue:forTag:client:
    /// after TISSelectInputSource successfully switches modes.
    private(set) var isRomanMode: Bool = false

    /// The last non-Roman input mode, used to restore when exiting Roman mode.
    private(set) var lastKoreanModeID: String = "org.cocomelo.inputmethod.Hanulim.2standard"

    var composedString: String?

    private var singleQuot: Int = 1
    private var doubleQuot: Int = 1

    private var keyBuffer: [UInt16] = []

    // MARK: - Public API

    func setKeyboardLayout(name: String) {
        if name == HNInputContext.romanModeID {
            isRomanMode = true
        } else {
            isRomanMode = false
            lastKoreanModeID = name
            keyboardLayout = hnKeyboardLayoutTable.first { $0.name == name }
        }
    }

    // Returns true if the key was handled.
    func handleKey(string: String, keyCode: Int, modifiers: Int, client: (any IMKTextInput)?) -> Bool {
        if isRomanMode {
            // Return false so handle(_:client:) in HNInputController also
            // returns false, re-dispatching the raw NSEvent to the app's
            // keyDown: — the correct path for terminal emulators like Ghostty.
            return false
        }
        let couldHandle = self.couldHandle(modifiers: modifiers)
        let keyConv: UInt16 = couldHandle ? keyboardCode(keyCode: keyCode, modifiers: modifiers) : 0

        if keyConv != 0 {
            if hnKeyType(keyConv) == HNKeyType.symbol.rawValue {
                var symbol = hnUnicodeSymbol[Int(hnKeyValue(keyConv))]

                if let ud = userDefaults, ud.usesSmartQuotationMarks {
                    symbol = quotationMark(for: symbol)
                }
                if let ud = userDefaults, ud.inputsBackSlashInsteadOfWon, symbol == 0xffe6 {
                    symbol = 0x005c
                }

                commitComposition(client: client)
                commitBuffer(client: client, chars: [symbol], processedKeyCount: 0)

            } else if keyBuffer.count < hnBufferSize {
                keyBuffer.append(keyConv)
                compose(client: client)
                updateComposition(client: client)

            } else {
                HNLog("HANULIM ERROR: Buffer overflow. Key ignored.")
            }
            return true

        } else if couldHandle && !keyBuffer.isEmpty {
            guard let firstChar = string.unicodeScalars.first else {
                commitComposition(client: client)
                return false
            }

            let character = firstChar.value

            switch character {
            case 0x08: // delete
                if !keyBuffer.isEmpty { keyBuffer.removeLast() }
                compose(client: client)
                updateComposition(client: client)
                return true

            case 0x09: // tab
                if client?.bundleIdentifier() == "com.apple.Terminal" {
                    HNLog("Terminal Tab")
                    commitComposition(client: client)
                    return false
                }
                // tab in non-Terminal: fall through to default handling below

            case 0x1c, 0x1d, 0x1e, 0x1f: // arrow keys
                if client?.bundleIdentifier() == "com.microsoft.Word" {
                    commitComposition(client: client)
                    return true
                }

            default:
                HNLog("HNInputContext HNICHandleKey character: \(String(format: "%#x", character))")
            }
        }

        commitComposition(client: client)
        return false
    }

    func commitComposition(client: (any IMKTextInput)?) {
        guard let str = composedString else { return }

        HNLog("HNInputContext HNICCommitComposition ## insertText: \(str)")
        client?.insertText(str, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))

        composedString = nil
        keyBuffer.removeAll()
    }

    func updateComposition(client: (any IMKTextInput)?) {
        guard let str = composedString else { return }

        HNLog("HNInputContext HNICUpdateComposition ## setMarkedText: \(str)")
        client?.setMarkedText(
            str,
            selectionRange: NSRange(location: str.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
    }

    func cancelComposition() {
        composedString = nil
        keyBuffer.removeAll()
    }

    // MARK: - Private: Key handling helpers

    private func couldHandle(modifiers: Int) -> Bool {
        return (UInt(bitPattern: modifiers) & hnHandlableMask) == 0
    }

    private func keyboardCode(keyCode: Int, modifiers: Int) -> UInt16 {
        guard let layout = keyboardLayout else { return 0 }

        let flags = NSEvent.ModifierFlags(rawValue: UInt(bitPattern: modifiers))
        let isShifted = flags.contains(.shift) ||
            (flags.contains(.capsLock) && (userDefaults?.handlesCapsLockAsShift ?? false))
        let shift: UInt32 = isShifted ? 16 : 0

        guard keyCode >= 0, keyCode < hnKeyCodeMax else { return 0 }

        let keyConv = UInt16(truncatingIfNeeded: layout.value[keyCode] >> shift)
        let type = hnKeyType(keyConv)
        let value = Int(hnKeyValue(keyConv))

        if type != HNKeyType.symbol.rawValue ||
           (value < hnUnicodeSymbolMax && hnUnicodeSymbol[value] != 0) {
            return keyConv
        }
        return 0
    }

    // MARK: - Private: Jaso composition

    private func jasoCompose(type: Int, v1: UInt8, v2: UInt8) -> UInt8 {
        guard type >= HNKeyType.initial.rawValue, type <= HNKeyType.final_.rawValue else {
            return HNCharacter.nilValue
        }
        let table = hnJasoCompositionTable[type]
        let scope = keyboardLayout?.scope ?? .modern
        let count = table.count(for: scope)
        let sIn = UInt16(v1) << 8 | UInt16(v2)

        for i in 0..<count {
            if table.input[i] == sIn { return table.output[i] }
        }
        return HNCharacter.nilValue
    }

    // MARK: - Private: Character composition

    /// Produces the Unicode code units for a composed HNCharacter.
    private func composeCharacter(_ char: HNCharacter) -> [UInt16] {
        let maxNFC: [UInt8] = [0x00, 0x13, 0x15, 0x1b]
        let maxNFD: [UInt8] = [0x00, 0x7c, 0x5e, 0x89]
        let diacritics: [UInt16] = [0x0000, 0x302e, 0x302f]

        let isArchaic = keyboardLayout?.scope == .archaic
        let isNFD = userDefaults?.usesDecomposedUnicode ?? false

        if isArchaic || isNFD {
            // Unicode NFD (첫가끝코드)
            var output = [UInt16](repeating: 0, count: 4)
            var length = 0

            for i in HNKeyType.initial.rawValue...HNKeyType.final_.rawValue {
                let val = char[i]
                if val <= maxNFD[i] {
                    output[i - 1] = hnUnicodeJaso[i][Int(val)]
                    length = i
                } else {
                    output[i - 1] = hnUnicodeJaso[i][0]
                }
            }

            var result = Array(output.prefix(length))

            if char.diacritic != HNCharacter.nilValue {
                if length < 2 { length = 2; result = Array(output.prefix(2)) }
                result.append(diacritics[Int(char.diacritic)])
            }
            return result

        } else {
            // Unicode NFC
            var sChar = char
            var count = 0
            var topType = 0

            for i in HNKeyType.initial.rawValue...HNKeyType.final_.rawValue {
                if sChar[i] <= maxNFC[i] { count += 1; topType = i }
            }

            if count == 3 {
                // 초성 + 중성 + 종성
                let syllable = 0xac00
                    + (Int(sChar.initial) - 1) * 21 * 28
                    + (Int(sChar.medial)  - 1) * 28
                    + Int(sChar.final_)
                return [UInt16(syllable)]

            } else if count == 2, topType < HNKeyType.final_.rawValue {
                // 초성 + 중성
                let syllable = 0xac00
                    + (Int(sChar.initial) - 1) * 21 * 28
                    + (Int(sChar.medial)  - 1) * 28
                return [UInt16(syllable)]

            } else if count == 1 {
                // 자모
                return [hnUnicodeJamo[topType][Int(sChar[topType])]]
            }
            return []
        }
    }

    private func quotationMark(for char: UInt16) -> UInt16 {
        let singleQuots: [UInt16] = [0x2018, 0x2019]
        let doubleQuots: [UInt16] = [0x201c, 0x201d]

        if char == 0x27 {
            singleQuot ^= 1
            return singleQuots[singleQuot]
        } else if char == 0x22 {
            doubleQuot ^= 1
            return doubleQuots[doubleQuot]
        }
        return char
    }

    // MARK: - Private: Buffer commit

    private func commitBuffer(client: (any IMKTextInput)?, chars: [UInt16], processedKeyCount: Int) {
        if processedKeyCount > 0 {
            keyBuffer.removeFirst(min(processedKeyCount, keyBuffer.count))
        }
        guard !chars.isEmpty, let client = client else { return }
        let str = String(utf16CodeUnits: chars, count: chars.count)
        HNLog("HNInputContext HNCommitBuffer ## insertText: \(str)")
        client.insertText(str, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    // MARK: - Private: Main composition loop

    private func compose(client: (any IMKTextInput)?) {
        var char = HNCharacter()
        var charBuffer = [UInt16]()
        charBuffer.reserveCapacity(hnBufferSize)

        var i = 0
        while i < keyBuffer.count {
            let code = keyBuffer[i]
            var sType  = hnKeyType(code)
            var sValue = hnKeyValue(code)

            // 두벌식 (Jamo) special handling
            if keyboardLayout?.type == .jamo {

                if sType == HNKeyType.initial.rawValue, Int(char.type) > sType {
                    // Try to use this initial consonant as a final consonant.
                    let sFinalCandidate = hnJasoInitialToFinal[Int(sValue)]

                    if sFinalCandidate != 0 {
                        let existingFinal = char.final_
                        let newFinal: UInt8

                        if existingFinal == HNCharacter.nilValue {
                            newFinal = sFinalCandidate
                        } else if existingFinal != sFinalCandidate {
                            let composed = jasoCompose(
                                type: HNKeyType.final_.rawValue,
                                v1: existingFinal,
                                v2: sFinalCandidate
                            )
                            newFinal = composed
                        } else {
                            newFinal = HNCharacter.nilValue
                        }

                        if newFinal != HNCharacter.nilValue {
                            var tmpChar = char
                            tmpChar.set(type: HNKeyType.final_.rawValue, value: newFinal)
                            if !composeCharacter(tmpChar).isEmpty {
                                sType  = HNKeyType.final_.rawValue
                                sValue = hnJasoInitialToFinal[Int(sValue)]
                            }
                        }
                    }

                } else if sType == HNKeyType.medial.rawValue,
                          char.type == UInt8(HNKeyType.final_.rawValue) {
                    // Medial after a syllable with a final consonant:
                    // Split — take the final consonant as the initial of the new syllable.

                    let sInitial = hnKeyValue(keyBuffer[i - 1])

                    let sFinal: UInt8
                    if i > 1, hnKeyType(keyBuffer[i - 2]) == HNKeyType.initial.rawValue {
                        if i > 2, hnKeyType(keyBuffer[i - 3]) == HNKeyType.initial.rawValue {
                            // Double final (옛한글)
                            sFinal = jasoCompose(
                                type: HNKeyType.final_.rawValue,
                                v1: hnJasoInitialToFinal[Int(hnKeyValue(keyBuffer[i - 3]))],
                                v2: hnJasoInitialToFinal[Int(hnKeyValue(keyBuffer[i - 2]))]
                            )
                        } else {
                            sFinal = hnJasoInitialToFinal[Int(hnKeyValue(keyBuffer[i - 2]))]
                        }
                    } else {
                        sFinal = HNCharacter.nilValue
                    }

                    char.final_ = sFinal
                    let composed = composeCharacter(char)

                    if let ud = userDefaults, ud.commitsImmediately {
                        commitBuffer(client: client, chars: composed, processedKeyCount: i - 1)
                        i = 1
                    } else {
                        charBuffer.append(contentsOf: composed)
                    }

                    char.clear()
                    char.set(type: HNKeyType.initial.rawValue, value: sInitial)
                    // Fall through to general processing with sType=medial, sValue=medial value
                }
            }

            // General jaso accumulation
            if Int(char.type) <= sType {
                let existing = char[sType]
                let newValue: UInt8

                if existing != HNCharacter.nilValue {
                    newValue = jasoCompose(type: sType, v1: existing, v2: sValue)
                } else {
                    newValue = sValue
                }

                if newValue != HNCharacter.nilValue {
                    var tmpChar = char
                    tmpChar.set(type: sType, value: newValue)
                    if !composeCharacter(tmpChar).isEmpty {
                        char = tmpChar
                        i += 1
                        continue
                    }
                }
            }

            // Can't extend current char — commit it and start a new one.
            let composed = composeCharacter(char)
            char.clear()
            char.set(type: sType, value: sValue)

            if !composed.isEmpty {
                if let ud = userDefaults, ud.commitsImmediately {
                    commitBuffer(client: client, chars: composed, processedKeyCount: i)
                    i = 0
                } else {
                    charBuffer.append(contentsOf: composed)
                }
            }

            i += 1
        }

        charBuffer.append(contentsOf: composeCharacter(char))
        composedString = charBuffer.isEmpty ? nil
            : String(utf16CodeUnits: charBuffer, count: charBuffer.count)
    }
}
