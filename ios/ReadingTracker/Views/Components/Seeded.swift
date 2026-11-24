import CoreGraphics

/// A tiny repeatable random generator, so drawn textures look the same every time.
struct Seeded {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493 }
    mutating func next() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat(Double(state >> 11) / Double(1 << 53))
    }
}
