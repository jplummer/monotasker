import Foundation
import os

/// In-memory `RemindersService` for unit tests and SwiftUI previews.
final class MockRemindersService: RemindersService, @unchecked Sendable {
  enum MockError: Error { case generic }

  private struct MutableState: @unchecked Sendable {
    var auth: RemindersAuthorization
    var calendars: [ReminderCalendarSummary]
    /// calendarId -> reminders
    var reminders: [String: [ReminderTask]]
    var changeContinuation: AsyncStream<Void>.Continuation?
    var nextReminderNumericId: Int
    /// When non-nil, `createReminderList` throws this error instead of succeeding.
    var createListError: Error? = nil
    /// Controls `requestFullAccess` outcome: nil = grant (default), false = deny, error = throw.
    var requestAccessResult: Bool? = nil
    var requestAccessError: Error? = nil
    var fetchCallCount: Int = 0
  }

  private let lock: OSAllocatedUnfairLock<MutableState>

  init(
    authorization: RemindersAuthorization = .fullAccess,
    calendars: [ReminderCalendarSummary] = [
      ReminderCalendarSummary(id: "cal-1", title: "Monotasker")
    ],
    reminders: [String: [ReminderTask]] = [:]
  ) {
    let remindersMap: [String: [ReminderTask]]
    if reminders.isEmpty {
      var map: [String: [ReminderTask]] = [:]
      for cal in calendars {
        map[cal.id] = []
      }
      remindersMap = map
    } else {
      remindersMap = reminders
    }
    let nextId = Self.nextReminderIdSeed(from: remindersMap)
    let initial = MutableState(
      auth: authorization,
      calendars: calendars,
      reminders: remindersMap,
      changeContinuation: nil,
      nextReminderNumericId: nextId
    )
    lock = OSAllocatedUnfairLock(initialState: initial)
  }

  /// Seed after max existing `r-N` id so new reminders never collide (e.g. `r-1` then `r-2`).
  private static func nextReminderIdSeed(from reminders: [String: [ReminderTask]]) -> Int {
    var maxNum = 0
    for list in reminders.values {
      for task in list {
        let parts = task.id.split(separator: "-")
        if parts.count >= 2, parts[0] == "r", let n = Int(parts[1]) {
          maxNum = max(maxNum, n)
        }
      }
    }
    return maxNum + 1
  }

  func setAuthorization(_ value: RemindersAuthorization) {
    lock.withLock { $0.auth = value }
  }

  func setCreateListError(_ error: Error?) {
    lock.withLock { $0.createListError = error }
  }

  func setRequestAccessResult(_ result: Bool?) {
    lock.withLock { $0.requestAccessResult = result }
  }

  func setRequestAccessError(_ error: Error?) {
    lock.withLock { $0.requestAccessError = error }
  }

  func currentAuthorization() -> RemindersAuthorization {
    lock.withLock { $0.auth }
  }

  func requestFullAccess() async throws -> Bool {
    let state = lock.withLock { $0 }
    if let error = state.requestAccessError { throw error }
    if let result = state.requestAccessResult {
      if result { lock.withLock { $0.auth = .fullAccess } }
      return result
    }
    lock.withLock { $0.auth = .fullAccess }
    return true
  }

  func reminderCalendars() -> [ReminderCalendarSummary] {
    lock.withLock { $0.calendars }
  }

  func calendar(withIdentifier id: String) -> ReminderCalendarSummary? {
    lock.withLock { $0.calendars.first { $0.id == id } }
  }

  func firstCalendar(named title: String) -> ReminderCalendarSummary? {
    lock.withLock { $0.calendars.first { $0.title == title } }
  }

  func createReminderList(title: String) throws -> ReminderCalendarSummary {
    let result = lock.withLock { state -> Result<ReminderCalendarSummary, Error> in
      if let error = state.createListError { return .failure(error) }
      let newId = "cal-mock-\(state.calendars.count + 1)"
      let created = ReminderCalendarSummary(id: newId, title: title)
      state.calendars.append(created)
      state.reminders[newId] = []
      return .success(created)
    }
    switch result {
    case .success(let summary):
      emitChange()
      return summary
    case .failure(let error):
      throw error
    }
  }

  var fetchCallCount: Int { lock.withLock { $0.fetchCallCount } }

  func fetchIncompleteTopLevel(calendarId: String) async throws -> [ReminderTask] {
    try lock.withLock { state in
      state.fetchCallCount += 1
      guard let list = state.reminders[calendarId] else {
        throw RemindersServiceError.calendarNotFound
      }
      return list.filter { !$0.isCompleted }
    }
  }

  func createReminder(title: String, notes: String?, calendarId: String) throws -> ReminderTask {
    let task = try lock.withLock { state -> ReminderTask in
      guard state.reminders[calendarId] != nil else {
        throw RemindersServiceError.calendarNotFound
      }
      let id = "r-\(state.nextReminderNumericId)"
      state.nextReminderNumericId += 1
      let created = ReminderTask(id: id, title: title, notes: notes, isCompleted: false)
      state.reminders[calendarId, default: []].append(created)
      return created
    }
    emitChange()
    return task
  }

  func updateReminder(id: String, title: String, notes: String?) throws {
    try lock.withLock { state in
      for key in state.reminders.keys {
        guard var list = state.reminders[key], let idx = list.firstIndex(where: { $0.id == id }) else { continue }
        list[idx].title = title
        list[idx].notes = notes
        state.reminders[key] = list
        return
      }
      throw RemindersServiceError.reminderNotFound
    }
    emitChange()
  }

  func completeReminder(id: String) throws {
    try lock.withLock { state in
      for key in state.reminders.keys {
        guard var list = state.reminders[key], let idx = list.firstIndex(where: { $0.id == id }) else { continue }
        list[idx].isCompleted = true
        state.reminders[key] = list
        return
      }
      throw RemindersServiceError.reminderNotFound
    }
    emitChange()
  }

  func deleteReminder(id: String) throws {
    try lock.withLock { state in
      for key in state.reminders.keys {
        guard var list = state.reminders[key], let idx = list.firstIndex(where: { $0.id == id }) else { continue }
        list.remove(at: idx)
        state.reminders[key] = list
        return
      }
      throw RemindersServiceError.reminderNotFound
    }
    emitChange()
  }

  func eventStoreChanges() -> AsyncStream<Void> {
    AsyncStream { continuation in
      self.lock.withLock { state in
        state.changeContinuation = continuation
      }
      continuation.onTermination = { [weak self] _ in
        self?.lock.withLock { state in
          state.changeContinuation = nil
        }
      }
    }
  }

  private func emitChange() {
    let continuation = lock.withLock { $0.changeContinuation }
    continuation?.yield()
  }
}
