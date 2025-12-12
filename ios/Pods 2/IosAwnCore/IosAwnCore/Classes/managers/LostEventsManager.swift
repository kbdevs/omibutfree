//
//  LostEventsManager.swift
//  IosAwnCore
//
//  Created by Rafael Setragni on 21/03/23.
//

import Foundation


public class EventRegister: Comparable {
    let eventName:String
    let eventDate:RealDateTime
    let notificationContent:NotificationReceived
    
    init(
        eventName:String,
        eventDate:RealDateTime,
        notificationContent:NotificationReceived
    ){
        self.eventName = eventName
        self.eventDate = eventDate
        self.notificationContent = notificationContent
    }
    
    public static func == (lhs: EventRegister, rhs: EventRegister) -> Bool {
        return lhs.eventDate == rhs.eventDate
    }
    
    public static func < (lhs: EventRegister, rhs: EventRegister) -> Bool {
        return lhs.eventDate < rhs.eventDate
    }
}

public class LostEventsManager {
    private let TAG:String = "LostEventsManager"
    
    // ************** SINGLETON PATTERN ***********************
    
    static var instance:LostEventsManager?
    public static var shared:LostEventsManager {
        get {
            LostEventsManager.instance =
            LostEventsManager.instance ?? LostEventsManager()
            return LostEventsManager.instance!
        }
    }
    private init(){}
    
    // ********************************************************
    
    private let timeoutLockedProcess:TimeInterval = 3
    private let recoverLostEventsLock = NSLock()
    public func recoverLostNotificationEvents(
        withReferenceLifeCycle:NotificationLifeCycle,
        createdHandle:Int64,
        displayedHandle:Int64,
        actionHandle:Int64,
        dismissedHandle:Int64
    ) throws -> [EventRegister] {
        var lostEvents:[EventRegister] = []
        if actionHandle == 0 { return lostEvents }
        
        let locked = recoverLostEventsLock.lock(
            before: Date().addingTimeInterval(timeoutLockedProcess)
        )
        defer { if locked { recoverLostEventsLock.unlock() } }
        
        lostEvents += try recoverLostCreatedEvents(
            hasHandleRegistered: createdHandle != 0
        )
        
        lostEvents += try recoverLostDisplayedEvents(
            hasHandleRegistered: displayedHandle != 0,
            withReferenceLifeCycle: withReferenceLifeCycle
        )
        
        lostEvents += try recoverLostDismissedEvents(
            hasHandleRegistered: dismissedHandle != 0
        )
        
        lostEvents += try recoverLostActionEvents(
            hasHandleRegistered: actionHandle != 0
        )
        
        return lostEvents.sorted()
    }
    
    private func recoverLostCreatedEvents(
        hasHandleRegistered: Bool
    ) throws -> [EventRegister] {
        var lostEvents:[EventRegister] = []
        
        if hasHandleRegistered {
            let lostCreated = CreatedManager
                .shared
                .listCreated()
            
            for createdNotification in lostCreated {
                do {
                    try createdNotification.validate()
                    if (createdNotification.createdDate == nil){
                        _ = createdNotification.registerCreateEvent(
                            withLifeCycle: createdNotification.createdLifeCycle ?? .Terminated,
                            fromSource: createdNotification.createdSource ?? .Local
                        )
                    }
                    guard let id:Int = createdNotification.id
                    else { continue }
                    let createdDate:RealDateTime = createdNotification.createdDate ?? RealDateTime.init(
                        fromTimeZone: TimeZone(identifier: "UTC")
                    )
                    
                    lostEvents.append(EventRegister(
                        eventName: Definitions.EVENT_NOTIFICATION_CREATED,
                        eventDate: createdDate,
                        notificationContent: createdNotification
                    ))
                    
                    if !CreatedManager
                        .shared
                        .removeCreated(
                            id: id,
                            createdDate: createdDate)
                    {
                        Logger.shared.e(TAG, "Created event \(createdNotification.id!) could not be cleaned")
                    }
                    
                } catch {
                    Logger.shared.e(TAG, "Created event \(String(describing: createdNotification.id)) failed to recover: \(error)")
                }
            }
        }
        
        CreatedManager
            .shared
            .removeAllCreated()
        
        CreatedManager
            .shared
            .commit()
        
        return lostEvents
    }
        
    private func recoverLostDisplayedEvents(
        hasHandleRegistered: Bool,
        withReferenceLifeCycle referenceLifeCycle:NotificationLifeCycle
    ) throws -> [EventRegister] {
        var lostEvents:[EventRegister] = []
        
        if hasHandleRegistered {
            let currentSchedules:[NotificationModel] = ScheduleManager
                .shared
                .listSchedules()
            
            let lastDisplayedDate:RealDateTime =
                            DefaultsManager
                                .shared
                                .lastDisplayedDate
            
            let currentDate = RealDateTime()
            
            DisplayedManager
                .shared
                .reloadLostSchedulesDisplayed(
                    schedules: currentSchedules,
                    lastDisplayedDate: lastDisplayedDate,
                    untilDate: currentDate)
            
            let lostDisplayed = DisplayedManager.shared.listDisplayed()
            for displayedNotification in lostDisplayed {
                
                guard let id:Int = displayedNotification.id
                else { continue }
                let displayedDate:RealDateTime =
                        displayedNotification.displayedDate ?? RealDateTime.init(
                            fromTimeZone: TimeZone(identifier: "UTC")
                        )
                displayedNotification.displayedDate = displayedDate
                
                if currentDate >= displayedDate && lastDisplayedDate <= displayedDate {
                    do {
                        try displayedNotification.validate()
                        
                        lostEvents.append(EventRegister(
                            eventName: Definitions.EVENT_NOTIFICATION_DISPLAYED,
                            eventDate: displayedDate,
                            notificationContent: displayedNotification
                        ))
                    } catch {
                        Logger.shared.e(TAG, "Displayed event \(String(describing: displayedNotification.id)) failed to recover: \(error)")
                    }
                }
                
                if !DisplayedManager
                    .shared
                    .removeDisplayed(
                        id: id,
                        displayedDate: displayedDate)
                {
                    Logger.shared.e(TAG, "Displayed event \(displayedNotification.id ?? -1) could not be cleaned")
                }
            }
            
            DefaultsManager
                .shared
                .registerLastDisplayedDate()
            
            ScheduleManager
                .shared
                .syncAllPendingSchedules { _ in
                    
                }
        }
        
        DisplayedManager
            .shared
            .removeAllDisplayed()
        
        DisplayedManager
            .shared
            .commit()
        
        return lostEvents
    }
    
    private func recoverLostDismissedEvents(
        hasHandleRegistered: Bool
    ) throws -> [EventRegister] {
        var lostEvents:[EventRegister] = []
        
        if hasHandleRegistered {
            let lostDismissed = DismissedManager
                .shared
                .listDismissed()
            
            for dismissedNotification in lostDismissed {
                let dismissedDate:RealDateTime =
                        dismissedNotification.dismissedDate ?? RealDateTime.init(
                            fromTimeZone: TimeZone(identifier: "UTC")
                        )
                dismissedNotification.dismissedDate = dismissedDate
                do {
                    try dismissedNotification.validate()
                    
                    lostEvents.append(EventRegister(
                        eventName: Definitions.EVENT_NOTIFICATION_DISMISSED,
                        eventDate: dismissedDate,
                        notificationContent: dismissedNotification
                    ))
                    
                } catch {
                    Logger.shared.e(TAG, "Dismissed event \(String(describing: dismissedNotification.id)) failed to recover: \(error)")
                }
                
                if !DismissedManager
                    .shared
                    .removeDismissed(id: dismissedNotification.id!)
                {
                    Logger.shared.e(TAG, "Dismissed event \(dismissedNotification.id!) could not be cleaned")
                }
            }
        }
        
        DismissedManager
            .shared
            .removeAllDismissed()
        
        DismissedManager
            .shared
            .commit()
        
        return lostEvents
    }
    
    private func recoverLostActionEvents(
        hasHandleRegistered: Bool
    ) throws -> [EventRegister] {
        var lostEvents:[EventRegister] = []
        
        if hasHandleRegistered {
            let lostActions = ActionManager
                .shared
                .recoverActions()
            
            for notificationAction in lostActions {
                let actionDate:RealDateTime =
                notificationAction.actionDate ?? RealDateTime.init(
                            fromTimeZone: TimeZone(identifier: "UTC")
                        )
                notificationAction.actionDate = actionDate
                do {
                    try notificationAction.validate()
                    
                    lostEvents.append(EventRegister(
                        eventName: Definitions.EVENT_DEFAULT_ACTION,
                        eventDate: actionDate,
                        notificationContent: notificationAction
                    ))
                    
                } catch {
                    Logger.shared.e(TAG, "Action event \(String(describing: notificationAction.id)) failed to recover: \(error)")
                }
                
                if !ActionManager.shared.removeAction(id: notificationAction.id!) {
                    Logger.shared.e(TAG, "Action event \(notificationAction.id!) could not be cleaned")
                }
            }
        }
        
        ActionManager
            .shared
            .removeAllActions()
        
        ActionManager
            .shared
            .commit()
        
        return lostEvents
    }
}
