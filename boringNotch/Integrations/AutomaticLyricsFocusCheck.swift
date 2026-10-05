/// One automatic decision per notch opening, after the selected day's events load.
struct AutomaticLyricsFocusCheck {
    private(set) var isPending = false

    mutating func begin(enabled: Bool) {
        isPending = enabled
    }

    mutating func cancel() {
        isPending = false
    }

    mutating func consumeIfReady(isOpen: Bool, isHome: Bool, isViewingToday: Bool,
                                hasLoadedSelectedDay: Bool, hasVisibleEvents: Bool,
                                canFocus: Bool) -> Bool {
        guard isPending, isOpen, isHome else { return false }
        // Navigating away is user intent; returning to today must not re-arm the check.
        guard isViewingToday else {
            cancel()
            return false
        }
        guard hasLoadedSelectedDay else { return false }
        cancel()
        return !hasVisibleEvents && canFocus
    }
}
