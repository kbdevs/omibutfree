//
//  NotificationIntervalModel.swift
//  awesome_notifications
//
//  Created by Rafael Setragni on 09/03/21.
//

import Foundation

public class NotificationIntervalModel : NotificationScheduleModel {
    
    static let TAG = "NotificationIntervalModel"
    
    var _createdDate:RealDateTime?
    var _timeZone:TimeZone?
    
    /// Initial reference date from schedule
    public var createdDate:RealDateTime? { get{
        return _createdDate
    } set(newValue){
        _createdDate = newValue
    }}
    
    /// Time zone reference date from schedule (abbreviation)
    public var timeZone:TimeZone? { get{
        return _timeZone
    } set(newValue){
        _timeZone = newValue
    }}
    
    /// Field number for get and set indicating the year.
    var interval:Int?
    /// Specify false to deliver the notification one time. Specify true to reschedule the notification request each time the notification is delivered.
    var repeats:Bool?
    
    public init(){}
    
    public convenience init?(fromMap arguments: [String : Any?]?){
        if arguments?.isEmpty ?? true { return nil }
        
        do {
            self.init()
            self._timeZone = MapUtils<TimeZone>.getValueOrDefault(reference: Definitions.NOTIFICATION_SCHEDULE_TIMEZONE, arguments: arguments)
            self.createdDate = MapUtils<RealDateTime>.getRealDateOrDefault(reference: Definitions.NOTIFICATION_SCHEDULE_INITIAL_DATE, arguments: arguments, defaultTimeZone: RealDateTime.utcTimeZone)
            self.interval = MapUtils<Int>.getValueOrDefault(reference: Definitions.NOTIFICATION_SCHEDULE_INTERVAL, arguments: arguments)
            self.repeats  = MapUtils<Bool>.getValueOrDefault(reference: Definitions.NOTIFICATION_SCHEDULE_REPEATS, arguments: arguments)
        }
        catch {
            Logger.shared.e(Self.TAG, error.localizedDescription)
            return nil
        }
    }
    
    public func toMap() -> [String : Any?] {
        var mapData:[String: Any?] = [:]
        
        if(_timeZone != nil) {mapData[Definitions.NOTIFICATION_SCHEDULE_TIMEZONE] = TimeZoneUtils.shared.timeZoneToString(timeZone: self._timeZone)}
        if(createdDate != nil) {mapData[Definitions.NOTIFICATION_SCHEDULE_INITIAL_DATE] = self.createdDate!.description}
        if(interval != nil) {mapData[Definitions.NOTIFICATION_SCHEDULE_INTERVAL] = self.interval}
        if(repeats != nil) {mapData[Definitions.NOTIFICATION_SCHEDULE_REPEATS]  = self.repeats}
        
        return mapData
    }
    
    public func validate() throws {
        
        if(IntUtils.isNullOrEmpty(interval) || interval! < 5){
            throw ExceptionFactory
                .shared
                .createNewAwesomeException(
                    className: NotificationIntervalModel.TAG,
                    code: ExceptionCode.CODE_INVALID_ARGUMENTS,
                    message: "Interval is required and must be equal or greater than 5",
                    detailedCode: ExceptionCode.DETAILED_INVALID_ARGUMENTS+".notificationInterval.interval")
        }

        if((repeats ?? false) && interval! < 60){
            throw ExceptionFactory
                .shared
                .createNewAwesomeException(
                    className: NotificationIntervalModel.TAG,
                    code: ExceptionCode.CODE_INVALID_ARGUMENTS,
                    message: "time interval must be at least 60 if repeating",
                    detailedCode: ExceptionCode.DETAILED_INVALID_ARGUMENTS+".notificationInterval.interval")
        }
    }
    
    public func getUNNotificationTrigger() -> UNNotificationTrigger? {
        
        do {
            try validate();
            let trigger = UNTimeIntervalNotificationTrigger( timeInterval: Double(interval!), repeats: repeats! )
            
            return trigger
            
        } catch {
            Logger.shared.e("NotificationIntervalModel", error.localizedDescription)
        }
        return nil
    }
    
    public func getNextValidDate(referenceDate: RealDateTime = RealDateTime()) -> RealDateTime? {
        guard let createdDate:RealDateTime = self.createdDate
        else { return nil }
        let timeZone:TimeZone = self.timeZone ?? TimeZone.current
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        
        // When repeats is true, calculate the next valid date based on createdDate
        if self.repeats ?? true {
            return getNextValidDateWithRepetition(referenceDate: referenceDate, createdDate: createdDate, calendar: calendar, timeZone: timeZone)
        } else {
            return getNextValidDateFromCreatedDate(referenceDate: referenceDate, createdDate: createdDate, calendar: calendar, timeZone: timeZone)
        }
    }

    private func getNextValidDateWithRepetition(referenceDate: RealDateTime, createdDate: RealDateTime, calendar: Calendar, timeZone: TimeZone) -> RealDateTime? {
        // Calculate the time interval between the reference date and createdDate
        let intervalFromCreated = referenceDate.date.secondsSince1970 - createdDate.date.secondsSince1970
        // Calculate the number of interval multiples between createdDate and the reference date
        let numIntervals = Int(intervalFromCreated / Int64(self.interval!))
        // Calculate the next valid date as the next interval multiple after the reference date
        guard let nextValidDate = calendar.date(byAdding: .second, value: (numIntervals + 1) * self.interval!, to: createdDate.date)
        else { return nil }
        
        return RealDateTime.init(fromDate: nextValidDate, inTimeZone: timeZone)
    }

    private func getNextValidDateFromCreatedDate(referenceDate: RealDateTime, createdDate: RealDateTime, calendar: Calendar, timeZone: TimeZone) -> RealDateTime? {
        // Calculate the next valid date as a simple time interval from the reference date
        guard let nextValidDate:Date = calendar.date(
            byAdding: .second,
            value: interval!,
            to: createdDate.date)
        else { return nil }
        
        let nextRealDate = RealDateTime.init(fromDate: nextValidDate, inTimeZone: timeZone)
        if nextRealDate < referenceDate {
            print("\(nextRealDate) < \(referenceDate)")
            return nil
        }
        
        return nextRealDate
    }
    
    public func hasNextValidDate(referenceDate: RealDateTime = RealDateTime()) -> Bool {
        return getNextValidDate(referenceDate: referenceDate) != nil
    }
    
    public func isRepeated() -> Bool { return repeats ?? false }
}
