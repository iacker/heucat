import SwiftUI

/// Modern design system: near-black canvas, translucent glass surfaces, one
/// electric indigo accent with a violet-to-cyan gradient for emphasis.
///
/// Every token and component name here is unchanged from the previous
/// neoclassical theme on purpose: the views address colours and surfaces only
/// through these names, so the whole app restyles from this one file. Names
/// like `paper`, `serif()` and `marbleShadow` are now historical labels for
/// their modern role, kept so no view has to be touched to change the look.
enum Theme {
    // MARK: Canvas

    /// The app ground. Near-black with a blue cast so accents read as light.
    static let paper = Color(red: 0.043, green: 0.047, blue: 0.063)
    static let paperDeep = Color(red: 0.027, green: 0.031, blue: 0.043)
    /// Surface fill for cards. Very slightly lifted off the canvas; the real
    /// separation comes from the stroke and the glow, not from brightness.
    static let card = Color(red: 0.086, green: 0.094, blue: 0.122)
    static let cream = Color(red: 0.098, green: 0.106, blue: 0.137)

    // MARK: Text

    static let ink = Color(red: 0.949, green: 0.957, blue: 0.976)
    static let inkSoft = Color(red: 0.639, green: 0.667, blue: 0.729)
    static let inkFaint = Color(red: 0.404, green: 0.435, blue: 0.514)

    // MARK: Accents

    /// Electric indigo. The single accent; everything else is a state colour.
    static let lapis = Color(red: 0.443, green: 0.404, blue: 0.996)
    static let lapisSoft = Color(red: 0.624, green: 0.573, blue: 1.0)
    /// Cyan tail of the accent gradient, used for motion and rings.
    static let cyanEdge = Color(red: 0.353, green: 0.827, blue: 0.949)
    /// State colours, tuned for contrast on the dark canvas rather than paper.
    static let verdigris = Color(red: 0.204, green: 0.827, blue: 0.600)
    static let amber = Color(red: 0.984, green: 0.749, blue: 0.286)
    static let rose = Color(red: 0.984, green: 0.443, blue: 0.522)

    /// Hairlines are light at low opacity, not a dark rule: on a dark canvas a
    /// darker line disappears while a lighter one reads as a lit edge.
    static let hairline = Color.white.opacity(0.09)
    static let hairlineBright = Color.white.opacity(0.16)

    /// Ground tokens. `marbleShadow` is now the colour that everything glows
    /// and drops shadow in, which on a dark UI is black, not violet.
    static let marbleDeep = Color(red: 0.035, green: 0.039, blue: 0.055)
    static let marbleShadow = Color.black

    /// The accent gradient. One definition so buttons, rings and the crest all
    /// share the same light source.
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [lapis, lapisSoft, cyanEdge],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The top-edge highlight every glass surface carries. A card without it
    /// looks flat; with it, it looks like a pane catching light from above.
    static var glassEdge: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.04),
                                Color.white.opacity(0.09)],
                       startPoint: .top, endPoint: .bottom)
    }

    // MARK: Type

    /// Modern UI type is the system face: SF Pro is variable-optical-sized and
    /// tuned for exactly these sizes, so a custom serif would only cost
    /// legibility here. `display` is the tight, heavy headline cut.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Body and label text. Rounded softens the dense technical content.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Monospaced digits and paths. Values must not reflow as they update.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Letterspaced small caps for eyebrow labels and plate captions.
    static func caption(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

// MARK: - Ornaments

/// A hairline rule that fades out from a bright centre. On a dark canvas the
/// old lozenge-and-rule printer's mark reads as debris, so the same separating
/// job is done by a gradient that simply dissolves at both ends.
struct Ornament: View {
    var width: CGFloat = 150
    var tint: Color = Theme.lapis

    var body: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [tint.opacity(0), tint.opacity(0.65), tint.opacity(0)],
                startPoint: .leading, endPoint: .trailing))
            .frame(width: width, height: 1)
    }
}

/// Eyebrow label: letterspaced uppercase in the accent, the tell that a block
/// is a titled section rather than body copy.
struct Eyebrow: View {
    let text: String
    var tint: Color = Theme.inkFaint

    var body: some View {
        Text(text.uppercased())
            .font(Theme.caption(9))
            .tracking(1.5)
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
    }
}

/// The app mark: a gradient-filled rounded shield carrying the H, sitting on
/// its own coloured glow. Drawn rather than shipped as an asset so it stays
/// crisp at any size and adds nothing to the binary.
struct Crest: View {
    var size: CGFloat = 74
    @State private var sweep = false

    var body: some View {
        ZStack {
            // The glow is what sells it as emissive rather than printed.
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(Theme.lapis)
                .frame(width: size * 0.82, height: size * 0.82)
                .blur(radius: size * 0.26)
                .opacity(0.55)

            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Theme.accentGradient)
                .frame(width: size * 0.78, height: size * 0.78)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                )

            Text("H")
                .font(.system(size: size * 0.40, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)

            // A slow orbiting ring: the one piece of ambient motion in the app.
            Circle()
                .trim(from: 0, to: 0.18)
                .stroke(Theme.cyanEdge.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .frame(width: size * 0.98, height: size * 0.98)
                .rotationEffect(.degrees(sweep ? 360 : 0))
                .animation(.linear(duration: 7).repeatForever(autoreverses: false),
                           value: sweep)
        }
        .frame(width: size, height: size)
        .onAppear { sweep = true }
    }
}

// MARK: - Surfaces

/// The standard surface: a translucent glass pane with a lit top edge and a
/// deep soft shadow. Materials, not opaque fills, so the coloured field behind
/// shows through and each card picks up the light around it.
struct Plate<Content: View>: View {
    var padding: CGFloat = 22
    var radius: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Theme.card.opacity(0.55))
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.glassEdge, lineWidth: 1)
            )
            // Contact shadow plus a wide ambient one. A single shadow reads as
            // a sticker; the pair gives the pane real depth over the field.
            .shadow(color: Theme.marbleShadow.opacity(0.40), radius: 2, y: 1)
            .shadow(color: Theme.marbleShadow.opacity(0.45), radius: 24, y: 12)
    }
}

/// A compact stat tile: eyebrow, big number, optional caption, and an accent
/// wash keyed to its tint so a row of them reads as a dashboard.
struct StatTile: View {
    let icon: String
    let value: String
    let label: String
    var caption: String? = nil
    var tint: Color = Theme.lapis
    @State private var appeared = false

    var body: some View {
        Plate(padding: 16, radius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 26, height: 26)
                        .background(tint.opacity(0.14), in: RoundedRectangle(
                            cornerRadius: 8, style: .continuous))
                    Eyebrow(text: label)
                    Spacer(minLength: 0)
                }
                Text(value)
                    .font(Theme.display(32, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let caption {
                    Text(caption)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Theme.inkFaint)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A faint tint wash at the top so each tile carries its own state
        // colour without a coloured border shouting at the user.
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(RadialGradient(colors: [tint.opacity(0.20), .clear],
                                     center: .topLeading,
                                     startRadius: 0, endRadius: 170))
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { appeared = true }
        }
    }
}

/// A titled plate with a section header and optional trailing accessory.
struct TitledPlate<Content: View, Accessory: View>: View {
    let title: String
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory

    var body: some View {
        Plate(padding: padding) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(Theme.serif(15, weight: .semibold))
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

/// The field behind everything: a dark canvas with slow coloured aurora pools
/// and a vignette. The glass panes have nothing to refract without it, so this
/// view is what makes the whole theme read as depth rather than flat dark grey.
struct MarbleBackground: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            Theme.paperDeep

            // Indigo pool, top-left, slowly breathing.
            RadialGradient(colors: [Theme.lapis.opacity(0.38), .clear],
                           center: .init(x: 0.08, y: 0.02), startRadius: 0, endRadius: 780)
                .scaleEffect(drift ? 1.12 : 0.94)
                .animation(.easeInOut(duration: 16).repeatForever(autoreverses: true),
                           value: drift)

            // Cyan pool, bottom-right, counter-phase so the field never rests.
            RadialGradient(colors: [Theme.cyanEdge.opacity(0.20), .clear],
                           center: .init(x: 0.98, y: 0.96), startRadius: 0, endRadius: 700)
                .scaleEffect(drift ? 0.92 : 1.14)
                .animation(.easeInOut(duration: 19).repeatForever(autoreverses: true),
                           value: drift)

            // A violet band behind the content column lifts the centre.
            RadialGradient(colors: [Color(red: 0.36, green: 0.20, blue: 0.62).opacity(0.30), .clear],
                           center: .init(x: 0.52, y: 0.42), startRadius: 0, endRadius: 640)

            // Vignette: keeps the outer frame dark so the app feels inset.
            RadialGradient(colors: [.clear, Color.black.opacity(0.55)],
                           center: .center, startRadius: 340, endRadius: 1100)
        }
        .ignoresSafeArea()
        .onAppear { drift = true }
    }
}

// MARK: - Controls

/// The primary action: gradient fill, coloured glow, and a press that scales
/// rather than just dimming.
struct LapisButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.accentGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
            )
            .shadow(color: Theme.lapis.opacity(configuration.isPressed ? 0.25 : 0.45),
                    radius: configuration.isPressed ? 6 : 14, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

/// The secondary action: glass chip that brightens its edge on press. Used for
/// every per-row action, so it stays quiet enough to repeat many times a page.
struct QuietButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium, design: .rounded))
            .foregroundStyle(hovering ? Theme.ink : Theme.inkSoft)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.14
                                              : (hovering ? 0.09 : 0.05)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(hovering ? Theme.hairlineBright : Theme.hairline,
                                  lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75),
                       value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Circular gauge used for vault health. `value` is 0...1. The track is a dim
/// ring and the progress arc carries the accent gradient plus its own glow.
struct HealthRing: View {
    let value: Double
    let label: String
    var size: CGFloat = 128
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 9)

            Circle()
                .trim(from: 0, to: max(0.001, min(1, shown)))
                .stroke(
                    AngularGradient(colors: [Theme.lapis, Theme.lapisSoft,
                                             Theme.cyanEdge, Theme.lapis],
                                    center: .center),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.lapis.opacity(0.55), radius: 9)

            VStack(spacing: 1) {
                Text(label)
                    .font(Theme.display(size * 0.26, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
        }
        .frame(width: size, height: size)
        // Animate from zero on appear so the ring draws itself in, then track
        // later changes with the same spring.
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) { shown = value }
        }
        .onChange(of: value) { _, new in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { shown = new }
        }
    }
}

/// A small state pill: dot plus label in the state's own colour. The dark
/// canvas makes coloured text on a tinted chip far more readable than the
/// bare coloured text the light theme used.
struct StatusPill: View {
    let text: String
    var tint: Color = Theme.verdigris
    var pulses: Bool = false
    @State private var glow = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .shadow(color: tint.opacity(0.9), radius: glow ? 5 : 2)
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.8))
        .onAppear {
            guard pulses else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}
