import Defaults
import Foundation

@main struct CalendarFocusTests {
    @MainActor static func main() async {
        defer { Defaults.reset(.calendarSelectionState) }
        testFocusDecision()
        await testCalendarLoading()
        print("Passed 12 automatic-focus scenarios and 8 calendar loading/race checks.")
    }

    static func decide(_ check: inout AutomaticLyricsFocusCheck, loaded: Bool = true,
                       today: Bool = true, events: Bool = false, lyrics: Bool = true,
                       open: Bool = true, home: Bool = true) -> Bool {
        check.consumeIfReady(isOpen: open, isHome: home, isViewingToday: today,
            hasLoadedSelectedDay: loaded, hasVisibleEvents: events, canFocus: lyrics)
    }

    static func testFocusDecision() {
        var check = AutomaticLyricsFocusCheck()
        check.begin(enabled: false)
        precondition(!decide(&check), "Disabled setting must never enter focus")
        check.begin(enabled: true)
        precondition(!decide(&check, loaded: false) && check.isPending, "Initial empty array is not loaded")
        precondition(decide(&check), "Loaded empty today should enter focus")
        precondition(!decide(&check), "Manual exit followed by refresh must not re-enter")
        precondition(!decide(&check, today: false) && !decide(&check), "Browsing away and back cannot re-enter")
        check.begin(enabled: true)
        precondition(!decide(&check, events: true) && !check.isPending, "Nonempty result also consumes the decision")
        precondition(!decide(&check), "Removing events later must not enter focus")
        check.begin(enabled: true)
        precondition(!decide(&check, lyrics: false) && !decide(&check), "Late lyrics cannot restart a consumed decision")
        check.begin(enabled: true)
        precondition(!decide(&check, today: false) && !check.isPending && !decide(&check),
                     "Navigation while loading cancels the decision even if today later loads")
        check.begin(enabled: true)
        precondition(!decide(&check, open: false) && !decide(&check, home: false), "Only open Home can enter focus")
        check.cancel()
        precondition(!decide(&check), "Closing, leaving Home or manually choosing a mode cancels pending work")
        check.begin(enabled: true)
        precondition(decide(&check), "Reopening with a cached empty result needs no events change notification")
    }

    @MainActor static func waitUntil(_ condition: () async -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !(await condition()) {
            precondition(Date() < deadline, "Timed out waiting for test fixture")
            await Task.yield()
        }
    }

    @MainActor static func testCalendarLoading() async {
        Defaults[.calendarSelectionState] = .all
        let service = DeferredCalendarService()
        let manager = CalendarManager(calendarService: service)
        let today = Calendar.current.startOfDay(for: Date())
        precondition(manager.selectedDay == today && !manager.hasLoadedSelectedDay)
        await waitUntil { await service.lists.count == 1 }
        await manager.loadSelectedDayIfNeeded()
        let initialRequests = await service.requests.count
        precondition(initialRequests == 0, "Wait for selected calendar lists before fetching events")
        await service.finishLists()
        await waitUntil { await service.requests.count == 1 }
        precondition(!manager.hasLoadedSelectedDay && manager.events.isEmpty, "Do not expose initial empty as loaded")
        await service.finishRequest(events: [EventModel(id: "today")])
        await waitUntil { manager.hasLoadedSelectedDay }
        precondition(manager.events == [EventModel(id: "today")])

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let nextDay = Calendar.current.date(byAdding: .day, value: 2, to: today)!
        let old = Task { await manager.updateCurrentDate(tomorrow) }
        await waitUntil { await service.requests.count == 1 }
        precondition(manager.loadedDay == nil && manager.events.isEmpty, "New date invalidates old data synchronously")
        let new = Task { await manager.updateCurrentDate(nextDay) }
        await waitUntil { await service.requests.count == 2 }
        await service.finishRequest(1, events: [EventModel(id: "new")])
        await new.value
        await service.finishRequest(events: [EventModel(id: "old")])
        await old.value
        precondition(manager.selectedDay == nextDay && manager.loadedDay == nextDay
            && manager.events == [EventModel(id: "new")], "Late old-date reply must not overwrite selected date")

        let oldRefresh = Task { await manager.reloadCalendarAndReminderLists() }
        await waitUntil { await service.lists.count == 1 }
        precondition(!manager.hasLoadedSelectedDay, "Store/permission refresh invalidates readiness")
        await service.finishLists()
        await waitUntil { await service.requests.count == 1 }
        let newRefresh = Task { await manager.updateCurrentDate(nextDay) }
        await waitUntil { await service.requests.count == 2 }
        await service.finishRequest(1, events: [])
        await newRefresh.value
        await service.finishRequest(events: [EventModel(id: "stale")])
        await oldRefresh.value
        precondition(manager.hasLoadedSelectedDay && manager.events.isEmpty, "Latest same-day query owns the result")

        let cancelled = Task { await manager.updateCurrentDate(nextDay) }
        await waitUntil { await service.requests.count == 1 }
        cancelled.cancel()
        await service.finishRequest(events: [EventModel(id: "cancelled")])
        await cancelled.value
        precondition(manager.loadedDay == nil && manager.events.isEmpty, "Cancelled view load must not publish readiness")

        manager.resetToToday()
        precondition(manager.selectedDay == today && !manager.hasLoadedSelectedDay)
        let reopened = Task { await manager.loadSelectedDayIfNeeded() }
        await waitUntil { await service.requests.count == 1 }
        let requestedDay = await service.requests[0].day
        precondition(requestedDay == today, "Reopening must query today")
        await service.finishRequest(events: [])
        await reopened.value
        await manager.loadSelectedDayIfNeeded()
        let cachedRequests = await service.requests.count
        precondition(manager.hasLoadedSelectedDay && cachedRequests == 0, "Loaded empty cache needs no additional query")
    }
}
