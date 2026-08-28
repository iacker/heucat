import SwiftUI

/// Neoclassical design system: marble paper, ink serif display type, a single
/// lapis accent. Colours are defined once here so the views never hardcode them.
enum Theme {
    static let paper = Color(red: 0.976, green: 0.973, blue: 0.965)
    static let paperDeep = Color(red: 0.957, green: 0.953, blue: 0.945)
    static let card = Color.white
    static let ink = Color(red: 0.106, green: 0.114, blue: 0.141)
    static let inkSoft = Color(red: 0.404, green: 0.420, blue: 0.463)
    static let inkFaint = Color(red: 0.612, green: 0.627, blue: 0.667)
    static let lapis = Color(red: 0.318, green: 0.302, blue: 0.702)
    static let lapisSoft = Color(red: 0.514, green: 0.494, blue: 0.847)
    static let verdigris = Color(red: 0.122, green: 0.545, blue: 0.408)
    static let amber = Color(red: 0.706, green: 0.478, blue: 0.114)
    static let hairline = Color(red: 0.878, green: 0.871, blue: 0.855)

    /// Marble ground tokens. The mockup's page is not white: it is a cool violet
    /// stone that makes the cream cards read as lifted plates.
    static let marbleDeep = Color(red: 0.882, green: 0.878, blue: 0.925)
    static let marbleShadow = Color(red: 0.239, green: 0.220, blue: 0.400)
    /// Cards and the sidebar are warm cream, not pure white, against that ground.
    static let cream = Color(red: 0.992, green: 0.988, blue: 0.980)

    /// Didot carries the plate-engraved look; Baskerville is the fallback and
    /// ships on every macOS install, so this never falls back to the system sans.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Didot", size: size).weight(weight)
    }

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Baskerville", size: size).weight(weight)
    }

    /// Letterspaced small caps used for eyebrow labels and plate captions.
    static func caption(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
}

// MARK: - Ornaments

/// A hairline rule interrupted by a small lozenge, the printer's mark used
/// throughout the layout to separate blocks without a heavy divider.
struct Ornament: View {
    var width: CGFloat = 150
    var tint: Color = Theme.inkFaint

    var body: some View {
        HStack(spacing: 7) {
            rule
            Image(systemName: "diamond")
                .font(.system(size: 6, weight: .light))
                .foregroundStyle(tint)
            rule
        }
        .frame(width: width)
    }

    private var rule: some View {
        Rectangle()
            .fill(LinearGradient(colors: [tint.opacity(0), tint.opacity(0.55)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(height: 0.5)
    }
}

/// Eyebrow label: letterspaced uppercase, the typographic tell of the style.
struct Eyebrow: View {
    let text: String
    var tint: Color = Theme.inkFaint

    var body: some View {
        Text(text.uppercased())
            .font(Theme.caption())
            .tracking(1.6)
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
    }
}

/// The engraved laurel crest. Drawn with shapes rather than shipped as an asset
/// so it stays crisp at any size and adds no binary to the repo.
struct Crest: View {
    var size: CGFloat = 74
    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.lapis.opacity(0.16), lineWidth: 0.6)
                .frame(width: size, height: size)
            Circle()
                .stroke(Theme.lapis.opacity(0.10), lineWidth: 0.6)
                .frame(width: size * 0.82, height: size * 0.82)
            ForEach(0..<24, id: \.self) { i in
                Rectangle()
                    .fill(Theme.lapis.opacity(0.14))
                    .frame(width: 0.6, height: size * 0.055)
                    .offset(y: -size * 0.46)
                    .rotationEffect(.degrees(Double(i) * 15))
            }
            Text("H")
                .font(Theme.display(size * 0.42, weight: .medium))
                .foregroundStyle(Theme.lapis)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Surfaces

/// The standard plate: white card, hairline rule, and a shadow low enough to
/// read as paper lifted off paper rather than a floating panel.
struct Plate<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Theme.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 0.8)
            )
            // Two shadows: a tight contact shadow plus a wide soft one. A single
            // shadow reads as a sticker; the pair is what makes it look like
            // paper resting on stone.
            .shadow(color: Theme.marbleShadow.opacity(0.10), radius: 2, y: 1)
            .shadow(color: Theme.marbleShadow.opacity(0.13), radius: 18, y: 8)
    }
}

/// A compact stat tile: icon, big number, label, and an optional delta line.
/// Used for the row of counters across the top of the overview.
struct StatTile: View {
    let icon: String
    let value: String
    let label: String
    var caption: String? = nil
    var tint: Color = Theme.lapis

    var body: some View {
        Plate(padding: 15) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(tint)
                    Eyebrow(text: label)
                    Spacer(minLength: 0)
                }
                Text(value)
                    .font(Theme.display(30, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let caption {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkFaint)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A titled plate with the eyebrow header and optional trailing accessory.
struct TitledPlate<Content: View, Accessory: View>: View {
    let title: String
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory

    var body: some View {
        Plate(padding: padding) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(Theme.serif(16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    accessory
                }
                content
            }
        }
    }
}

extension TitledPlate where Accessory == EmptyView {
    init(_ title: String, padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.init(title: title, padding: padding, content: content, accessory: { EmptyView() })
    }
}

/// The marble field behind everything. The mockup's depth comes from a violet
/// ground with light pooling in the centre, not from a flat paper fill: cards
/// only read as lifted when the field behind them is darker at the edges.
struct MarbleBackground: View {
    var body: some View {
        ZStack {
            Theme.marbleDeep
            // Light pools behind the content column so the centre lifts.
            RadialGradient(colors: [Color.white.opacity(0.55), .clear],
                           center: .init(x: 0.5, y: 0.32), startRadius: 0, endRadius: 760)
            // Violet wash top-left and bottom-right, the mockup's cool corners.
            RadialGradient(colors: [Theme.lapis.opacity(0.20), .clear],
                           center: .init(x: 0.06, y: 0.04), startRadius: 0, endRadius: 660)
            RadialGradient(colors: [Theme.lapis.opacity(0.16), .clear],
                           center: .init(x: 0.96, y: 0.98), startRadius: 0, endRadius: 620)
            // Vignette: keeps the outer frame dark so the app feels inset.
            RadialGradient(colors: [.clear, Theme.marbleShadow.opacity(0.34)],
                           center: .center, startRadius: 380, endRadius: 1080)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Controls

struct LapisButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.lapis.opacity(configuration.isPressed ? 0.82 : 1))
            )
            .shadow(color: Theme.lapis.opacity(0.28), radius: 8, y: 3)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isPressed ? Theme.paperDeep : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 0.8)
            )
    }
}

/// Circular gauge used for vault health. `value` is 0...1.
struct HealthRing: View {
    let value: Double
    let label: String
    var size: CGFloat = 128

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.hairline, lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(
                    AngularGradient(colors: [Theme.lapis, Theme.lapisSoft, Theme.lapis],
                                    center: .center),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(Theme.display(size * 0.23, weight: .medium))
                .foregroundStyle(Theme.lapis)
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.45), value: value)
    }
}
