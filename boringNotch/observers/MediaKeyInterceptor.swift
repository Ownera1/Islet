//
//  MediaKeyInterceptor.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-23.

import Foundation
import AppKit
import Combine
import Defaults
import AVFoundation

@MainActor
final class MediaKeyInterceptor: ObservableObject {
    static let shared = MediaKeyInterceptor()
    
    private enum NXKeyType: Int {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
        case keyboardBrightnessUp = 21
        case keyboardBrightnessDown = 22
    }
    
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false
    private var generation = 0
    private var isStarting = false
    private let step: Float = 1.0 / 16.0
    private var audioPlayer: AVAudioPlayer?
    
    private init() {}
    
    // MARK: - Accessibility (via XPC)
    
    func requestAccessibilityAuthorization() {
        XPCHelperClient.shared.requestAccessibilityAuthorization()
    }
    
    func ensureAccessibilityAuthorization(promptIfNeeded: Bool = false) async -> Bool {
        await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: promptIfNeeded)
    }
    
    // MARK: - Helper media key events

    func start(promptIfNeeded: Bool = false) async {
        guard Defaults[.hudReplacement], !isRunning, !isStarting else { return }
        isStarting = true
        let request = generation
        defer { if request == generation { isStarting = false } }
        errorMessage = nil
        if promptIfNeeded { _ = await ensureAccessibilityAuthorization(promptIfNeeded: true) }
        guard request == generation, Defaults[.hudReplacement], !Task.isCancelled else { return }
        let client = XPCHelperClient.shared
        client.onMediaKeyDown = { [weak self] code, modifiers in
            guard Defaults[.hudReplacement], self?.isRunning == true else { return }
            self?.handleEvent(keyCode: code, modifiers: modifiers)
        }
        client.onMediaDisconnect = { [weak self] in
            guard let self else { return }
            self.isRunning = false
            if Defaults[.hudReplacement] {
                self.errorMessage = "HUD Helper 连接已中断，请重新开启 HUD。"
                Defaults[.hudReplacement] = false
            }
        }
        let result = await client.startMediaKeyEvents()
        guard request == generation, Defaults[.hudReplacement], !Task.isCancelled else {
            // A later enable owns the same tap; its queued start/stop order is preserved.
            if !Defaults[.hudReplacement] { client.stopMediaKeyEvents() }
            return
        }
        isRunning = result.0
        if !result.0 {
            errorMessage = result.1 ?? "无法启动 HUD 媒体键拦截。"
            Defaults[.hudReplacement] = false
        }
    }

    func stop() {
        generation += 1
        isStarting = false
        isRunning = false
        XPCHelperClient.shared.onMediaKeyDown = nil
        // Queue stop immediately so a subsequent start cannot overtake it.
        XPCHelperClient.shared.stopMediaKeyEvents()
    }

    private func handleEvent(keyCode: Int, modifiers: UInt) {
        guard let keyType = NXKeyType(rawValue: keyCode) else { return }
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        let option = flags.contains(.option)
        let shift = flags.contains(.shift)
        let command = flags.contains(.command)
        if option && !shift && handleOptionAction(for: keyType, command: command) { return }
        handleKeyPress(keyType: keyType, option: option, shift: shift, command: command)
    }

    private func handleOptionAction(for keyType: NXKeyType, command: Bool) -> Bool {
        let action = Defaults[.optionKeyAction]
        
        switch action {
        case .openSettings:
            openSystemSettings(for: keyType, command: command)
            return true
        case .showHUD:
            showHUD(for: keyType, command: command)
            return true
        case .none:
            return true
        }
    }
    
    private func prepareAudioPlayerIfNeeded() {
        guard audioPlayer == nil else { return }

        let defaultPath = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
        if FileManager.default.fileExists(atPath: defaultPath) {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: defaultPath))
                print("🔊 [MediaKeyInterceptor] Loaded default Bezel audio from: \(defaultPath)")
            } catch {
                print("⚠️ [MediaKeyInterceptor] Failed to init AVAudioPlayer with default path \(defaultPath): \(error.localizedDescription)")
            }
        } else {
            print("⚠️ [MediaKeyInterceptor] Default bezel audio not found at: \(defaultPath)")
        }

        if let player = audioPlayer {
            player.volume = 1.0
            player.numberOfLoops = 0
            player.prepareToPlay()
        }
    }

    private func playFeedbackSound() {
        guard let feedback = UserDefaults.standard.persistentDomain(forName: "NSGlobalDomain")?["com.apple.sound.beep.feedback"] as? Int,
              feedback == 1 else { return }

        prepareAudioPlayerIfNeeded()
        guard let player = audioPlayer else {
            print("⚠️ [MediaKeyInterceptor] No audio player available to play feedback sound")
            return
        }
        if let url = player.url {
            print("🔊 [MediaKeyInterceptor] Playing feedback sound from: \(url.path)")
        } else {
            print("🔊 [MediaKeyInterceptor] Playing feedback sound (no url available for AVAudioPlayer)")
        }
        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
        player.play()
    }

    private func handleKeyPress(keyType: NXKeyType, option: Bool, shift: Bool, command: Bool) {
        let stepDivisor: Float = (option && shift) ? 4.0 : 1.0
        
        switch keyType {
        case .soundUp:
            Task { @MainActor in
                self.playFeedbackSound()
                VolumeManager.shared.increase(stepDivisor: stepDivisor)
            }
        case .soundDown:
            Task { @MainActor in
                self.playFeedbackSound()
                VolumeManager.shared.decrease(stepDivisor: stepDivisor)
            }
        case .mute:
            Task { @MainActor in
                VolumeManager.shared.toggleMuteAction()
            }
        case .brightnessUp, .keyboardBrightnessUp:
            let delta = step / stepDivisor
            adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessUp || command)
        case .brightnessDown, .keyboardBrightnessDown:
            let delta = -(step / stepDivisor)
            adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessDown || command)
        }
    }
    
    private func adjustBrightness(delta: Float, keyboard: Bool) {
        Task { @MainActor in
            if keyboard {
                KeyboardBacklightManager.shared.setRelative(delta: delta)
            } else {
                BrightnessManager.shared.setRelative(delta: delta)
            }
        }
    }
    
    private func showHUD(for keyType: NXKeyType, command: Bool) {
        Task { @MainActor in
            switch keyType {
            case .soundUp, .soundDown, .mute:
                let v = VolumeManager.shared.rawVolume
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(v))
            case .brightnessUp, .brightnessDown:
                if command {
                    let v = KeyboardBacklightManager.shared.rawBrightness
                    BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
                } else {
                    let v = BrightnessManager.shared.rawBrightness
                    BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(v))
                }
            case .keyboardBrightnessUp, .keyboardBrightnessDown:
                let v = KeyboardBacklightManager.shared.rawBrightness
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
            }
        }
    }
    
    private func openSystemSettings(for keyType: NXKeyType, command: Bool) {
        let urlString: String
        
        switch keyType {
        case .soundUp, .soundDown, .mute:
            urlString = "x-apple.systempreferences:com.apple.preference.sound"
        case .brightnessUp, .brightnessDown:
            if command {
                urlString = "x-apple.systempreferences:com.apple.preference.keyboard"
            } else {
                urlString = "x-apple.systempreferences:com.apple.preference.displays"
            }
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            urlString = "x-apple.systempreferences:com.apple.preference.keyboard"
        }
        
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
