import Foundation
import BackgroundTasks

/// Schedules a periodic metering check-in via BGAppRefreshTask. This is the
/// control-plane channel only (MAU accounting) - it is completely separate from
/// the k-anon lookup path and never affects lookup latency.
///
/// Setup in AppDelegate:
/// ```swift
/// func application(_ application: UIApplication,
///                  didFinishLaunchingWithOptions ...) -> Bool {
///     CallerAPI.configure(featureEnabled: true)
///     CallerAPI.BackgroundSync.register()
///     return true
/// }
/// ```
///
/// Also add to Info.plist → BGTaskSchedulerPermittedIdentifiers:
///   "com.callerapi.checkin"
@available(iOS 13.0, *)
public extension CallerAPI {

    enum BackgroundSync {

        public static let taskIdentifier = "com.callerapi.checkin"

        /// Register the background task with the system. Call once at launch.
        public static func register() {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: taskIdentifier,
                using: nil
            ) { task in
                handleTask(task as! BGAppRefreshTask)
            }
            scheduleNext()
        }

        // MARK: - Internal

        private static func handleTask(_ task: BGAppRefreshTask) {
            let work = Task {
                if CallerAPI.isEntitled() {
                    _ = await CallerAPI.checkIn()
                }
            }

            task.expirationHandler = { work.cancel() }

            Task {
                _ = await work.result
                task.setTaskCompleted(success: true)
                scheduleNext()
            }
        }

        private static func scheduleNext() {
            let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
            request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 3600)
            try? BGTaskScheduler.shared.submit(request)
        }
    }
}
