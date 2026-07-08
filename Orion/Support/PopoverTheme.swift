import AppKit

struct PopoverTheme {
    let name: String
    // Popover
    let popoverBg: NSColor
    let popoverBorder: NSColor
    let popoverBorderWidth: CGFloat
    let popoverCornerRadius: CGFloat
    let titleBarBg: NSColor
    let titleText: NSColor
    let titleFont: NSFont
    let titleString: String
    let separatorColor: NSColor
    // Terminal
    let font: NSFont
    let fontBold: NSFont
    let textPrimary: NSColor
    let textDim: NSColor
    let accentColor: NSColor
    let errorColor: NSColor
    let successColor: NSColor
    // Amber #F59E0B — MEANING = active / in-progress. Defaulted so the
    // legacy presets don't need to be rewritten; the Orbit themes set it
    // explicitly. Signals carry meaning, never decoration.
    var activeColor: NSColor = NSColor(red: 0.961, green: 0.620, blue: 0.043, alpha: 1.0)
    let inputBg: NSColor
    let inputCornerRadius: CGFloat
    // Bubble
    let bubbleBg: NSColor
    let bubbleBorder: NSColor
    let bubbleText: NSColor
    let bubbleCompletionBorder: NSColor
    let bubbleCompletionText: NSColor
    let bubbleFont: NSFont
    let bubbleCornerRadius: CGFloat

    // MARK: - Presets

    static let teenageEngineering = PopoverTheme(
        name: "Midnight",
        popoverBg: NSColor(red: 0.050, green: 0.050, blue: 0.058, alpha: 0.97),
        popoverBorder: NSColor(red: 1.0, green: 0.42, blue: 0.0, alpha: 0.62),
        popoverBorderWidth: 1.0,
        popoverCornerRadius: 14,
        titleBarBg: NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0),
        titleText: NSColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 1.0),
        titleFont: NSFont(name: "SFMono-Bold", size: 10) ?? .monospacedSystemFont(ofSize: 10, weight: .bold),
        titleString: "Orbit",
        separatorColor: NSColor(red: 1.0, green: 0.42, blue: 0.0, alpha: 0.22),
        font: NSFont(name: "SFMono-Regular", size: 11.5) ?? .monospacedSystemFont(ofSize: 11.5, weight: .regular),
        fontBold: NSFont(name: "SFMono-Medium", size: 11.5) ?? .monospacedSystemFont(ofSize: 11.5, weight: .medium),
        textPrimary: NSColor(red: 0.92, green: 0.92, blue: 0.93, alpha: 1.0),
        textDim: NSColor(white: 0.52, alpha: 1.0),
        accentColor: NSColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 1.0),
        errorColor: NSColor(red: 1.0, green: 0.32, blue: 0.22, alpha: 1.0),
        successColor: NSColor(red: 0.38, green: 0.68, blue: 0.38, alpha: 1.0),
        inputBg: NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1.0),
        inputCornerRadius: 8,
        bubbleBg: NSColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 0.96),
        bubbleBorder: NSColor(red: 1.0, green: 0.42, blue: 0.0, alpha: 0.52),
        bubbleText: NSColor(white: 0.62, alpha: 1.0),
        bubbleCompletionBorder: NSColor(red: 0.28, green: 0.82, blue: 0.28, alpha: 0.62),
        bubbleCompletionText: NSColor(red: 0.28, green: 0.85, blue: 0.28, alpha: 1.0),
        bubbleFont: .monospacedSystemFont(ofSize: 10, weight: .medium),
        bubbleCornerRadius: 10
    )

    static let playful = PopoverTheme(
        name: "Peach",
        popoverBg: NSColor(red: 0.988, green: 0.960, blue: 0.912, alpha: 0.96),
        popoverBorder: NSColor(red: 0.848, green: 0.618, blue: 0.308, alpha: 0.55),
        popoverBorderWidth: 1.0,
        popoverCornerRadius: 32,
        titleBarBg: NSColor(red: 0.972, green: 0.900, blue: 0.772, alpha: 0.84),
        titleText: NSColor(red: 0.365, green: 0.212, blue: 0.075, alpha: 1.0),
        titleFont: NSFont.systemFont(ofSize: 11, weight: .semibold),
        titleString: "Orbit",
        separatorColor: NSColor(red: 0.838, green: 0.718, blue: 0.528, alpha: 0.30),
        font: NSFont.systemFont(ofSize: 13, weight: .regular),
        fontBold: NSFont.systemFont(ofSize: 13, weight: .semibold),
        textPrimary: NSColor(red: 0.182, green: 0.138, blue: 0.098, alpha: 1.0),
        textDim: NSColor(red: 0.455, green: 0.382, blue: 0.308, alpha: 1.0),
        accentColor: NSColor(red: 0.798, green: 0.462, blue: 0.108, alpha: 1.0),
        errorColor: NSColor(red: 0.778, green: 0.252, blue: 0.182, alpha: 1.0),
        successColor: NSColor(red: 0.238, green: 0.542, blue: 0.398, alpha: 1.0),
        inputBg: NSColor(red: 0.998, green: 0.985, blue: 0.965, alpha: 0.98),
        inputCornerRadius: 12,
        bubbleBg: NSColor(red: 0.994, green: 0.944, blue: 0.868, alpha: 0.96),
        bubbleBorder: NSColor(red: 0.848, green: 0.638, blue: 0.338, alpha: 0.48),
        bubbleText: NSColor(red: 0.438, green: 0.342, blue: 0.268, alpha: 1.0),
        bubbleCompletionBorder: NSColor(red: 0.28, green: 0.72, blue: 0.48, alpha: 0.62),
        bubbleCompletionText: NSColor(red: 0.18, green: 0.58, blue: 0.38, alpha: 1.0),
        bubbleFont: NSFont.systemFont(ofSize: 11, weight: .semibold),
        bubbleCornerRadius: 14
    )

    static let wii = PopoverTheme(
        name: "Cloud",
        popoverBg: NSColor(red: 0.955, green: 0.960, blue: 0.970, alpha: 0.97),
        popoverBorder: NSColor(red: 0.718, green: 0.748, blue: 0.800, alpha: 0.48),
        popoverBorderWidth: 0.75,
        popoverCornerRadius: 26,
        titleBarBg: NSColor(red: 0.900, green: 0.914, blue: 0.935, alpha: 1.0),
        titleText: NSColor(red: 0.218, green: 0.218, blue: 0.278, alpha: 1.0),
        titleFont: NSFont(name: "Optima-Bold", size: 11) ?? .systemFont(ofSize: 11, weight: .semibold),
        titleString: "Orbit",
        separatorColor: NSColor(red: 0.718, green: 0.748, blue: 0.800, alpha: 0.32),
        font: NSFont(name: "Optima", size: 13) ?? .systemFont(ofSize: 13, weight: .regular),
        fontBold: NSFont(name: "Optima-Bold", size: 13) ?? .systemFont(ofSize: 13, weight: .semibold),
        textPrimary: NSColor(red: 0.118, green: 0.118, blue: 0.168, alpha: 1.0),
        textDim: NSColor(red: 0.478, green: 0.478, blue: 0.538, alpha: 1.0),
        accentColor: NSColor(red: 0.0, green: 0.438, blue: 0.818, alpha: 1.0),
        errorColor: NSColor(red: 0.848, green: 0.198, blue: 0.148, alpha: 1.0),
        successColor: NSColor(red: 0.178, green: 0.618, blue: 0.278, alpha: 1.0),
        inputBg: NSColor(red: 0.992, green: 0.995, blue: 1.000, alpha: 1.0),
        inputCornerRadius: 10,
        bubbleBg: NSColor(red: 0.940, green: 0.950, blue: 0.975, alpha: 0.95),
        bubbleBorder: NSColor(red: 0.0, green: 0.438, blue: 0.818, alpha: 0.32),
        bubbleText: NSColor(red: 0.418, green: 0.438, blue: 0.518, alpha: 1.0),
        bubbleCompletionBorder: NSColor(red: 0.178, green: 0.678, blue: 0.278, alpha: 0.52),
        bubbleCompletionText: NSColor(red: 0.118, green: 0.518, blue: 0.178, alpha: 1.0),
        bubbleFont: NSFont(name: "Optima", size: 10) ?? .systemFont(ofSize: 10, weight: .regular),
        bubbleCornerRadius: 10
    )

    static let iPod = PopoverTheme(
        name: "Moss",
        popoverBg: NSColor(red: 0.798, green: 0.828, blue: 0.755, alpha: 0.98),
        popoverBorder: NSColor(red: 0.518, green: 0.558, blue: 0.472, alpha: 0.88),
        popoverBorderWidth: 2.0,
        popoverCornerRadius: 10,
        titleBarBg: NSColor(red: 0.698, green: 0.732, blue: 0.658, alpha: 1.0),
        titleText: NSColor(red: 0.118, green: 0.138, blue: 0.078, alpha: 1.0),
        titleFont: NSFont(name: "Chicago", size: 11) ?? .systemFont(ofSize: 11, weight: .bold),
        titleString: "Orbit",
        separatorColor: NSColor(red: 0.518, green: 0.558, blue: 0.472, alpha: 0.52),
        font: NSFont(name: "Geneva", size: 11) ?? .monospacedSystemFont(ofSize: 11, weight: .regular),
        fontBold: NSFont(name: "Geneva", size: 11) ?? .monospacedSystemFont(ofSize: 11, weight: .bold),
        textPrimary: NSColor(red: 0.078, green: 0.098, blue: 0.058, alpha: 1.0),
        textDim: NSColor(red: 0.318, green: 0.358, blue: 0.268, alpha: 1.0),
        accentColor: NSColor(red: 0.148, green: 0.418, blue: 0.178, alpha: 1.0),
        errorColor: NSColor(red: 0.578, green: 0.118, blue: 0.078, alpha: 1.0),
        successColor: NSColor(red: 0.118, green: 0.378, blue: 0.118, alpha: 1.0),
        inputBg: NSColor(red: 0.858, green: 0.888, blue: 0.818, alpha: 1.0),
        inputCornerRadius: 4,
        bubbleBg: NSColor(red: 0.808, green: 0.838, blue: 0.765, alpha: 0.96),
        bubbleBorder: NSColor(red: 0.518, green: 0.558, blue: 0.472, alpha: 0.62),
        bubbleText: NSColor(red: 0.378, green: 0.398, blue: 0.338, alpha: 1.0),
        bubbleCompletionBorder: NSColor(red: 0.178, green: 0.498, blue: 0.178, alpha: 0.62),
        bubbleCompletionText: NSColor(red: 0.118, green: 0.378, blue: 0.118, alpha: 1.0),
        bubbleFont: NSFont(name: "Geneva", size: 10) ?? .monospacedSystemFont(ofSize: 10, weight: .medium),
        bubbleCornerRadius: 6
    )

    // Deep indigo night with warm amber accents
    static let dusk = PopoverTheme(
        name: "Dusk",
        popoverBg: NSColor(red: 0.068, green: 0.068, blue: 0.135, alpha: 0.97),
        popoverBorder: NSColor(red: 0.818, green: 0.608, blue: 0.218, alpha: 0.50),
        popoverBorderWidth: 1.0,
        popoverCornerRadius: 28,
        titleBarBg: NSColor(red: 0.108, green: 0.108, blue: 0.205, alpha: 1.0),
        titleText: NSColor(red: 0.940, green: 0.778, blue: 0.418, alpha: 1.0),
        titleFont: NSFont(name: "Avenir Next Demi Bold", size: 11) ?? .systemFont(ofSize: 11, weight: .semibold),
        titleString: "Orbit",
        separatorColor: NSColor(red: 0.818, green: 0.608, blue: 0.218, alpha: 0.24),
        font: NSFont(name: "Avenir Next Regular", size: 13) ?? .systemFont(ofSize: 13, weight: .regular),
        fontBold: NSFont(name: "Avenir Next Demi Bold", size: 13) ?? .systemFont(ofSize: 13, weight: .semibold),
        textPrimary: NSColor(red: 0.878, green: 0.878, blue: 0.958, alpha: 1.0),
        textDim: NSColor(red: 0.518, green: 0.518, blue: 0.668, alpha: 1.0),
        accentColor: NSColor(red: 0.940, green: 0.708, blue: 0.278, alpha: 1.0),
        errorColor: NSColor(red: 1.0, green: 0.418, blue: 0.358, alpha: 1.0),
        successColor: NSColor(red: 0.348, green: 0.878, blue: 0.598, alpha: 1.0),
        inputBg: NSColor(red: 0.118, green: 0.118, blue: 0.225, alpha: 1.0),
        inputCornerRadius: 12,
        bubbleBg: NSColor(red: 0.108, green: 0.108, blue: 0.198, alpha: 0.96),
        bubbleBorder: NSColor(red: 0.818, green: 0.608, blue: 0.218, alpha: 0.50),
        bubbleText: NSColor(red: 0.678, green: 0.678, blue: 0.818, alpha: 1.0),
        bubbleCompletionBorder: NSColor(red: 0.348, green: 0.878, blue: 0.598, alpha: 0.60),
        bubbleCompletionText: NSColor(red: 0.348, green: 0.878, blue: 0.598, alpha: 1.0),
        bubbleFont: NSFont(name: "Avenir Next Regular", size: 10) ?? .systemFont(ofSize: 10, weight: .regular),
        bubbleCornerRadius: 14
    )

    static let harbor = PopoverTheme(
        name: "Orbit",
        // Orbit brand palette — clean neutrals with indigo accent (#6366F1).
        // Matches the design tokens at get-orbit/app/globals.css:
        //   --orbit-brand: #6366F1, --orbit-active: #F59E0B,
        //   --orbit-complete: #10B981. Neutral surfaces from Tailwind
        //   neutral-50/100/200/500/900.
        popoverBg: NSColor(red: 0.980, green: 0.980, blue: 0.984, alpha: 1.0),     // neutral-50
        popoverBorder: NSColor(red: 0.388, green: 0.400, blue: 0.945, alpha: 0.20),  // indigo at low alpha
        popoverBorderWidth: 1.0,
        popoverCornerRadius: 22,
        titleBarBg: NSColor(red: 0.965, green: 0.965, blue: 0.971, alpha: 1.0),    // neutral-100
        titleText: NSColor(red: 0.039, green: 0.039, blue: 0.043, alpha: 1.0),     // neutral-950
        titleFont: NSFont.systemFont(ofSize: 14, weight: .semibold),
        titleString: "Orbit",
        separatorColor: NSColor(red: 0.886, green: 0.890, blue: 0.910, alpha: 0.60),  // neutral-200
        font: NSFont.systemFont(ofSize: 14, weight: .regular),
        fontBold: NSFont.systemFont(ofSize: 14, weight: .semibold),
        textPrimary: NSColor(red: 0.063, green: 0.063, blue: 0.071, alpha: 1.0),    // neutral-900
        textDim: NSColor(red: 0.439, green: 0.439, blue: 0.478, alpha: 1.0),        // neutral-500
        accentColor: NSColor(red: 0.388, green: 0.400, blue: 0.945, alpha: 1.0),    // #6366F1 orbit-brand
        errorColor: NSColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1.0),     // red-500
        successColor: NSColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 1.0),   // #10B981 orbit-complete
        inputBg: NSColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1.0),        // white
        inputCornerRadius: 22,
        bubbleBg: NSColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1.0),       // white
        bubbleBorder: NSColor(red: 0.886, green: 0.890, blue: 0.910, alpha: 0.60),  // neutral-200
        bubbleText: NSColor(red: 0.063, green: 0.063, blue: 0.071, alpha: 1.0),     // neutral-900
        bubbleCompletionBorder: NSColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 0.50),
        bubbleCompletionText: NSColor(red: 0.040, green: 0.588, blue: 0.408, alpha: 1.0),
        bubbleFont: NSFont.systemFont(ofSize: 11, weight: .medium),
        bubbleCornerRadius: 18
    )

    // MARK: - Orbit brand themes (get-orbit design tokens)
    //
    // One accent — indigo #6366F1. Amber #F59E0B and emerald #10B981 carry
    // MEANING only (active / complete). Flat surfaces, hairline borders,
    // restrained rounding. Fonts: SF Pro body (≈ Inter), SF Mono code
    // (≈ JetBrains Mono), SF Pro Rounded semibold wordmark (≈ Bricolage).
    //
    // Hex → RGB reference:
    //   indigo #6366F1 (0.388, 0.400, 0.945) · strong #4F46E5 (0.310, 0.275, 0.898)
    //   soft   #818CF8 (0.506, 0.549, 0.973) · amber  #F59E0B (0.961, 0.620, 0.043)
    //   emerald #10B981 (0.063, 0.725, 0.506) · red #EF4444 (0.937, 0.267, 0.267)

    // Tokens converted 1:1 from the get-orbit on-rails popover demo
    // (get-orbit/app/mac/orbit-demo-client.tsx), which the founder set as
    // the canonical spec. CSS → native mapping:
    //   panel bg            #1A1A22 → (0.102, 0.102, 0.133)   [bg-[#1A1A22]]
    //   titlebar bg         #15151D → (0.082, 0.082, 0.114)   [composer bg-[#15151D]]
    //   rounded-2xl         16                                 [panel radius]
    //   panel border        white/8%                           [border-white/[0.08]]
    //   assistant text      neutral-100 #F5F5F5 → (0.961…)     [text-neutral-100]
    //   muted / subtitle    neutral-400 #A3A3A3 → (0.639…)     [text-neutral-400]
    //   indigo accent       #6366F1 → (0.388, 0.400, 0.945)
    //   user / surface      #2D2D38 → (0.176, 0.176, 0.220)    [bg-[#2D2D38]]
    //   sources link        #A5B4FC → (0.647, 0.706, 0.988)    [text-[#A5B4FC]]
    static let orbitDark = PopoverTheme(
        name: "Orbit Dark",
        popoverBg: NSColor(red: 0.102, green: 0.102, blue: 0.133, alpha: 1.0),       // #1A1A22 demo panel
        popoverBorder: NSColor(white: 1.0, alpha: 0.08),                             // white hairline @ 8%
        popoverBorderWidth: 1.0,
        popoverCornerRadius: 16,                                                      // rounded-2xl
        titleBarBg: NSColor(red: 0.082, green: 0.082, blue: 0.114, alpha: 1.0),      // #15151D demo composer/chrome
        titleText: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),             // white title (demo text-white)
        titleFont: PopoverTheme.wordmarkFont(size: 15),
        titleString: "Orbit",
        separatorColor: NSColor(white: 1.0, alpha: 0.07),                            // white hairline @ 7% (border-white/[0.06])
        font: NSFont.systemFont(ofSize: 13.5, weight: .regular),
        fontBold: NSFont.systemFont(ofSize: 13.5, weight: .semibold),
        textPrimary: NSColor(red: 0.961, green: 0.961, blue: 0.961, alpha: 1.0),     // #F5F5F5 neutral-100 assistant text
        textDim: NSColor(red: 0.639, green: 0.639, blue: 0.639, alpha: 1.0),         // #A3A3A3 neutral-400 muted/subtitle
        accentColor: NSColor(red: 0.388, green: 0.400, blue: 0.945, alpha: 1.0),     // #6366F1 indigo
        errorColor: NSColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1.0),      // #EF4444
        successColor: NSColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 1.0),    // #10B981 emerald
        activeColor: NSColor(red: 0.961, green: 0.620, blue: 0.043, alpha: 1.0),     // #F59E0B amber
        inputBg: NSColor(red: 0.176, green: 0.176, blue: 0.220, alpha: 1.0),         // #2D2D38 demo composer field / surface
        inputCornerRadius: 12,                                                        // rounded-xl composer/bubble
        bubbleBg: NSColor(red: 0.176, green: 0.176, blue: 0.220, alpha: 1.0),        // #2D2D38 demo bubble surface
        bubbleBorder: NSColor(white: 1.0, alpha: 0.08),                              // white hairline @ 8%
        bubbleText: NSColor(red: 0.961, green: 0.961, blue: 0.961, alpha: 1.0),      // #F5F5F5 neutral-100 body
        bubbleCompletionBorder: NSColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 0.45), // emerald
        bubbleCompletionText: NSColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 1.0),    // emerald
        bubbleFont: NSFont.systemFont(ofSize: 13.5, weight: .regular),
        bubbleCornerRadius: 12                                                        // rounded-xl bubble
    )

    static let orbitLight = PopoverTheme(
        name: "Orbit Light",
        popoverBg: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),             // #FFFFFF
        popoverBorder: NSColor(white: 0.0, alpha: 0.08),                             // black hairline @ 8%
        popoverBorderWidth: 1.0,
        popoverCornerRadius: 15,
        titleBarBg: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),            // white, flat
        titleText: NSColor(red: 0.063, green: 0.063, blue: 0.071, alpha: 1.0),       // #101012
        titleFont: PopoverTheme.wordmarkFont(size: 15),
        titleString: "Orbit",
        separatorColor: NSColor(white: 0.0, alpha: 0.07),                            // black hairline @ 7%
        font: NSFont.systemFont(ofSize: 13.5, weight: .regular),
        fontBold: NSFont.systemFont(ofSize: 13.5, weight: .semibold),
        textPrimary: NSColor(red: 0.063, green: 0.063, blue: 0.071, alpha: 1.0),     // #101012
        textDim: NSColor(red: 0.541, green: 0.541, blue: 0.576, alpha: 1.0),         // #8A8A93 dim
        accentColor: NSColor(red: 0.388, green: 0.400, blue: 0.945, alpha: 1.0),     // #6366F1 indigo
        errorColor: NSColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1.0),      // #EF4444
        successColor: NSColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 1.0),    // #10B981 emerald
        activeColor: NSColor(red: 0.961, green: 0.620, blue: 0.043, alpha: 1.0),     // #F59E0B amber
        inputBg: NSColor(red: 0.965, green: 0.965, blue: 0.969, alpha: 1.0),         // #F6F6F7 field
        inputCornerRadius: 11,
        bubbleBg: NSColor(red: 0.965, green: 0.965, blue: 0.969, alpha: 1.0),        // #F6F6F7 surface
        bubbleBorder: NSColor(white: 0.0, alpha: 0.08),                              // black hairline @ 8%
        bubbleText: NSColor(red: 0.247, green: 0.247, blue: 0.275, alpha: 1.0),      // #3F3F46 body
        bubbleCompletionBorder: NSColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 0.45), // emerald
        bubbleCompletionText: NSColor(red: 0.040, green: 0.588, blue: 0.408, alpha: 1.0),    // emerald (darker for contrast)
        bubbleFont: NSFont.systemFont(ofSize: 13.5, weight: .regular),
        bubbleCornerRadius: 13
    )

    /// Indigo-300 #A5B4FC — secondary accent (Sources links, speaker label,
    /// inline code tint). Matches the demo's `text-[#A5B4FC]` source links
    /// and the soft-indigo used for the assistant speaker label. Not part of
    /// the memberwise init; derived so both Orbit themes expose it.
    static let softAccent = NSColor(red: 0.647, green: 0.706, blue: 0.988, alpha: 1.0)

    /// Confident rounded-design wordmark font (SF Pro Rounded ≈ Bricolage
    /// stand-in). Falls back to plain system semibold if the rounded
    /// design descriptor is unavailable.
    static func wordmarkFont(size: CGFloat = 15) -> NSFont {
        // Plain SF Pro semibold — same face as the bubble speaker label
        // ("Orbit"), so the two never read as different fonts. Sharp, not
        // rounded, which also sits closer to get-orbit's grotesque wordmark.
        NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    // The get-orbit demo (the canonical design spec) is a SINGLE dark
    // theme. The popover therefore forces the demo's dark look regardless
    // of the system appearance, rather than following light/dark. The
    // light variant (`orbitLight`) is retained below as a faithful
    // derived twin — currently unreferenced — so a future opt-in light
    // mode can be wired without re-deriving the palette. To restore
    // system-following, put both back in `allThemes` and switch
    // `resolvedForSystemAppearance()` back to the appearance branch.
    static let allThemes: [PopoverTheme] = [.orbitDark]

    /// Active theme. Always the Orbit dark theme — the demo is one look.
    /// `_currentOverride` still lets the Style menu pin a theme if ever
    /// needed, but by default we force dark.
    static var _currentOverride: PopoverTheme? = nil
    static var current: PopoverTheme {
        get {
            if let override = _currentOverride { return override }
            return resolvedForSystemAppearance()
        }
        set { _currentOverride = newValue }
    }

    /// Force the demo's single dark theme (name kept for call-site
    /// compatibility — it no longer varies by system appearance).
    static func resolvedForSystemAppearance() -> PopoverTheme {
        .orbitDark
    }

    static var customFontName: String? = nil
    static var customFontSize: CGFloat = 14

    // MARK: - Theme Modifiers

    func withCharacterColor(_ color: NSColor) -> PopoverTheme {
        guard name == "Peach" else { return self }
        guard let rgbColor = color.usingColorSpace(.deviceRGB) else { return self }
        let r = rgbColor.redComponent
        let g = rgbColor.greenComponent
        let b = rgbColor.blueComponent
        let light = NSColor(red: min(r + 0.4, 1), green: min(g + 0.4, 1), blue: min(b + 0.4, 1), alpha: 0.25)
        let border = NSColor(red: r, green: g, blue: b, alpha: 0.6)
        return PopoverTheme(
            name: name, popoverBg: popoverBg,
            popoverBorder: border,
            popoverBorderWidth: popoverBorderWidth, popoverCornerRadius: popoverCornerRadius,
            titleBarBg: NSColor(red: min(r * 0.3 + 0.7, 1), green: min(g * 0.3 + 0.7, 1), blue: min(b * 0.3 + 0.7, 1), alpha: 1.0),
            titleText: color, titleFont: titleFont, titleString: titleString,
            separatorColor: light,
            font: font, fontBold: fontBold,
            textPrimary: textPrimary, textDim: textDim,
            accentColor: color,
            errorColor: errorColor, successColor: successColor,
            inputBg: inputBg, inputCornerRadius: inputCornerRadius,
            bubbleBg: NSColor(red: min(r * 0.15 + 0.85, 1), green: min(g * 0.15 + 0.85, 1), blue: min(b * 0.15 + 0.85, 1), alpha: 0.95),
            bubbleBorder: border,
            bubbleText: bubbleText,
            bubbleCompletionBorder: bubbleCompletionBorder, bubbleCompletionText: bubbleCompletionText,
            bubbleFont: bubbleFont, bubbleCornerRadius: bubbleCornerRadius
        )
    }

    func withCustomFont() -> PopoverTheme {
        // Midnight uses its own mono font — don't override
        guard name != "Midnight" else { return self }
        guard let fontName = PopoverTheme.customFontName,
              let baseFont = NSFont(name: fontName, size: PopoverTheme.customFontSize) else { return self }
        let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        let smallFont = NSFont(name: fontName, size: PopoverTheme.customFontSize - 1) ?? baseFont
        return PopoverTheme(
            name: name, popoverBg: popoverBg, popoverBorder: popoverBorder,
            popoverBorderWidth: popoverBorderWidth, popoverCornerRadius: popoverCornerRadius,
            titleBarBg: titleBarBg, titleText: titleText, titleFont: titleFont, titleString: titleString,
            separatorColor: separatorColor,
            font: baseFont, fontBold: boldFont,
            textPrimary: textPrimary, textDim: textDim, accentColor: accentColor,
            errorColor: errorColor, successColor: successColor,
            inputBg: inputBg, inputCornerRadius: inputCornerRadius,
            bubbleBg: bubbleBg, bubbleBorder: bubbleBorder, bubbleText: bubbleText,
            bubbleCompletionBorder: bubbleCompletionBorder, bubbleCompletionText: bubbleCompletionText,
            bubbleFont: smallFont, bubbleCornerRadius: bubbleCornerRadius
        )
    }

    var rgbPopoverBackground: NSColor {
        popoverBg.usingColorSpace(.deviceRGB) ?? popoverBg
    }
}
