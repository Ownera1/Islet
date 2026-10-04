//
//  PanGesture.swift
//  boringNotch
//
//  Created by Richard Kunkli on 21/08/2024.
//

import AppKit
import SwiftUI

enum PanDirection {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
    var sign: CGFloat { (self == .right || self == .down) ? 1 : -1 }

    func signed(from translation: CGSize) -> CGFloat { (isHorizontal ? translation.width : translation.height) * sign }
    func signed(deltaX: CGFloat, deltaY: CGFloat) -> CGFloat { (isHorizontal ? deltaX : deltaY) * sign }
}

extension View {
    func panGesture(direction: PanDirection, threshold: CGFloat = 4, action: @escaping (CGFloat, NSEvent.Phase) -> Void) -> some View {
        self
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let s = direction.signed(from: value.translation)
                        guard s > 0, s.magnitude >= threshold else { return }
                        action(s.magnitude, .changed)
                    }
                    .onEnded { _ in action(0, .ended) }
            )
            .background(ScrollMonitor(direction: direction, threshold: threshold, action: action))
    }
}

struct ScrollPanUpdate {
    let translation: CGFloat
    let phase: NSEvent.Phase
}

/// A scroll sequence belongs to the region where it started. Inertia never
/// starts a notch gesture, including after the pointer moves out of a list.
struct ScrollPanState {
    let direction: PanDirection
    let threshold: CGFloat
    private(set) var isTracking = false
    private var startsInside = false
    private var accumulated: CGFloat = 0
    private var active = false

    mutating func finish() -> ScrollPanUpdate? {
        let update = active ? ScrollPanUpdate(translation: 0, phase: .ended) : nil
        isTracking = false
        startsInside = false
        accumulated = 0
        active = false
        return update
    }

    mutating func update(
        deltaX: CGFloat,
        deltaY: CGFloat,
        precise: Bool,
        phase: NSEvent.Phase,
        momentumPhase: NSEvent.Phase,
        insideRegion: Bool
    ) -> [ScrollPanUpdate] {
        var updates: [ScrollPanUpdate] = []
        if !momentumPhase.isEmpty {
            if let end = finish() { updates.append(end) }
            return updates
        }
        if phase.contains(.began) {
            if let end = finish() { updates.append(end) }
        }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            if let end = finish() { updates.append(end) }
            return updates
        }
        if !isTracking {
            isTracking = true
            startsInside = insideRegion
        }
        guard startsInside else { return updates }

        let absDX = abs(deltaX)
        let absDY = abs(deltaY)
        let axisDominant = direction.isHorizontal
            ? absDX >= 1.5 * absDY
            : absDY >= 1.5 * absDX
        guard axisDominant else { return updates }

        let delta = direction.signed(deltaX: deltaX, deltaY: deltaY) * (precise ? 1 : 8)
        guard delta.magnitude > 0.2 else { return updates }
        accumulated = delta > 0 ? accumulated + delta : 0
        if !active && accumulated >= threshold {
            active = true
            updates.append(ScrollPanUpdate(translation: accumulated, phase: .began))
        } else if active {
            updates.append(ScrollPanUpdate(translation: accumulated, phase: .changed))
        }
        return updates
    }
}

private struct ScrollMonitor: NSViewRepresentable {
    let direction: PanDirection
    let threshold: CGFloat
    let action: (CGFloat, NSEvent.Phase) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.removeMonitor() }

    func makeCoordinator() -> Coordinator { 
        Coordinator(direction: direction, threshold: threshold, action: action) 
    }

    @MainActor final class Coordinator: NSObject {
        private let action: (CGFloat, NSEvent.Phase) -> Void
        private var monitor: Any?
        private var state: ScrollPanState
        private var endTask: Task<Void, Never>?

        init(direction: PanDirection, threshold: CGFloat, action: @escaping (CGFloat, NSEvent.Phase) -> Void) {
            self.state = ScrollPanState(direction: direction, threshold: threshold)
            self.action = action
        }

        private func scheduleEndTimeout() {
            // Cancel any existing scheduled end and schedule a new one.
            endTask?.cancel()
            endTask = Task { @MainActor in
                // Mouse wheels have no phases; end their sequence after a quiet interval.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if let end = state.finish() {
                    action(end.translation, end.phase)
                }
            }
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self, weak view] event in
                guard let self, let view, let window = view.window,
                      event.window === window else { return event }
                self.handleScroll(event, on: view)
                return event
            }
        }

        func removeMonitor() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            _ = state.finish()
            endTask?.cancel()
            endTask = nil
        }

        private func handleScroll(_ event: NSEvent, on view: NSView) {
            endTask?.cancel()
            endTask = nil
            let location = view.convert(event.locationInWindow, from: nil)
            let updates = state.update(
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY,
                precise: event.hasPreciseScrollingDeltas,
                phase: event.phase,
                momentumPhase: event.momentumPhase,
                insideRegion: view.bounds.contains(location)
            )
            for update in updates {
                action(update.translation, update.phase)
            }
            if event.phase.isEmpty && event.momentumPhase.isEmpty && state.isTracking {
                scheduleEndTimeout()
            }
        }
    }
}
