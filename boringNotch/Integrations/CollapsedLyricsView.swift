import AppKit
import Defaults
import NotchIntegrationCore
import SwiftUI

extension CollapsedLyricsMode: Defaults.Serializable {}

extension Defaults.Keys {
    static let collapsedLyricsMode = Key<CollapsedLyricsMode>("collapsedLyricsMode", default: .externalDisplays)
}

/// Mounted only while the closed music activity (or its lower strip) is visible.
struct CollapsedLyricsView: View {
    @ObservedObject private var music = MusicManager.shared
    @Default(.lyricsTimeOffset) private var timeOffset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var fontSize: CGFloat = 13

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.25 : 1.0 / 30, paused: !music.isPlaying)) { timeline in
            let elapsed = music.estimatedPlaybackPosition(at: timeline.date) + timeOffset
            CollapsedLyricContent(
                frame: CollapsedLyricFrame(document: music.lyricsDocument, elapsed: elapsed, duration: music.songDuration),
                elapsed: elapsed, date: timeline.date, isPlaying: music.isPlaying,
                reduceMotion: reduceMotion, fontSize: fontSize
            )
            .id(music.songTitle + "|" + music.artistName)
        }
    }
}

struct CollapsedLyricContent: View {
    let frame: CollapsedLyricFrame
    let elapsed: Double
    let date: Date
    let isPlaying: Bool
    let reduceMotion: Bool
    var fontSize: CGFloat = 13

    var body: some View {
        ZStack {
            if let line = frame.line {
                CollapsedLyricLine(line: line, elapsed: elapsed, revealProgress: frame.revealProgress,
                                   scrollProgress: frame.scrollProgress, isPlaying: isPlaying,
                                   reduceMotion: reduceMotion, fontSize: fontSize)
                    .id("\(frame.index ?? -1)|\(line.text)")
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 6)),
                        removal: .opacity.combined(with: .offset(y: -6))
                    ))
            } else {
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in
                        let phase = date.timeIntervalSinceReferenceDate * (2 * .pi / 1.4) - Double(index) * 0.8
                        Circle().fill(.white)
                            .frame(width: 5, height: 5)
                            .opacity(!isPlaying ? 0.35 : (reduceMotion ? 0.6 : 0.25 + 0.75 * (sin(phase) + 1) / 2))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("间奏 / 纯音乐")
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.23), value: frame.line == nil ? nil : frame.index)
        .clipped()
    }
}

private struct CollapsedLyricLine: View {
    let line: LyricLine
    let elapsed: Double
    let revealProgress: Double
    let scrollProgress: Double
    let isPlaying: Bool
    let reduceMotion: Bool
    let fontSize: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let width = (line.text as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium)
            ]).width
            let overflow = max(0, width - geometry.size.width)
            let offset = overflow > 0 ? (reduceMotion ? 0 : -overflow * scrollProgress) : (geometry.size.width - width) / 2
            Group {
                if !isPlaying || reduceMotion {
                    Text(verbatim: line.text).foregroundStyle(.white.opacity(isPlaying ? 1 : 0.35))
                } else if line.words.isEmpty {
                    RevealedLyricText(text: line.text, progress: revealProgress)
                } else {
                    HStack(spacing: 0) {
                        ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                            RevealedLyricText(text: word.text, progress: word.progress(at: elapsed))
                        }
                    }
                }
            }
            .font(.system(size: fontSize, weight: .medium))
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: geometry.size.height)
            .offset(x: offset)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            .mask {
                if overflow > 0 {
                    let edge = min(0.49, 14 / max(1, geometry.size.width))
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0), .init(color: .white, location: edge),
                        .init(color: .white, location: 1 - edge), .init(color: .clear, location: 1)
                    ], startPoint: .leading, endPoint: .trailing)
                } else {
                    Rectangle()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.text)
    }
}

/// A sharp reveal edge, with no glow or gradient sweeping over the letters.
private struct RevealedLyricText: View {
    let text: String
    let progress: Double

    var body: some View {
        Text(verbatim: text).foregroundStyle(.white.opacity(0.5))
            .overlay(alignment: .leading) {
                Text(verbatim: text).foregroundStyle(.white)
                    .mask(alignment: .leading) {
                        GeometryReader { geometry in
                            Rectangle().frame(width: geometry.size.width * min(1, max(0, progress)))
                        }
                    }
            }
    }
}

struct CollapsedLyricsSettingsPreview: View {
    let mode: CollapsedLyricsMode
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview(hasNotch: false, title: "无硬件刘海的屏幕")
            preview(hasNotch: true, title: "内置刘海屏")
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: mode)
        .accessibilityElement(children: .combine)
    }

    private func preview(hasNotch: Bool, title: String) -> some View {
        let placement = collapsedLyricsPlacement(mode: enabled ? mode : .off, hasHardwareNotch: hasNotch)
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "music.note").frame(width: 24, height: 24)
                        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                    if placement == .inline {
                        Text("这里显示正在演唱的这一句歌词").font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                    } else {
                        Spacer(minLength: 0)
                    }
                    Image(systemName: "waveform").foregroundStyle(.gray)
                }
                .padding(.horizontal, 14).frame(height: 36)
                if placement == .belowNotch {
                    Text("演唱时常驻，指针靠近自动让开").font(.system(size: 12, weight: .medium))
                        .frame(height: 22).padding(.bottom, 6)
                }
            }
            .frame(width: placement == .inline ? 360 : 230)
            .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .top)
        }
    }
}
