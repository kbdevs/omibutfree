//
//  CreatedManager.swift
//  awesome_notifications
//
//  Created by Rafael Setragni on 15/09/20.
//

import Foundation

public class CreatedManager : EventManager {
    
    let storage:SharedManager = SharedManager(tag: Definitions.SHARED_CREATED)
    
    // **************************** SINGLETON PATTERN *************************************
    
    static var instance:CreatedManager?
    public static var shared:CreatedManager {
        get {
            CreatedManager.instance =
            CreatedManager.instance ?? CreatedManager()
            return CreatedManager.instance!
        }
    }
    private override init(){}
    
    // **************************** OBSERVER PATTERN **************************************
    

    
    public func saveCreated(
        received:NotificationReceived,
        lifeCycle: NotificationLifeCycle,
        source: NotificationSource
    ) -> Bool {
        guard let id: Int = received.id
        else { return false }
        if received.createdDate == nil {
            if !received.registerCreateEvent(
                withLifeCycle: lifeCycle,
                fromSource: source
            ) { return false }
        }
        guard let createdDate: RealDateTime = received.createdDate
        else { return false }
        
        storage.set(
            received.toMap(),
            referenceKey: getKeyByIdAndDate(
                id: id,
                referenceDate: createdDate
            )
        )
        return true
    }
    
    public func listCreated() -> [NotificationReceived] {
        var returnedList:[NotificationReceived] = []
        let dataList = storage.getAllObjects()
        
        for data in dataList {
            guard let received = NotificationReceived(fromMap: data)
            else { continue }
            if received.createdDate == nil {
                _ = received.registerCreateEvent(
                    withLifeCycle: .Terminated,
                    fromSource: .Local
                )
            }
            returnedList.append(received)
        }
        
        return returnedList
    }
    
    public func getCreatedByKey(id:Int) -> [NotificationReceived] {
        var returnedList:[NotificationReceived] = []
        let dataList = storage.getAllObjectsStarting(with: getKeyById(id: id))
        
        for data in dataList {
            guard let received = NotificationReceived(fromMap: data)
            else { continue }
            if received.id != id { continue }
            if received.createdDate == nil {
                _ = received.registerCreateEvent(
                    withLifeCycle: .Terminated,
                    fromSource: .Local
                )
            }
            returnedList.append(received)
        }
        
        return returnedList
    }
    
    public func getCreatedByKeyAndDate(id:Int, createdDate:RealDateTime) -> NotificationReceived? {
        return NotificationReceived(fromMap: storage.get(
            referenceKey: getKeyByIdAndDate(
                id: id,
                referenceDate: createdDate
            ))
        )
    }

    public func removeAllCreated() {
        storage.removeAll()
    }
    
    public func removeCreated(id:Int, createdDate:RealDateTime) -> Bool {
        return storage.remove(
            referenceKey: getKeyByIdAndDate(
                id: id,
                referenceDate: createdDate
            )
        )
    }
    
    public func commit() {
        
    }
    
}
