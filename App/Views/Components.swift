import AppKit
import CableKit
import SwiftUI

/// Pure Black Lime, from the app icon: black, lime #C5FA09, ink #111014.
enum Palette {
    static let lime = Color(red: 0xC5 / 255, green: 0xFA / 255, blue: 0x09 / 255)
    static let ink = Color(red: 0x11 / 255, green: 0x10 / 255, blue: 0x14 / 255)
    static let background = Color.black
    static let limeSaved = Color(red: 0xE9 / 255, green: 1, blue: 0xB0 / 255)
    static let power = lime
    static let thunderbolt = lime
    static let groupFill = Color.white.opacity(0.04)
    static let groupStroke = Color.white.opacity(0.08)
    static let amber = Color(nsColor: .systemOrange)

    static func tie(_ t: TieColor) -> Color {
        switch t {
        case .red: Color(nsColor: .systemRed)
        case .orange: Color(nsColor: .systemOrange)
        case .yellow: Color(nsColor: .systemYellow)
        case .green: Color(nsColor: .systemGreen)
        case .blue: Color(nsColor: .systemBlue)
        case .purple: Color(nsColor: .systemPurple)
        case .pink: Color(red: 1.0, green: 0.50, blue: 0.80)
        case .gray: Color(nsColor: .systemGray)
        }
    }
}

/// The Thunderbolt mark: a lightning bolt whose lower stroke ends in an arrowhead.
struct ThunderboltGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * w, y: r.minY + y * h) }
        var path = Path()
        path.move(to: p(0.62, 0.0))
        path.addLine(to: p(0.18, 0.56))
        path.addLine(to: p(0.48, 0.56))
        path.addLine(to: p(0.36, 1.0))
        path.addLine(to: p(0.70, 0.52))
        path.addLine(to: p(0.86, 0.52))
        path.addLine(to: p(0.86, 0.66))
        path.addLine(to: p(1.0, 0.44))
        path.addLine(to: p(0.86, 0.22))
        path.addLine(to: p(0.86, 0.36))
        path.addLine(to: p(0.60, 0.36))
        path.closeSubpath()
        return path
    }
}

/// Bitmap versions of the glyphs, for places that only draw images (menus, menu labels).
@MainActor enum GlyphImages {
    private static var cache: [String: NSImage] = [:]

    static func thunderbolt(height: CGFloat) -> Image {
        image(key: "tb-\(height)", size: CGSize(width: height * 0.8, height: height)) {
            ThunderboltGlyph().fill(Palette.thunderbolt)
        }
    }

    static func dot(_ color: Color, key: String, size: CGFloat = 11) -> Image {
        image(key: "dot-\(key)-\(size)", size: CGSize(width: size, height: size)) { Circle().fill(color) }
    }

    private static func image<V: View>(key: String, size: CGSize, @ViewBuilder _ v: () -> V) -> Image {
        if let img = cache[key] { return Image(nsImage: img) }
        let r = ImageRenderer(content: v().frame(width: size.width, height: size.height))
        r.scale = 2
        let img = r.nsImage ?? NSImage(size: size)
        img.isTemplate = false
        cache[key] = img
        return Image(nsImage: img)
    }
}

/// "USB 4" with the Thunderbolt mark in front when the link is Thunderbolt-capable.
struct DataName: View {
    var generation: DataGeneration?
    var thunderbolt: Bool
    var glyphSize: CGFloat = 13

    var body: some View {
        HStack(spacing: glyphSize * 0.35) {
            if thunderbolt {
                GlyphImages.thunderbolt(height: glyphSize)
                    .accessibilityLabel("Thunderbolt")
            }
            Text(generation?.name ?? "—")
        }
    }
}

struct Chip: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Palette.groupFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.groupStroke))
    }
}

/// A grouped key-value table, as in the inspector.
struct InfoGroup: View {
    var title: String
    var rows: [(String, String)]
    var emptyText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 15, weight: .semibold))
            VStack(spacing: 0) {
                if rows.isEmpty, let emptyText {
                    Text(emptyText).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 9)
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.0).foregroundStyle(.secondary).frame(width: 118, alignment: .leading)
                        Text(row.1).monospacedDigit().textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6.5).padding(.horizontal, 12)
                    if i < rows.count - 1 { Divider().padding(.leading, 12) }
                }
            }
            .font(.system(size: 13))
            .background(Palette.groupFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.groupStroke))
        }
    }
}

struct TieSwatches: View {
    @Binding var selection: TieColor?
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: size * 0.45) {
            ForEach(TieColor.allCases, id: \.self) { t in
                Button { selection = (selection == t ? nil : t) } label: {
                    Circle().fill(Palette.tie(t)).frame(width: size, height: size)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(selection == t ? 0.9 : 0), lineWidth: 2).padding(-4))
                }
                .buttonStyle(.plain)
                .help(t.name)
                .accessibilityLabel(t.name)
                .accessibilityAddTraits(selection == t ? .isSelected : [])
            }
        }
    }
}

enum LabelActions {
    static func copy(_ label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(label, forType: .string)
    }

    /// Prints the label in large type through the system print dialog.
    @MainActor static func print(_ label: String) {
        let view = NSHostingView(rootView:
            Text(label).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.black).padding(12).background(.white))
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 64)
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.topMargin = 12; info.leftMargin = 12
        NSPrintOperation(view: view, printInfo: info).run()
    }
}

// MARK: Pure Black Lime building blocks

/// The lime primary button with ink text (Save).
struct LimeButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var large = true
    var fill = Palette.lime

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 15 : 13, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, large ? 18 : 14).frame(height: large ? 36 : 28)
            .background(fill.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35),
                        in: RoundedRectangle(cornerRadius: large ? 10 : 7, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// One step of a cascade: fades and rises into place after `index` steps of 45 ms.
struct CascadeItem: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var index: Int
    var shown: Bool
    var base: Double

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .animation(.spring(response: 0.5, dampingFraction: 0.9).delay(shown ? base + Double(index) * 0.045 : 0), value: shown)
    }
}

extension View {
    func cascade(_ index: Int, shown: Bool, base: Double = 0.12) -> some View {
        modifier(CascadeItem(index: index, shown: shown, base: base))
    }
}

/// Turns `shown` on right after the view appears, so its cascade plays.
struct CascadeOnAppear<Content: View>: View {
    @State private var shown = false
    @ViewBuilder var content: (Bool) -> Content
    var body: some View {
        content(shown).onAppear { shown = true }
    }
}

/// The checkmark from the mockup: a lime disc that springs in, then the tick draws itself.
struct DrawnCheck: View {
    var done: Bool
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle().fill(Palette.lime)
                .scaleEffect(done ? 1 : 0.3)
                .opacity(done ? 1 : 0)
                .animation(done ? .spring(response: 0.42, dampingFraction: 0.5) : .easeOut(duration: 0.12), value: done)
            TickShape()
                .trim(from: 0, to: done ? 1 : 0)
                .stroke(Palette.ink, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round, lineJoin: .round))
                .animation(done ? .easeOut(duration: 0.32).delay(0.14) : .linear(duration: 0), value: done)
        }
        .frame(width: size, height: size)
    }
}

struct TickShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.29, y: r.minY + r.height * 0.52))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.43, y: r.minY + r.height * 0.66))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.71, y: r.minY + r.height * 0.375))
        return p
    }
}

/// A plain lightning bolt, as on the app icon's connector.
struct BoltShape: Shape {
    func path(in r: CGRect) -> Path {
        // From the mockup's bolt, box 31 x 48.
        let pts: [(CGFloat, CGFloat)] = [(22, 0), (0, 28), (13, 28), (8, 48), (31, 18), (18, 18)]
        var p = Path()
        for (i, pt) in pts.enumerated() {
            let c = CGPoint(x: r.minX + pt.0 / 31 * r.width, y: r.minY + pt.1 / 48 * r.height)
            if i == 0 { p.move(to: c) } else { p.addLine(to: c) }
        }
        p.closeSubpath()
        return p
    }
}

/// Counts up from 0 to `value` with ease-out when it appears (or when `value` changes).
struct CountUpText: View {
    var value: Int
    var delay: Double = 0
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("\(shown)")
            .monospacedDigit()
            .task(id: value) {
                if reduceMotion { shown = value; return }
                shown = 0
                try? await Task.sleep(for: .seconds(delay))
                let start = Date()
                while !Task.isCancelled {
                    let p = min(1, Date().timeIntervalSince(start) / 1.1)
                    shown = Int((Double(value) * (1 - pow(1 - p, 3))).rounded())
                    if p >= 1 { break }
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
            .accessibilityLabel("\(value)")
    }
}
