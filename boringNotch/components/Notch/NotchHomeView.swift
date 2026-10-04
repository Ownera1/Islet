//
//  NotchHomeView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-18.
//  Modified by Harsh Vardhan Goswami & Richard Kunkli & Mustafa Ramadan
//

import Combine
import Defaults
import SwiftUI
import NotchIntegrationCore

// MARK: - Music Player Components

struct MusicPlayerView: View {
    @EnvironmentObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID
    @Binding var focused: Bool
    let currentDate: Date
    let coverSize: CGFloat
    let infoWidth: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
                .frame(width: coverSize, height: coverSize)
            MusicControlsView(focused: $focused, currentDate: currentDate)
                .frame(width: infoWidth, height: 134)
        }
        .frame(height: 134)
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if Defaults[.lightingEffect] {
                albumArtBackground
            }
            albumArtButton
        }
    }

    private var albumArtBackground: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 40)
            .opacity(musicManager.isPlaying ? 0.5 : 0)
    }

    private var albumArtButton: some View {
        ZStack {
            Button {
                musicManager.openMusicApp()
            } label: {
                ZStack(alignment:.bottomTrailing) {
                    albumArtImage
                    appIconOverlay
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
            
            albumArtDarkOverlay.allowsHitTesting(false)
        }
    }

    private var albumArtDarkOverlay: some View {
        Rectangle()
            .aspectRatio(1, contentMode: .fit)
            .foregroundColor(Color.black)
            .opacity(musicManager.isPlaying ? 0 : 0.8)
            .blur(radius: 50)
    }
                

    private var albumArtImage: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open && !musicManager.usingAppIconForArtwork {
            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 18, height: 18)
                .opacity(0.7)
                .offset(x: 4, y: 4)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
        }
    }
}

struct MusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared
    @Binding var focused: Bool
    let currentDate: Date
    @State private var sliderValue: Double = 0
    @State private var dragging = false
    @State private var lastDragged: Date = .distantPast
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit
    @Default(.enableLyrics) private var enableLyrics
    @Default(.lyricsTimeOffset) private var lyricsTimeOffset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lyricTime: Double {
        musicManager.estimatedPlaybackPosition(at: currentDate) + lyricsTimeOffset
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 6) {
                    titleRow(width: geo.size.width)
                    HomeLyricView(document: musicManager.lyricsDocument,
                                  availability: musicManager.lyricsAvailability,
                                  elapsed: lyricTime, duration: musicManager.songDuration,
                                  date: currentDate, reduceMotion: reduceMotion)
                        .frame(height: focused || !enableLyrics || musicManager.lyricsAvailability == .unavailable ? 0 : 40)
                        .opacity(focused ? 0 : 1)
                        .clipped()
                }
                .frame(maxHeight: .infinity, alignment: musicManager.lyricsAvailability == .unavailable || !enableLyrics ? .center : .top)
            }
            .frame(height: 72)
            MusicSliderView(
                sliderValue: $sliderValue, duration: $musicManager.songDuration,
                lastDragged: $lastDragged, color: musicManager.avgColor, dragging: $dragging,
                currentDate: currentDate, timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime, playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying
            ) { musicManager.seek(to: $0) }
            .frame(height: 34)
            slotToolbar.frame(height: 28)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func titleRow(width: CGFloat) -> some View {
        if focused {
            VStack(alignment: .leading, spacing: 3) {
                Text(musicManager.songTitle).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                Text(musicManager.artistName).font(.system(size: 12)).foregroundStyle(playerAccent)
            }
            .lineLimit(1)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(musicManager.songTitle)
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Text(musicManager.artistName)
                    .font(.system(size: 12)).foregroundStyle(playerAccent)
                    .lineLimit(1).frame(maxWidth: width * 0.45, alignment: .leading)
                    .layoutPriority(1)
            }
        }
    }

    private var playerAccent: Color { Color(red: 0.90, green: 0.38, blue: 0.37) }

    private var slotToolbar: some View {
        HStack(spacing: 2) {
            ForEach(Array(activeSlots.enumerated()), id: \.offset) { _, slot in
                slotView(for: slot)
                    .frame(maxWidth: .infinity)
            }
            if enableLyrics {
                Button { focused.toggle() } label: {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(focused ? .white : Color(white: 0.6))
                        .frame(width: 26, height: 24)
                        .background(focused ? Color(white: 0.17) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .disabled(!musicManager.lyricsAvailability.canFocus)
                .opacity(musicManager.lyricsAvailability.canFocus ? 1 : 0.35)
                .help(focused ? "返回主页模式" : "歌词专注模式")
                .accessibilityLabel(focused ? "返回主页模式" : "歌词专注模式")
                .accessibilityValue(focused ? "已开启" : "已关闭")
            }
        }
    }

    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        let padded = slotConfig.padded(to: sanitizedLimit, filler: .none)
        let configured = Array(padded.prefix(sanitizedLimit))
        let result = configured.filter { $0 != .none }
        // If calendar and camera are both visible alongside music, hide the edge slots
        let shouldHideEdges = Defaults[.showCalendar] && Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
        if shouldHideEdges && result.count >= 5 {
            return Array(result.dropFirst().dropLast())
        }

        return result
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            CompactMusicButton(icon: "shuffle", iconColor: musicManager.isShuffled ? .red : .primary, size: 15) {
                MusicManager.shared.toggleShuffle()
            }
        case .previous:
            CompactMusicButton(icon: "backward.fill", size: 15) {
                MusicManager.shared.previousTrack()
            }
        case .playPause:
            CompactMusicButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", size: 20) {
                MusicManager.shared.togglePlay()
            }
        case .next:
            CompactMusicButton(icon: "forward.fill", size: 15) {
                MusicManager.shared.nextTrack()
            }
        case .repeatMode:
            CompactMusicButton(icon: repeatIcon, iconColor: repeatIconColor, size: 15) {
                MusicManager.shared.toggleRepeat()
            }
        case .volume:
            VolumeControlView()
        case .favorite:
            FavoriteControlButton()
        case .goBackward:
            CompactMusicButton(icon: "gobackward.15", size: 15) {
                MusicManager.shared.skip(seconds: -15)
            }
        case .goForward:
            CompactMusicButton(icon: "goforward.15", size: 15) {
                MusicManager.shared.skip(seconds: 15)
            }
        case .none:
            Color.clear.frame(height: 1)
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            return .primary
        case .all, .one:
            return .red
        }
    }
}

struct FavoriteControlButton: View {
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        HoverButton(icon: iconName, iconColor: iconColor, scale: .medium) {
            MusicManager.shared.toggleFavoriteTrack()
        }
        .disabled(!musicManager.canFavoriteTrack)
        .opacity(musicManager.canFavoriteTrack ? 1 : 0.35)
    }

    private var iconName: String {
        musicManager.isFavoriteTrack ? "heart.fill" : "heart"
    }

    private var iconColor: Color {
        musicManager.isFavoriteTrack ? .red : .primary
    }
}

private extension Array where Element == MusicControlButton {
    func padded(to length: Int, filler: MusicControlButton) -> [MusicControlButton] {
        if count >= length { return self }
        return self + Array(repeating: filler, count: length - count)
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var volumeSliderValue: Double = 0.5
    @State private var dragging: Bool = false
    @State private var showVolumeSlider: Bool = false
    @State private var lastVolumeUpdateTime: Date = Date.distantPast
    private let volumeUpdateThrottle: TimeInterval = 0.1
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                if musicManager.volumeControlSupported {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showVolumeSlider.toggle()
                    }
                }
            }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(musicManager.volumeControlSupported ? .white : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!musicManager.volumeControlSupported)
            .frame(width: 24)

            if showVolumeSlider && musicManager.volumeControlSupported {
                CustomSlider(
                    value: $volumeSliderValue,
                    range: 0.0...1.0,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: .constant(Date.distantPast),
                    onValueChange: { newValue in
                        MusicManager.shared.setVolume(to: newValue)
                    },
                    onDragChange: { newValue in
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            MusicManager.shared.setVolume(to: newValue)
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 48, height: 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
        .onReceive(musicManager.$volume) { volume in
            if !dragging {
                volumeSliderValue = volume
            }
        }
        .onReceive(musicManager.$volumeControlSupported) { supported in
            if !supported {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVolumeSlider = false
                }
            }
        }
        .onChange(of: showVolumeSlider) { _, isShowing in
            if isShowing {
                // Sync volume from app when slider appears
                Task {
                    await MusicManager.shared.syncVolumeFromActiveApp()
                }
            }
        }
        .onDisappear {
            // volumeUpdateTask?.cancel() // No longer needed
        }
    }
    
    
    private var volumeIcon: String {
        if !musicManager.volumeControlSupported {
            return "speaker.slash"
        } else if volumeSliderValue == 0 {
            return "speaker.slash.fill"
        } else if volumeSliderValue < 0.33 {
            return "speaker.1.fill"
        } else if volumeSliderValue < 0.66 {
            return "speaker.2.fill"
        } else {
            return "speaker.3.fill"
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    let albumArtNamespace: Namespace.ID

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
            }
        }
        // simplified: use a straightforward opacity transition
        .transition(.opacity)
    }

    private var shouldShowCamera: Bool {
        Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
    }

    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) private var showCalendar
    @Default(.enableLyrics) private var enableLyrics
    @Default(.autoLyricsFocusWhenCalendarEmpty) private var autoFocus
    @Default(.lyricsTimeOffset) private var lyricsTimeOffset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var focused: Bool { enableLyrics && musicManager.lyricsFocusRequested }
    private var modeAnimation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.4) }

    private var mainContent: some View {
        GeometryReader { geometry in
            let cover: CGFloat = focused ? 104 : 112
            let info: CGFloat = shouldShowCamera ? 160 : (focused ? 180 : 224)
            let right = max(0, geometry.size.width - cover - info - 24)
            TimelineView(.animation(minimumInterval: reduceMotion ? 0.25 : 1.0 / 30,
                                    paused: vm.notchState != .open || coordinator.currentView != .home
                                        || (!musicManager.isPlaying && !musicManager.isFetchingLyrics))) { timeline in
                HStack(alignment: .center, spacing: 12) {
                    MusicPlayerView(albumArtNamespace: albumArtNamespace,
                                    focused: $musicManager.lyricsFocusRequested,
                                    currentDate: timeline.date, coverSize: cover, infoWidth: info)
                    ZStack {
                        // Stable identity preserves the selected date and scroll position across mode changes.
                        HStack(spacing: 10) {
                            if showCalendar {
                                CalendarView()
                                    .frame(width: shouldShowCamera ? min(170, right * 0.6) : right)
                                    .onHover { vm.isHoveringCalendar = !focused && $0 }
                            }
                            if shouldShowCamera {
                                CameraPreviewView(webcamManager: webcamManager).scaledToFit()
                            }
                        }
                        .opacity(focused ? 0 : 1)
                        .allowsHitTesting(!focused)
                        .accessibilityHidden(focused)
                        FocusLyricsView(document: musicManager.lyricsDocument,
                                        availability: musicManager.lyricsAvailability,
                                        elapsed: musicManager.estimatedPlaybackPosition(at: timeline.date) + lyricsTimeOffset,
                                        duration: musicManager.songDuration, date: timeline.date,
                                        reduceMotion: reduceMotion,
                                        seek: { musicManager.seek(to: $0 - lyricsTimeOffset) })
                            .opacity(focused ? 1 : 0)
                            .allowsHitTesting(focused)
                            .accessibilityHidden(!focused)
                    }
                    .frame(width: right, height: 134)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: focused)
                }
            }
        }
        .frame(height: 134)
        .animation(modeAnimation, value: focused)
        .onChange(of: focused) { _, _ in vm.isHoveringCalendar = false }
        .onChange(of: musicManager.lyricsAvailability) { _, state in
            if state == .unavailable { musicManager.lyricsFocusRequested = false }
            enterAutomaticFocusIfNeeded()
        }
        .onChange(of: calendarManager.events) { _, _ in enterAutomaticFocusIfNeeded() }
        .onChange(of: autoFocus) { _, _ in enterAutomaticFocusIfNeeded() }
        .onAppear { enterAutomaticFocusIfNeeded() }
        .blur(radius: vm.notchState == .closed ? 30 : 0)
    }

    private func enterAutomaticFocusIfNeeded() {
        if autoFocus && showCalendar && EventListView.filteredEvents(events: calendarManager.events).isEmpty
            && musicManager.lyricsAvailability.canFocus {
            musicManager.lyricsFocusRequested = true
        }
    }
}


struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    var onValueChange: (Double) -> Void


    var body: some View {
        VStack(spacing: 4) {
            CustomSlider(
                value: $sliderValue,
                range: 0...duration,
                color: Defaults[.sliderColor] == SliderColorEnum.albumArt
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.8)
                    : Defaults[.sliderColor] == SliderColorEnum.accent ? .effectiveAccent : .white,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: onValueChange
            )
            .frame(height: 10, alignment: .center)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(timeString(from: duration))
            }
            .fontWeight(.medium)
            .foregroundStyle(Color(red: 0.90, green: 0.38, blue: 0.37))
            .font(.system(size: 11))
        }
        .onAppear { sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate) }
        .onChange(of: elapsedTime) { _, _ in
            if !dragging { sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate) }
        }
        .onChange(of: currentDate) {
           guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
        }
    }

    func timeString(from seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        }
    }
}

// MARK: - Lyrics presentation

private struct CompactMusicButton: View {
    let icon: String
    var iconColor: Color = .white
    var size: CGFloat = 15
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch icon {
        case "backward.fill": return "上一首"
        case "forward.fill": return "下一首"
        case "pause.fill": return "暂停"
        case "play.fill": return "播放"
        case "shuffle": return "随机播放"
        case "repeat", "repeat.1": return "循环播放"
        case "gobackward.15": return "后退 15 秒"
        case "goforward.15": return "前进 15 秒"
        default: return icon
        }
    }
}

private struct LyricsLoadingPlaceholder: View {
    let date: Date
    let reduceMotion: Bool

    var body: some View {
        Capsule().fill(.white.opacity(reduceMotion ? 0.08 : 0.06 + 0.035 * (1 + sin(date.timeIntervalSinceReferenceDate * 2))))
            .frame(width: 88, height: 5)
            .accessibilityLabel("歌词加载中")
    }
}

private struct InstrumentalLyricsView: View {
    var body: some View {
        Label("纯音乐，请欣赏", systemImage: "music.note")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.65))
    }
}

private struct HomeLyricView: View {
    let document: LyricsDocument
    let availability: LyricsAvailability
    let elapsed: Double
    let duration: Double
    let date: Date
    let reduceMotion: Bool

    var body: some View {
        Group {
            switch availability {
            case .loading:
                LyricsLoadingPlaceholder(date: date, reduceMotion: reduceMotion)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            case .instrumental:
                InstrumentalLyricsView().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            case .unavailable:
                Color.clear
            case .available:
                let index = Lyrics.index(at: elapsed, in: document.lines)
                let shown = index ?? (document.lines.isEmpty ? nil : 0)
                VStack(alignment: .leading, spacing: 3) {
                    if let shown {
                        SweepLyricLine(line: document.lines[shown], elapsed: elapsed,
                                       progress: index == nil ? 0 : Lyrics.progress(at: elapsed, index: shown, in: document.lines, duration: duration),
                                       fontSize: 15, reduceMotion: reduceMotion)
                            .frame(height: 20)
                            .id(shown)
                            .transition(.opacity.combined(with: .offset(y: 6)))
                        if shown + 1 < document.lines.count {
                            Text(document.lines[shown + 1].text)
                                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                        }
                    } else {
                        Text(document.plain.components(separatedBy: .newlines).first(where: { !$0.isEmpty }) ?? "")
                            .font(.system(size: 15, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: shown)
            }
        }
        .clipped()
    }
}

/// Only the lit layer is masked. Explicit endpoints avoid a half-lit first/last character.
private struct SweepText: View {
    let text: String
    let progress: Double

    var body: some View {
        Text(verbatim: text).foregroundStyle(.white.opacity(0.35))
            .overlay {
                Text(verbatim: text).foregroundStyle(.white)
                    .mask {
                        if progress >= 1 {
                            Color.white
                        } else if progress <= 0 {
                            Color.clear
                        } else {
                            let start = min(1, max(0, progress * 1.12 - 0.12))
                            let end = min(1, max(0, progress * 1.12))
                            LinearGradient(stops: [.init(color: .white, location: start),
                                                   .init(color: .clear, location: end)],
                                           startPoint: .leading, endPoint: .trailing)
                        }
                    }
            }
    }
}

private struct SweepLyricLine: View {
    let line: LyricLine
    let elapsed: Double
    let progress: Double
    var fontSize: CGFloat = 16
    let reduceMotion: Bool
    @State private var textWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let overflow = max(0, textWidth - geo.size.width)
            let scroll = min(1, max(0, (progress - 0.1) / 0.8))
            Group {
                if line.words.isEmpty {
                    SweepText(text: line.text, progress: progress)
                } else {
                    HStack(spacing: 0) {
                        ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                            SweepText(text: word.text, progress: progress >= 1 ? 1 : (progress <= 0 ? 0 : word.progress(at: elapsed)))
                        }
                    }
                }
            }
            .font(.system(size: fontSize, weight: .medium))
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: geo.size.height)
            .offset(x: reduceMotion ? 0 : -overflow * scroll)
        }
        .clipped()
        .task(id: line.text + String(Double(fontSize))) {
            textWidth = (line.text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)]).width
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.text)
    }
}

private struct FocusLyricsView: View {
    let document: LyricsDocument
    let availability: LyricsAvailability
    let elapsed: Double
    let duration: Double
    let date: Date
    let reduceMotion: Bool
    let seek: (Double) -> Void
    @State private var following = true
    @State private var resumeTask: Task<Void, Never>?

    private var currentIndex: Int? { Lyrics.index(at: elapsed, in: document.lines) }

    var body: some View {
        Group {
            switch availability {
            case .loading:
                LyricsLoadingPlaceholder(date: date, reduceMotion: reduceMotion)
            case .instrumental:
                InstrumentalLyricsView()
            case .unavailable:
                Color.clear
            case .available:
                if document.lines.isEmpty {
                    ScrollView {
                        Text(document.plain).font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    timedLyrics
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: document) { _, _ in
            resumeTask?.cancel()
            following = true
        }
        .onDisappear { resumeTask?.cancel() }
    }

    private var timedLyrics: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 51.5)
                    ForEach(Array(document.lines.enumerated()), id: \.offset) { index, line in
                        let current = currentIndex ?? 0
                        let distance = abs(index - current)
                        Button {
                            following = true
                            seek(line.time)
                        } label: {
                            SweepLyricLine(line: line, elapsed: elapsed,
                                           progress: index < current ? 1 : (index == current && currentIndex != nil ? Lyrics.progress(at: elapsed, index: index, in: document.lines, duration: duration) : 0),
                                           reduceMotion: reduceMotion)
                                .frame(height: 31)
                                .opacity(distance == 0 ? 1 : max(0.12, 0.42 - Double(distance - 1) * 0.15))
                                .blur(radius: reduceMotion || distance == 0 || distance > 3 ? 0 : min(CGFloat(distance) * 1.2, 3.6))
                                .scaleEffect(distance == 0 ? 1 : 0.92, anchor: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("跳转到这一句")
                        .id(index)
                    }
                    Color.clear.frame(height: 51.5)
                }
            }
            .scrollIndicators(.hidden)
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.24),
                                       .init(color: .white, location: 0.76), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .onAppear { proxy.scrollTo(currentIndex ?? 0, anchor: .center) }
            .onChange(of: currentIndex) { _, index in
                guard following else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85)) {
                    proxy.scrollTo(index ?? 0, anchor: .center)
                }
            }
            .onChange(of: following) { _, follows in
                if follows {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85)) {
                        proxy.scrollTo(currentIndex ?? 0, anchor: .center)
                    }
                }
            }
            .onScrollPhaseChange { old, new in
                if new == .interacting || new == .decelerating {
                    resumeTask?.cancel()
                    following = false
                }
                if new == .idle && old != .animating && !following {
                    resumeTask = Task { @MainActor in
                        do {
                            try await Task.sleep(for: .seconds(4))
                            following = true
                        } catch { }
                    }
                }
            }
        }
    }
}
