import SwiftUI

/// A bare line through `values`, scaled to fill the rect. Used in tables and the widget.
struct SparklineShape: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return Path() }
        let span = hi - lo == 0 ? 1 : hi - lo
        let step = rect.width / CGFloat(values.count - 1)
        return Path { p in
            for (i, v) in values.enumerated() {
                let point = CGPoint(x: CGFloat(i) * step, y: rect.maxY - CGFloat((v - lo) / span) * rect.height)
                i == 0 ? p.move(to: point) : p.addLine(to: point)
            }
        }
    }
}
