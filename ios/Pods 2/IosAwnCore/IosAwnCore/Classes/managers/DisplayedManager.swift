//
//  DisplayedManager.swift
//  awesome_notifications
//
//  Displayed by Rafael Setragni on 15/09/20.
//

import Foundation

public class DisplayedManager : EventManager {
    
    let storage:SharedManager = SharedManager(tag: Definitions.SHARED_DISPLAYED)
    
    
    // **************************** SINGLETON PATTERN *************************************
    
    static var instance:DisplayedManager?
    public static var shared:DisplayedManager {
        get {
            DisplayedManager.instance =
            DisplayedManager.instance ?? DisplayedManager()
            return DisplayedManager.instance!
        }
    }
    private override init(){}
    
    // **************************** SINGLETON PATTERN *************************************
    
    
    public func saveDisplayed(received:NotificationReceived) -> Bool {
        guard let id: Int = received.id
        else { return false }
        if received.displayedDate == nil {
            received.displayedDate = RealDateTime.init(
                fromTimeZone: TimeZone(identifier: "UTC")
            )
            received.displayedLifeCycle = LifeCycleManager
                .shared
                .currentLifeCycle
        }
        guard let displayedDate: RealDateTime = received.displayedDate
        else { return false }
        
        storage.set(
            received.toMap(),
            referenceKey: getKeyByIdAndDate(
                id: id,
                referenceDate: displayedDate
            )
        )
        return true
    }

    public func listDisplayed() -> [NotificationReceived] {
        var returnedList:[NotificationReceived] = []
        let dataList = storage.getAllObjects()
        
        for data in dataList {
            guard let received = NotificationReceived(fromMap: data)
            else { continue }
            returnedList.append(received)
        }
        
        return returnedList
    }
    
    public func getDisplayedByKey(id:Int) -> [NotificationReceived] {
        var returnedList:[NotificationReceived] = []
        let dataList = storage.getAllObjectsStarting(with: getKeyById(id: id))
        
        for data in dataList {
            guard let received = NotificationReceived(fromMap: data)
            else { continue }
            if received.id != id { continue }
            returnedList.append(received)
        }
        
        return returnedList
    }
    
    public func getDisplayedByKeyAndDate(id:Int, displayedDate:RealDateTime) -> NotificationReceived? {
        guard let data:[String:Any?] = storage.get(
            referenceKey: getKeyByIdAndDate(
                id: id,
                referenceDate: displayedDate
            )
        ) else {
          return nil
        }
        return NotificationReceived(fromMap: data)
    }
    
    public func clearDisplayed(id:Int, displayedDate:RealDateTime) -> Bool {
        return storage.remove(
            referenceKey: getKeyByIdAndDate(
                id: id,
                referenceDate: displayedDate
            )
        )
    }
    
    public func reloadLostSchedulesDisplayed(
        schedules:[NotificationModel],
        lastDisplayedDate startingDate:RealDateTime,
        untilDate limitDate:RealDateTime
    ){
        let lastLifeCycle:NotificationLifeCycle =
                LifeCycleManager
                    .shared
                    .hasGoneForeground
                        ? .Background
                        : .AppKilled
        
        for notificationScheduled in schedules {
            guard let schedule:NotificationScheduleModel = notificationScheduled.schedule
            else { continue }
            
            let displayedDates:[RealDateTime] = getNextValidDates(
                fromScheduleModel: schedule,
                startingfromDate: startingDate,
                untilDate: limitDate)
            
            for displayedDate in displayedDates {
                let receivedNotification = NotificationReceived(notificationScheduled.content)
                receivedNotification.registerDisplayedEvent(
                    withDisplayedDate: displayedDate,
                    withLifeCycle: displayedDate == limitDate
                        ? .Foreground
                        : lastLifeCycle
                )
                _ = saveDisplayed(received: receivedNotification)
            }
        }
    }
    
    public func removeDisplayed(id:Int, displayedDate:RealDateTime) -> Bool {
        return clearDisplayed(id: id, displayedDate: displayedDate)
    }

    public func removeAllDisplayed() {
        storage.removeAll()
    }
    
    public func commit() {
        
    }
    
    private func getNextValidDates(
        fromScheduleModel scheduleModel: NotificationScheduleModel,
        startingfromDate referenceDate: RealDateTime,
        untilDate limitDate: RealDateTime
    ) -> [RealDateTime] {
        var currentValidDate = referenceDate
        var displayedDates:[RealDateTime] = []
        repeat {
            guard let nextValidDate =
                    scheduleModel
                        .getNextValidDate(
                            referenceDate: currentValidDate)
            else { break }
            
            if nextValidDate <= limitDate && nextValidDate >= currentValidDate {
                displayedDates.insert(nextValidDate, at: 0)
            }
            
            print("displayed recovered: \(nextValidDate)")
            
            if !scheduleModel.isRepeated() { break }
            if currentValidDate == nextValidDate { break }
            
            currentValidDate = nextValidDate
        } while currentValidDate < limitDate
        
        return displayedDates
    }
}
