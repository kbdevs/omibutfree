//
//  ActionManager.swift
//  awesome_notifications
//
//  Created by CardaDev on 31/01/22.
//

import Foundation

public class ActionManager : EventManager {
    static let TAG = "ActionManager"
    var recovered:Bool  = false
    
    // Cache is necessary due user preferences are not aways ready for return data
    // if the respective value is request too fast.
    var actionCache:[Int:ActionReceived] = [:]
    var initialAction:ActionReceived?
    var removeInitialActionFromCache:Bool = false
    
    // **************************** SINGLETON PATTERN *************************************
    
    static var instance:ActionManager?
    public static var shared:ActionManager {
        get {
            ActionManager.instance =
            ActionManager.instance ?? ActionManager()
            return ActionManager.instance!
        }
    }
    private override init(){}
    
    // **************************** SINGLETON PATTERN *************************************
    
    public func removeAction(id:Int) -> Bool {
        return actionCache.removeValue(forKey: id) != nil
    }

    public func recoverActions() -> [ActionReceived] {
        if recovered { return [] }
        recovered = true
        return Array(actionCache.values)
    }

    public func saveAction(received:ActionReceived) {
        if received.actionLifeCycle == .AppKilled {
            initialAction = received
            if removeInitialActionFromCache { return }
        }
        actionCache[received.id!] = received
    }

    public func getActionByKey(id:Int) -> ActionReceived? {
        return actionCache[id]
    }
    
    public func removeAllActions() {
        actionCache.removeAll()
    }
    
    public func getInitialAction(removeFromEvents:Bool) -> ActionReceived? {
        if initialAction == nil { return nil }
        if removeFromEvents {
            removeInitialActionFromCache = true
            _ = removeAction(id: initialAction!.id!)
        }
        return initialAction
    }

    //public static func removeAction(id:Int) {
    //    actionCache.removeValue(forKey: id)
    //}
    
    public func commit() {
        
    }
    
}
