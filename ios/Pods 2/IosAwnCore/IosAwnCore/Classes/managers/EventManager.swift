//
//  EventManager.swift
//  IosAwnCore
//
//  Created by Rafael Setragni on 03/03/23.
//

import Foundation

public class EventManager {
    
    public func getKeyByIdAndDate(id: Int, referenceDate: RealDateTime) -> String {
        return "\(getKeyById(id: id))-\(getKeyByCalendar(referenceDate: referenceDate))"
    }
    
    public func getKeyById(id: Int) -> String {
        return String(format: "%010d", id)
    }
    
    public func getKeyByCalendar(referenceDate: RealDateTime) -> String {
        let unixTimestamp = referenceDate.date.secondsSince1970
        return String(format: "%010d", Int(unixTimestamp))
    }
}
