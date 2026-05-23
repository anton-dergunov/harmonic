import SwiftUI

enum MenuBarElement: String, CaseIterable, Identifiable {
    case albumArtThumb  = "albumArtThumb"
    case trackInfo      = "trackInfo"
    case previousTrack  = "previousTrack"
    case playPause      = "playPause"
    case nextTrack      = "nextTrack"
    case like           = "like"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .albumArtThumb:  return "Album Art"
        case .trackInfo:      return "Track Info"
        case .previousTrack:  return "Previous Track"
        case .playPause:      return "Play / Pause"
        case .nextTrack:      return "Next Track"
        case .like:           return "Like"
        }
    }

    var systemImage: String {
        switch self {
        case .albumArtThumb:  return "photo"
        case .trackInfo:      return "text.justify.leading"
        case .previousTrack:  return "backward.end.fill"
        case .playPause:      return "playpause.fill"
        case .nextTrack:      return "forward.end.fill"
        case .like:           return "heart"
        }
    }
}

enum AlbumArtStyle: String, CaseIterable, Identifiable {
    case color     = "color"
    case faded     = "faded"
    case grayscale = "grayscale"

    var title: String {
        switch self {
        case .color:     return "Color"
        case .faded:     return "Faded"
        case .grayscale: return "Grayscale"
        }
    }

    var id: String { rawValue }

    // Saturation multiplier to apply when rendering.
    var saturation: Double {
        switch self {
        case .color:     return 1.0
        case .faded:     return 0.3
        case .grayscale: return 0.0
        }
    }
}

@MainActor
final class MenuBarSettings: ObservableObject {

    static let shared = MenuBarSettings()
    private let ud = UserDefaults.standard

    // MARK: Visibility

    @Published var showAlbumArtThumb: Bool = false {
        didSet { ud.set(showAlbumArtThumb, forKey: "menuBar.showAlbumArtThumb") }
    }
    @Published var showTrackInfo: Bool = true {
        didSet { ud.set(showTrackInfo, forKey: "menuBar.showTrackInfo") }
    }
    @Published var showPreviousTrack: Bool = false {
        didSet { ud.set(showPreviousTrack, forKey: "menuBar.showPreviousTrack") }
    }
    @Published var showPlayPause: Bool = false {
        didSet { ud.set(showPlayPause, forKey: "menuBar.showPlayPause") }
    }
    @Published var showNextTrack: Bool = true {
        didSet { ud.set(showNextTrack, forKey: "menuBar.showNextTrack") }
    }
    @Published var showLikeButton: Bool = true {
        didSet { ud.set(showLikeButton, forKey: "menuBar.showLikeButton") }
    }

    // MARK: Element order

    @Published var elementOrder: [MenuBarElement] = MenuBarElement.allCases {
        didSet {
            ud.set(
                elementOrder.map(\.rawValue).joined(separator: ","),
                forKey: "menuBar.elementOrder"
            )
        }
    }

    // MARK: Track info — templates

    @Published var showTwoLines: Bool = true {
        didSet { ud.set(showTwoLines, forKey: "menuBar.showTwoLines") }
    }
    @Published var line1Template: String = "{artist}" {
        didSet { ud.set(line1Template, forKey: "menuBar.line1Template") }
    }
    @Published var line2Template: String = "{song}" {
        didSet { ud.set(line2Template, forKey: "menuBar.line2Template") }
    }
    @Published var dimSecondLine: Bool = true {
        didSet { ud.set(dimSecondLine, forKey: "menuBar.dimSecondLine") }
    }

    // MARK: Track info — fonts

    @Published var artistFontSize: Double = 11 {
        didSet { ud.set(artistFontSize, forKey: "menuBar.artistFontSize") }
    }
    @Published var artistBold: Bool = true {
        didSet { ud.set(artistBold, forKey: "menuBar.artistBold") }
    }
    @Published var songFontSize: Double = 10 {
        didSet { ud.set(songFontSize, forKey: "menuBar.songFontSize") }
    }
    @Published var songBold: Bool = false {
        didSet { ud.set(songBold, forKey: "menuBar.songBold") }
    }

    // MARK: Buttons

    @Published var buttonIconSize: Double = 14 {
        didSet { ud.set(buttonIconSize, forKey: "menuBar.buttonIconSize") }
    }
    @Published var buttonColumnWidth: Double = 28 {
        didSet { ud.set(buttonColumnWidth, forKey: "menuBar.buttonColumnWidth") }
    }

    // MARK: Colors

    @Published var useCustomForeground: Bool = false {
        didSet { ud.set(useCustomForeground, forKey: "menuBar.useCustomForeground") }
    }
    @Published var foregroundRed:   Double = 1.0 {
        didSet { ud.set(foregroundRed,   forKey: "menuBar.foregroundRed") }
    }
    @Published var foregroundGreen: Double = 1.0 {
        didSet { ud.set(foregroundGreen, forKey: "menuBar.foregroundGreen") }
    }
    @Published var foregroundBlue:  Double = 1.0 {
        didSet { ud.set(foregroundBlue,  forKey: "menuBar.foregroundBlue") }
    }
    @Published var foregroundAlpha: Double = 1.0 {
        didSet { ud.set(foregroundAlpha, forKey: "menuBar.foregroundAlpha") }
    }

    // Resolved color used by MenuBarItemView at render time.
    var effectiveForeground: Color {
        useCustomForeground
            ? Color(red: foregroundRed, green: foregroundGreen,
                    blue: foregroundBlue, opacity: foregroundAlpha)
            : Color(nsColor: .labelColor)
    }

    // MARK: Album art thumbnail

    @Published var albumArtThumbSize: Double = 18 {
        didSet { ud.set(albumArtThumbSize, forKey: "menuBar.albumArtThumbSize") }
    }
    @Published var albumArtThumbStyle: AlbumArtStyle = .color {
        didSet { ud.set(albumArtThumbStyle.rawValue, forKey: "menuBar.albumArtThumbStyle") }
    }

    // MARK: Album art background

    @Published var showAlbumArtBackground: Bool = false {
        didSet { ud.set(showAlbumArtBackground, forKey: "menuBar.showAlbumArtBackground") }
    }
    @Published var albumArtBgStyle: AlbumArtStyle = .faded {
        didSet { ud.set(albumArtBgStyle.rawValue, forKey: "menuBar.albumArtBgStyle") }
    }
    @Published var albumArtBgOpacity: Double = 0.35 {
        didSet { ud.set(albumArtBgOpacity, forKey: "menuBar.albumArtBgOpacity") }
    }

    // MARK: Layout

    @Published var itemWidth: Double = 150 {
        didSet { ud.set(itemWidth, forKey: "menuBar.itemWidth") }
    }

    // MARK: Init / load

    private init() {
        if let v = ud.object(forKey: "menuBar.showAlbumArtThumb")  as? Bool   { showAlbumArtThumb  = v }
        if let v = ud.object(forKey: "menuBar.showTrackInfo")       as? Bool   { showTrackInfo       = v }
        if let v = ud.object(forKey: "menuBar.showPreviousTrack")   as? Bool   { showPreviousTrack   = v }
        if let v = ud.object(forKey: "menuBar.showPlayPause")       as? Bool   { showPlayPause       = v }
        if let v = ud.object(forKey: "menuBar.showNextTrack")       as? Bool   { showNextTrack       = v }
        if let v = ud.object(forKey: "menuBar.showLikeButton")      as? Bool   { showLikeButton      = v }

        if let raw = ud.string(forKey: "menuBar.elementOrder") {
            let parsed = raw.split(separator: ",").compactMap { MenuBarElement(rawValue: String($0)) }
            elementOrder = parsed + MenuBarElement.allCases.filter { !parsed.contains($0) }
        }

        if let v = ud.object(forKey: "menuBar.showTwoLines")    as? Bool   { showTwoLines    = v }
        if let v = ud.string(forKey: "menuBar.line1Template")               { line1Template   = v }
        if let v = ud.string(forKey: "menuBar.line2Template")               { line2Template   = v }
        if let v = ud.object(forKey: "menuBar.dimSecondLine")   as? Bool   { dimSecondLine   = v }

        if let v = ud.object(forKey: "menuBar.artistFontSize")   as? Double { artistFontSize   = v }
        if let v = ud.object(forKey: "menuBar.artistBold")        as? Bool   { artistBold        = v }
        if let v = ud.object(forKey: "menuBar.songFontSize")      as? Double { songFontSize      = v }
        if let v = ud.object(forKey: "menuBar.songBold")          as? Bool   { songBold          = v }

        if let v = ud.object(forKey: "menuBar.buttonIconSize")    as? Double { buttonIconSize    = v }
        if let v = ud.object(forKey: "menuBar.buttonColumnWidth") as? Double { buttonColumnWidth = v }

        if let v = ud.object(forKey: "menuBar.useCustomForeground") as? Bool   { useCustomForeground = v }
        if let v = ud.object(forKey: "menuBar.foregroundRed")        as? Double { foregroundRed        = v }
        if let v = ud.object(forKey: "menuBar.foregroundGreen")      as? Double { foregroundGreen      = v }
        if let v = ud.object(forKey: "menuBar.foregroundBlue")       as? Double { foregroundBlue       = v }
        if let v = ud.object(forKey: "menuBar.foregroundAlpha")      as? Double { foregroundAlpha      = v }

        if let v = ud.object(forKey: "menuBar.albumArtThumbSize") as? Double    { albumArtThumbSize  = v }
        if let raw = ud.string(forKey: "menuBar.albumArtThumbStyle"),
           let s   = AlbumArtStyle(rawValue: raw)                               { albumArtThumbStyle = s }

        if let v   = ud.object(forKey: "menuBar.showAlbumArtBackground") as? Bool   { showAlbumArtBackground = v }
        if let raw = ud.string(forKey: "menuBar.albumArtBgStyle"),
           let s   = AlbumArtStyle(rawValue: raw)                               { albumArtBgStyle        = s }
        if let v   = ud.object(forKey: "menuBar.albumArtBgOpacity")      as? Double { albumArtBgOpacity      = v }

        if let v = ud.object(forKey: "menuBar.itemWidth") as? Double { itemWidth = v }
    }

    // MARK: Reset

    func resetToDefaults() {
        showAlbumArtThumb      = false
        showTrackInfo          = true
        showPreviousTrack      = false
        showPlayPause          = false
        showNextTrack          = true
        showLikeButton         = true
        elementOrder           = MenuBarElement.allCases
        showTwoLines           = true
        line1Template          = "{artist}"
        line2Template          = "{song}"
        dimSecondLine          = true
        artistFontSize         = 11
        artistBold             = true
        songFontSize           = 10
        songBold               = false
        buttonIconSize         = 14
        buttonColumnWidth      = 28
        useCustomForeground    = false
        foregroundRed          = 1.0
        foregroundGreen        = 1.0
        foregroundBlue         = 1.0
        foregroundAlpha        = 1.0
        albumArtThumbSize      = 18
        albumArtThumbStyle     = .color
        showAlbumArtBackground = false
        albumArtBgStyle        = .faded
        albumArtBgOpacity      = 0.35
        itemWidth              = 150
    }
}
