import Foundation

var seed: UInt64 = 0x451114
func byte() -> UInt8 {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return UInt8(truncatingIfNeeded: seed >> 32)
}
var parser = IntuosProTouchParser()
var cases = 0
for length in 0...127 {
    for trial in 0..<500 {
        var bytes = (0..<max(length, 1)).map { _ in byte() }
        if length > 0 && trial % 2 == 0 { bytes[0] = 2 }
        bytes.withUnsafeMutableBufferPointer { buffer in
            if let contacts = parser.decode(data: buffer.baseAddress!, length: length) {
                precondition(contacts.count <= 16)
                precondition(Set(contacts.map { $0.slotID }).count == contacts.count)
                precondition(contacts.allSatisfy { (2...17).contains($0.slotID) && (0...4095).contains($0.x) && (0...4095).contains($0.y) && $0.inContact })
            }
            for reportID: UInt32 in [2, 3, 192] {
                let result = IntuosProParser.decode(reportID: reportID, data: buffer.baseAddress!, length: length)
                if case .pen(let pen) = result {
                    precondition((0...2047).contains(pen.pressure))
                    precondition((-64...63).contains(pen.tiltX) && (-64...63).contains(pen.tiltY))
                    precondition((0...63).contains(pen.distance))
                }
            }
        }
        cases += 1
    }
}
print("Parser robustness PASS: \(cases) deterministic buffers, lengths 0...127, three pen report IDs and stateful touch decoding; no desktop input posted")
