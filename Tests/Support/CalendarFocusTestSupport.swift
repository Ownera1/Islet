import Defaults
import EventKit
import Foundation

// Only the platform-facing types are fixtures; tests compile the real CalendarManager.
struct CalendarModel {
    let id: String
    var isReminder = false
}

struct EventModel: Equatable {
    let id: String
}

enum CalendarSelectionState: Codable, Defaults.Serializable {
    case all
    case selected(Set<String>)
}

extension Defaults.Keys {
    static let calendarSelectionState = Key<CalendarSelectionState>("selection", default: .all,
        suite: UserDefaults(suiteName: "com.ownera1.islet.calendar-focus-tests")!)
}

class CalendarService: CalendarServiceProviding {
    func requestAccess(to type: EKEntityType) async throws -> Bool { true }
    func calendars() async -> [CalendarModel] { [] }
    func events(from start: Date, to end: Date, calendars: [String]) async -> [EventModel] { [] }
    func setReminderCompleted(reminderID: String, completed: Bool) async {}
}

actor DeferredCalendarService: CalendarServiceProviding {
    struct Request {
        let day: Date
        let calendars: [String]
        let reply: CheckedContinuation<[EventModel], Never>
    }

    var lists: [CheckedContinuation<[CalendarModel], Never>] = []
    var requests: [Request] = []
    func requestAccess(to type: EKEntityType) async throws -> Bool { true }
    func calendars() async -> [CalendarModel] {
        await withCheckedContinuation { lists.append($0) }
    }
    func events(from start: Date, to end: Date, calendars: [String]) async -> [EventModel] {
        await withCheckedContinuation { requests.append(Request(day: start, calendars: calendars, reply: $0)) }
    }
    func setReminderCompleted(reminderID: String, completed: Bool) async {}
    func finishLists(_ calendars: [CalendarModel] = [CalendarModel(id: "work")]) {
        lists.removeFirst().resume(returning: calendars)
    }
    func finishRequest(_ index: Int = 0, events: [EventModel]) {
        requests.remove(at: index).reply.resume(returning: events)
    }
}
