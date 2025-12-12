//
//  AbstractModel.swift
//  awesome_notifications
//
//  Created by Rafael Setragni on 05/09/20.
//

import Foundation

public protocol AbstractModel: AnyObject {
    
    func toMap() -> [String : Any?]

    func validate() throws
}
