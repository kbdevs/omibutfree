//
//  DismissedManager.swift
//  awesome_notifications
//
//  Dismissed by CardaDev on 31/01/22.
//

import Foundation

public class DismissedManager : EventManager {
    
    let sharedManager:SharedManager = SharedManager(tag: Definitions.SHARED_DISMISSED)
    
    // **************************** SINGLETON PATTERN *************************************
    
    static var instance:DismissedManager?
    public static var shared:DismissedManager {
        get {
            DismissedManager.instance =
            DismissedManager.instance ?? DismissedManager()
            return DismissedManager.instance!
        }
    }
    private override init(){}
    
    // **************************** SINGLETON PATTERN *************************************
    
    public func removeDismissed(id:Int) -> Bool {
        return sharedManager.remove(referenceKey: String(id));
    }

    public func listDismissed() -> [ActionReceived] {
        var returnedList:[ActionReceived] = []
        let dataList = sharedManager.getAllObjects()
        
        for data in dataList {
            guard let received = ActionReceived(fromMap: data)
            else { continue }
            returnedList.append(received)
        }
        
        return returnedList
    }

    public func saveDismissed(received:NotificationReceived) {
        sharedManager.set(received.toMap(), referenceKey: String(received.id!))
    }

    public func getDismissedByKey(id:Int) -> ActionReceived? {
        return ActionReceived(fromMap: sharedManager.get(referenceKey: String(id)))
    }

    public func removeAllDismissed() {
        sharedManager.removeAll()
    }

    public func cancelDismissed(id:Int) {
        _ = sharedManager.remove(referenceKey: String(id))
    }
    
    public func commit() {
        
    }
    
}
