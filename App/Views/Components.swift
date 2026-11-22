import AppKit
import CableKit
import SwiftUI

enum Palette {
    static let power = Color(nsColor: .systemGreen)
    static let thunderbolt = Color(nsColor: .systemBlue)
    static let groupFill = Color.primary.opacity(0.045)
    static let groupStroke = Color.primary.opacity(0.09)
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
                .foregroundStyle(thunderbolt ? Palette.thunderbolt : .primary)
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
