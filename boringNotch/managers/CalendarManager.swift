//
//  CalendarManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import Defaults
import EventKit
import SwiftUI

protocol CalendarServiceProviding {
    func requestAccess(to type: EKEntityType) async throws -> Bool
    func calendars() async -> [CalendarModel]
    func events(from start: Date, to end: Date, calendars: [String]) async -> [EventModel]
    func setReminderCompleted(reminderID: String, completed: Bool) async
}

// MARK: - CalendarManager

@MainActor
class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    @Published private(set) var selectedDay: Date
    @Published private(set) var events: [EventModel] = []
    @Published private(set) var loadedDay: Date?
    var hasLoadedSelectedDay: Bool { loadedDay == selectedDay }
    @Published var allCalendars: [CalendarModel] = []
    @Published var eventCalendars: [CalendarModel] = []
    @Published var reminderLists: [CalendarModel] = []
    @Published var selectedCalendarIDs: Set<String> = []
    @Published var calendarAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var reminderAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    private var selectedCalendars: [CalendarModel] = []
    private let calendarService: any CalendarServiceProviding
    private var eventsRequestID = UUID()
    private var calendarListsRequestID = UUID()
    private var calendarListsReady = false

    private var eventStoreChangedObserver: NSObjectProtocol?

    init(calendarService: any CalendarServiceProviding = CalendarService()) {
        self.calendarService = calendarService
        self.selectedDay = CalendarManager.startOfDay(Date())
        setupEventStoreChangedObserver()
        Task {
            await reloadCalendarAndReminderLists()
        }
    }

    deinit {
        if let observer = eventStoreChangedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupEventStoreChangedObserver() {
        eventStoreChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.reloadCalendarAndReminderLists()
            }
        }
    }

    @MainActor
    func reloadCalendarAndReminderLists() async {
        let requestID = UUID()
        calendarListsRequestID = requestID
        calendarListsReady = false
        eventsRequestID = UUID()
        loadedDay = nil
        let all = await calendarService.calendars()
        guard calendarListsRequestID == requestID else { return }
        self.eventCalendars = all.filter { !$0.isReminder }
        self.reminderLists = all.filter { $0.isReminder }
        self.allCalendars = all // for legacy compatibility, can be removed if not needed
        updateSelectedCalendars()
        calendarListsReady = true
        await updateEvents()
    }

    func checkCalendarAuthorization() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        self.calendarAuthorizationStatus = status

        switch status {
        case .notDetermined:
            guard let granted = try? await calendarService.requestAccess(to: .event) else {
                self.calendarAuthorizationStatus = .notDetermined
                return
            }
            self.calendarAuthorizationStatus = granted ? .fullAccess : .denied
            if granted {
                await reloadCalendarAndReminderLists()
            }
        case .restricted, .denied:
            NSLog("Calendar access denied or restricted")
            await reloadCalendarAndReminderLists()
        case .fullAccess:
            NSLog("Full access")
            await reloadCalendarAndReminderLists()
        case .writeOnly:
            NSLog("Write only")
        @unknown default:
            print("Unknown authorization status")
        }
    }
    
    func checkReminderAuthorization() async {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        DispatchQueue.main.async {
            print("📅 Current reminder authorization status: \(status)")
            self.reminderAuthorizationStatus = status
        }

        switch status {
        case .notDetermined:
            guard let granted = try? await calendarService.requestAccess(to: .reminder) else {
                self.reminderAuthorizationStatus = .notDetermined
                return
            }
            self.reminderAuthorizationStatus = granted ? .fullAccess : .denied
            if granted {
                await reloadCalendarAndReminderLists()
            }
        case .restricted, .denied:
            NSLog("Reminder access denied or restricted")
        case .fullAccess:
            NSLog("Full access")
            await reloadCalendarAndReminderLists()
        case .writeOnly:
            NSLog("Write only")
        @unknown default:
            print("Unknown authorization status")
        }
    }
        

    func updateSelectedCalendars() {
        // Populate selectedCalendarIDs based on Defaults calendar selection state
        switch Defaults[.calendarSelectionState] {
        case .all:
            selectedCalendarIDs = Set(allCalendars.map { $0.id })
        case .selected(let identifiers):
            selectedCalendarIDs = identifiers
        }

        // Update the local calendar objects that correspond to the selected ids
        selectedCalendars = allCalendars.filter { selectedCalendarIDs.contains($0.id) }
    }

    func getCalendarSelected(_ calendar: CalendarModel) -> Bool {
        return selectedCalendarIDs.contains(calendar.id)
    }

    func setCalendarSelected(_ calendar: CalendarModel, isSelected: Bool) async {
        var selectionState = Defaults[.calendarSelectionState]

        switch selectionState {
        case .all:
            if !isSelected {
                let identifiers = Set(allCalendars.map { $0.id }).subtracting([calendar.id])
                selectionState = .selected(identifiers)
            }

        case .selected(var identifiers):
            if isSelected {
                identifiers.insert(calendar.id)
            } else {
                identifiers.remove(calendar.id)
            }

            selectionState =
                identifiers.isEmpty
                ? .all : identifiers.count == allCalendars.count ? .all : .selected(identifiers)  // if empty, select all
        }

        Defaults[.calendarSelectionState] = selectionState
        updateSelectedCalendars()
        await updateEvents()
    }

    static func startOfDay(_ date: Date) -> Date {
        return Calendar.current.startOfDay(for: date)
    }

    func updateCurrentDate(_ date: Date) async {
        selectDay(date)
        await updateEvents()
    }

    func selectDay(_ date: Date) {
        let day = Self.startOfDay(date)
        guard selectedDay != day else { return }
        eventsRequestID = UUID()
        loadedDay = nil
        events = []
        selectedDay = day
    }

    func resetToToday() {
        selectDay(Date())
    }

    func loadSelectedDayIfNeeded() async {
        guard !hasLoadedSelectedDay else { return }
        await updateEvents()
    }

    private func updateEvents() async {
        guard calendarListsReady else { return }
        let requestID = UUID()
        eventsRequestID = requestID
        let day = selectedDay
        let calendarIDs = selectedCalendars.map { $0.id }
        loadedDay = nil
        let eventsResult = await calendarService.events(
            from: day,
            to: Calendar.current.date(byAdding: .day, value: 1, to: day)!,
            calendars: calendarIDs
        )
        guard !Task.isCancelled, eventsRequestID == requestID, selectedDay == day,
              selectedCalendars.map({ $0.id }) == calendarIDs else { return }
        self.events = eventsResult
        loadedDay = day
    }
    
    func setReminderCompleted(reminderID: String, completed: Bool) async {
        await calendarService.setReminderCompleted(reminderID: reminderID, completed: completed)
        // Refresh events after updating
        await updateEvents()
    }
}
