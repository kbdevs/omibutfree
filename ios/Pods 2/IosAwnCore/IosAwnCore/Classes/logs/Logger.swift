//
//  Logger.shared.swift
//  awesome_notifications
//
//  Created by CardaDev on 01/04/22.
//

import Foundation
import os.log

public class Logger {
    public static let shared = LoggerImpl()
    private init() {}
}

// Define the Logger protocol
public protocol LoggerProtocol {
    func d(_ className: String, _ message: String, line: Int)
    func e(_ className: String, _ message: String, line: Int)
    func i(_ className: String, _ message: String, line: Int)
    func w(_ className: String, _ message: String, line: Int)
}

// Implement the Logger protocol in LoggerImpl class
public class LoggerImpl: LoggerProtocol {
    
    public func d(_ className: String, _ message: String, line: Int = #line) {
        os_log("D/Swift: \u{001B}[32m[AWESOME NOTIFICATIONS]\u{001B}[0m %@ (%@:%d)", type: .debug, message, className, line)
    }

    public func e(_ className: String, _ message: String, line: Int = #line) {
        os_log("E/Swift: \u{001B}[31m[AWESOME NOTIFICATIONS] %@ (%@:%d)\u{001B}[0m", type: .error, message, className, line)
    }

    public func i(_ className: String, _ message: String, line: Int = #line) {
        os_log("I/Swift: \u{001B}[94m[AWESOME NOTIFICATIONS] %@ (%@:%d)\u{001B}[0m", type: .info, message, className, line)
    }

    public func w(_ className: String, _ message: String, line: Int = #line) {
        os_log("W/Swift: \u{001B}[33m[AWESOME NOTIFICATIONS] %@ (%@:%d)\u{001B}[0m", type: .fault, message, className, line)
    }
}
