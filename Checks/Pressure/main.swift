import Foundation
import WacomdShared

var cases = 0
let exponents: [Double] = [0.25, 0.5, 1, 2, 3]
for exponent in exponents {
    var config = WacomdConfig()
    config.penPressureExponent = exponent
    try config.validate()
    precondition(config.pressure(-1) == 0 && config.pressure(2) == 1)
    precondition(config.pressure(0) == 0 && config.pressure(1) == 1)
    var previous = -Double.infinity
    for step in 0...2047 {
        let input = Double(step) / 2047
        let output = config.pressure(input)
        precondition(output.isFinite && output >= 0 && output <= 1)
        precondition(output >= previous)
        if exponent == 1 { precondition(output == input) }
        if input > 0 && input < 1 {
            if exponent < 1 { precondition(output > input) }
            if exponent > 1 { precondition(output < input) }
        }
        previous = output
        cases += 1
    }
    let decoded = try JSONDecoder().decode(WacomdConfig.self, from: JSONEncoder().encode(config))
    precondition(decoded.penPressureExponent == exponent)
}
for exponent in [-1.0, 0, 0.249, 3.001, Double.infinity, Double.nan] {
    var config = WacomdConfig()
    config.penPressureExponent = exponent
    do { try config.validate(); fatalError("Accepted invalid pressure exponent") } catch {}
}
let bundledURL = URL(fileURLWithPath: CommandLine.arguments[1])
let bundled = try JSONDecoder().decode(WacomdConfig.self, from: Data(contentsOf: bundledURL))
precondition(bundled.penPressureExponent == 1)
print("Pressure matrix PASS: \(cases) samples, soft/linear/firm curves, monotonic bounds, clamping, persistence, invalid settings, bundled settings import")
