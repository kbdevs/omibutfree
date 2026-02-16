import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

class NotificationService {
    func initialize() async {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        if granted == true {
            print("Notification permission granted")
        }
    }
    
    func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func showAiResponse(_ response: String) {
        showNotification(title: "Omi", body: response)
    }
    
    func scheduleTaskNotification(id: Int, title: String, dueDate: Date) async {
        let content = UNMutableNotificationContent()
        content.title = "Task Reminder"
        content.body = title
        content.sound = .default
        
        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: String(id),
            content: content,
            trigger: trigger
        )
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    func cancelTaskNotification(_ id: Int) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [String(id)])
    }
    
    func resetGlobalBadge() {
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0)
        } else {
            #if canImport(UIKit)
            UIApplication.shared.applicationIconBadgeNumber = 0
            #endif
        }
    }
}
