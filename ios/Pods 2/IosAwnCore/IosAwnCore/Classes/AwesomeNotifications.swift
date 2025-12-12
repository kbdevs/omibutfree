//
//  AwesomeNotifications.swift
//  awesome_notifications
//
//  Created by CardaDev on 30/01/22.
//

import Foundation

public class AwesomeNotifications:
        NSObject,
        AwesomeActionEventListener,
        AwesomeNotificationEventListener,
        AwesomeLifeCycleEventListener,
        UIApplicationDelegate,
        UNUserNotificationCenterDelegate
{
    let TAG = "AwesomeNotifications"
    
    static var _debug:Bool? = nil
    public static var debug:Bool {
        get {
            if _debug == nil {
                _debug = DefaultsManager.shared.debug
            }
            return _debug!
        }
        set {
            _debug = newValue
            DefaultsManager.shared.debug = newValue
        }
    }
    
    static var initialValues:[String : Any?] = [:]
    
    public static var awesomeExtensions:AwesomeNotificationsExtension?
    public static var backgroundClassType:BackgroundExecutor.Type?
    public static var didFinishLaunch:Bool = false
    public static var removeFromEvents:Bool = false
    public static var completionHandlerGetInitialAction:((ActionReceived?) -> Void)? = nil
    
    // ************************** CONSTRUCTOR ***********************************
        
    public override init() {
        super.init()
        
        AwesomeNotifications.debug = isApplicationInDebug()
        
        if !SwiftUtils.isRunningOnExtension() {
            LifeCycleManager
                .shared
                .subscribe(listener: self)
                .startListeners()
        }
        
        activateiOSNotifications()
        
        DefaultsManager
            .shared
            .setDefaultGroupTest()
        
        BadgeManager
            .shared
            .syncBadgeAmount()
    }
    
    static var areDefaultsLoaded = false
    public static func loadExtensions() throws {
        if areDefaultsLoaded {
            return
        }
        
        if AwesomeNotifications.awesomeExtensions == nil {
            throw ExceptionFactory
                    .shared
                    .createNewAwesomeException(
                        className: "SwiftLoadDefaults",
                        code: ExceptionCode.CODE_INITIALIZATION_EXCEPTION,
                        message: "Awesome's plugin extension reference was not found.",
                        detailedCode: ExceptionCode.DETAILED_INITIALIZATION_FAILED+".awesomeNotifications.extensions")
        }
        
        AwesomeNotifications.awesomeExtensions!.loadExternalExtensions()
        
        areDefaultsLoaded = true
    }
    
    private var isTheMainInstance = false
    public func attachAsMainInstance(usingAwesomeEventListener listener: AwesomeEventListener){
        if self.isTheMainInstance {
            return
        }
        
        self.isTheMainInstance = true
        
        subscribeOnAwesomeNotificationEvents(listener: listener)
        
        AwesomeEventsReceiver
            .shared
            .subscribeOnNotificationEvents(listener: self)
            .subscribeOnActionEvents(listener: self)
        
        Logger.shared.d(TAG, "Awesome notifications \(self.hash) attached to app instance")
    }
    
    public func detachAsMainInstance(listener: AwesomeEventListener){
        if !self.isTheMainInstance {
            return
        }
        
        self.isTheMainInstance = false
        
        unsubscribeOnAwesomeNotificationEvents(listener: listener)
        
        AwesomeEventsReceiver
            .shared
            .unsubscribeOnNotificationEvents(listener: self)
            .unsubscribeOnActionEvents(listener: self)
        
        Logger.shared.d(TAG, "Awesome notifications \(self.hash) detached from app instance")
    }
    
    public func dispose(){
        if !SwiftUtils.isRunningOnExtension() {
            LifeCycleManager
                .shared
                .unsubscribe(listener: self)
        }
    }
    
    public func initialize() {
        AwesomeNotifications.initialValues.removeAll()
        AwesomeNotifications.initialValues.merge(
                Definitions.initialValues,
                uniquingKeysWith: { (current, _) in current })
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func activateiOSNotifications(){
        
        let categoryObject = UNNotificationCategory(
            identifier: Definitions.DEFAULT_CATEGORY_IDENTIFIER.uppercased(),
            actions: [],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        UNUserNotificationCenter.current().getNotificationCategories(completionHandler: { results in
            UNUserNotificationCenter.current().setNotificationCategories(results.union([categoryObject]))
        })
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.didFinishLaunch),
            name: UIApplication.didFinishLaunchingNotification, object: nil)
    }
    
    // ***********************  EVENT INTERFACES  *******************************
    
    public func onNewNotificationReceived(eventName: String, notificationReceived: NotificationReceived) {
        notifyNotificationEvent(eventName: eventName, notificationReceived: notificationReceived)
    }
    
    public func onNewActionReceived(fromEventNamed eventName: String, withActionReceived actionReceived: ActionReceived) {
        notifyActionEvent(fromEventNamed: eventName, withActionReceived: actionReceived)
    }
    
    public func onNewActionReceivedWithInterruption(fromEventNamed eventName: String, withActionReceived actionReceived: ActionReceived) -> Bool {
        return false
    }
    
    public func onNewLifeCycleEvent(lifeCycle: NotificationLifeCycle) {
        
        if !isTheMainInstance {
            return
        }
        
        switch lifeCycle {
            
            case .Foreground:
                PermissionManager
                    .shared
                    .handlePermissionResult()
                do {
                    let lostEvents = try LostEventsManager
                        .shared
                        .recoverLostNotificationEvents(
                            withReferenceLifeCycle: .Background,
                            createdHandle: DefaultsManager.shared.createdCallback,
                            displayedHandle: DefaultsManager.shared.displayedCallback,
                            actionHandle: DefaultsManager.shared.actionCallback,
                            dismissedHandle: DefaultsManager.shared.dismissedCallback
                        )
                    
                    for lostEvent in lostEvents {
                        notifyNotificationEvent(
                            eventName: lostEvent.eventName,
                            notificationReceived: lostEvent.notificationContent)
                    }
                    
                    RefreshSchedulesReceiver()
                            .refreshSchedules()
                    
                } catch {
                    if !(error is AwesomeNotificationsException) {
                        ExceptionFactory
                            .shared
                            .registerNewAwesomeException(
                                className: TAG,
                                code: ExceptionCode.CODE_UNKNOWN_EXCEPTION,
                                message: "An unknow exception was found while recovering lost events",
                                detailedCode: ExceptionCode.DETAILED_UNEXPECTED_ERROR,
                                originalException: error)
                    }
                }
                break
            
            case .Background: fallthrough
            case .Terminated:
                DefaultsManager
                    .shared
                    .registerLastDisplayedDate()
                break
        }
    }
    
    // **************************** OBSERVER PATTERN **************************************
    
    private lazy var notificationEventListeners = [AwesomeNotificationEventListener]()
    
    public func subscribeOnNotificationEvents(listener:AwesomeNotificationEventListener) {
        notificationEventListeners.append(listener)
    }
    
    public func unsubscribeOnNotificationEvents(listener:AwesomeNotificationEventListener) {
        if let index = notificationEventListeners.firstIndex(where: {$0 === listener}) {
            notificationEventListeners.remove(at: index)
        }
    }
    
    private func notifyNotificationEvent(eventName:String, notificationReceived:NotificationReceived){
        notifyAwesomeEvent(eventType: eventName, content: notificationReceived.toMap())
        for listener in notificationEventListeners {
            listener.onNewNotificationReceived(
                eventName: eventName,
                notificationReceived: notificationReceived)
        }
    }
    
    // **************************** OBSERVER PATTERN **************************************
    
    private lazy var notificationActionListeners = [AwesomeActionEventListener]()
    
    public func subscribeOnActionEvents(listener:AwesomeActionEventListener) {
        notificationActionListeners.append(listener)
    }
    
    public func unsubscribeOnActionEvents(listener:AwesomeActionEventListener) {
        if let index = notificationActionListeners.firstIndex(where: {$0 === listener}) {
            notificationActionListeners.remove(at: index)
        }
    }
    
    private func notifyActionEvent(fromEventNamed eventName:String, withActionReceived actionReceived:ActionReceived){
        notifyAwesomeEvent(eventType: eventName, content: actionReceived.toMap())
        for listener in notificationActionListeners {
            listener
                .onNewActionReceived(
                    fromEventNamed: eventName,
                    withActionReceived: actionReceived)
        }
    }
    
    // ***************************************************************************************
    
    private lazy var awesomeEventListeners = [AwesomeEventListener]()
    
    public func subscribeOnAwesomeNotificationEvents(listener:AwesomeEventListener) {
        awesomeEventListeners.append(listener)
    }
    
    public func unsubscribeOnAwesomeNotificationEvents(listener:AwesomeEventListener) {
        if let index = awesomeEventListeners.firstIndex(where: {$0 === listener}) {
            awesomeEventListeners.remove(at: index)
        }
    }
    
    private func notifyAwesomeEvent(eventType: String, content: [String : Any?]){
        for listener in awesomeEventListeners {
            listener.onNewAwesomeEvent(eventType: eventType, content: content)
        }
    }
    
    // *****************************  LIFECYCLE FUNCTIONS  **********************************
    
    public var currentLifeCycle: NotificationLifeCycle {
        get { return LifeCycleManager.shared.currentLifeCycle }
        set { LifeCycleManager.shared.currentLifeCycle = newValue }
    }
    
    // *****************************  DRAWABLE FUNCTIONS  **********************************
    
    public func getDrawableData(bitmapReference:String) -> Data? {
        guard let image:UIImage =
            BitmapUtils
                .shared
                .getBitmapFromSource(
                    bitmapPath: bitmapReference,
                    roundedBitpmap: false)
        else {
            return nil
        }
        
        return image.pngData()
    }
    
    // ***************************************************************************************
    
    public func setEventsHandle(
        createdHandle:Int64,
        displayedHandle:Int64,
        actionHandle:Int64,
        dismissedHandle:Int64
    ) throws {
        
        DefaultsManager.shared.actionCallback = actionHandle
        DefaultsManager.shared.createdCallback = createdHandle
        DefaultsManager.shared.displayedCallback = displayedHandle
        DefaultsManager.shared.dismissedCallback = dismissedHandle
        
        let lostEvents = try LostEventsManager
            .shared
            .recoverLostNotificationEvents(
                withReferenceLifeCycle: .Terminated,
                createdHandle: createdHandle,
                displayedHandle: displayedHandle,
                actionHandle: actionHandle,
                dismissedHandle: dismissedHandle
            )
                
        for lostEvent in lostEvents {
            notifyNotificationEvent(
                eventName: lostEvent.eventName,
                notificationReceived: lostEvent.notificationContent)
        }
    }
    
    public func getActionHandle() -> Int64 {
        return DefaultsManager
                    .shared
                    .actionCallback
    }
    
    public func isApplicationInDebug() -> Bool {
#if DEBUG
        return true
#else
        return false
#endif
    }
    
    // *****************************  INITIALIZATION FUNCTIONS  **********************************
    
    public func initialize(
        defaultIconPath:String?,
        channels:[NotificationChannelModel],
        backgroundHandle:Int64,
        debug:Bool
    ) throws {
        
        setDefaultConfigurations (
            defaultIconPath: defaultIconPath,
            backgroundHandle: backgroundHandle)
        
        if ListUtils.isNullOrEmpty(channels) {
            throw ExceptionFactory
                    .shared
                    .createNewAwesomeException(
                        className: TAG,
                        code: ExceptionCode.CODE_INITIALIZATION_EXCEPTION,
                        message: "At least one channel is required",
                        detailedCode: ExceptionCode.DETAILED_REQUIRED_ARGUMENTS+".channelList")
        }
        
        for channel in channels {
            ChannelManager
                .shared
                .saveChannel(channel: channel, setOnlyNew: true)
        }
        
        AwesomeNotifications.debug = debug
        
        if(AwesomeNotifications.debug){
            Logger.shared.d(TAG, "Awesome Notifications initialized")
        }
    }
    
    private func setDefaultConfigurations(defaultIconPath:String?, backgroundHandle:Int64?) {
        DefaultsManager.shared.defaultIcon = defaultIconPath
        DefaultsManager.shared.backgroundCallback = backgroundHandle ?? 0
    }
    
    // *****************************  RECOVER FUNCTIONS  **********************************
    
    let timeoutLockedProcess:TimeInterval = 3
    
    private func recoverNotificationsCreated() throws {
        let lostCreated = CreatedManager
            .shared
            .listCreated()
        
        for createdNotification in lostCreated {
            try createdNotification.validate()
            
            notifyNotificationEvent(
                eventName: Definitions.EVENT_NOTIFICATION_CREATED,
                notificationReceived: createdNotification)
            
            _ = CreatedManager
                .shared
                .removeCreated(
                    id: createdNotification.id!,
                    createdDate: createdNotification.createdDate!)
        }
        
        CreatedManager
            .shared
            .removeAllCreated()
        
        CreatedManager
            .shared
            .commit()
    }
    
    private func recoverNotificationsDisplayed(
        withCurrentSchedules currentSchedules:[NotificationModel],
        withReferenceLifeCycle referenceLifeCycle:NotificationLifeCycle
    ) throws {
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
            
            guard let displayedDate:RealDateTime = displayedNotification.displayedDate ?? displayedNotification.createdDate
            else { continue }
            
            if currentDate >= displayedDate && lastDisplayedDate <= displayedDate {
                try displayedNotification.validate()
                
                notifyNotificationEvent(
                    eventName: Definitions.EVENT_NOTIFICATION_DISPLAYED,
                    notificationReceived: displayedNotification)
            }
            
            if !DisplayedManager
                .shared
                .removeDisplayed(
                    id: displayedNotification.id!,
                    displayedDate: displayedNotification.displayedDate!)
            {
                Logger.shared.e(TAG, "Displayed event \(displayedNotification.id!) could not be cleaned")
            }
        }
        
        DefaultsManager
            .shared
            .registerLastDisplayedDate()
    }
    
    func regenerateScheduledDisplayedDates(startDate: Date, endDate: Date) -> [Date:[String:Any?]] {
        var displayDates = [Date:[String:Any?]]()
        let center = UNUserNotificationCenter.current()
        
        center.getPendingNotificationRequests { (requests) in
            let calendar = Calendar.current
            
            for request in requests {
                guard let trigger = request.trigger as? UNCalendarNotificationTrigger
                else { continue }
                
                guard let jsonData:[String:Any?] = request.content.userInfo[Definitions.NOTIFICATION_JSON] as? [String:Any?]
                else { continue }
                
                let nextTriggerDate = trigger.nextTriggerDate()!
                
                if nextTriggerDate >= startDate && nextTriggerDate <= endDate {
                    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: nextTriggerDate)
                    let displayDate = calendar.date(from: components)!
                    
                    displayDates[displayDate] = jsonData
                }
            }
        }
        
        return displayDates
    }
    
    // *****************************  IOS NOTIFICATION CENTER METHODS  **********************************
    
    private var _originalNotificationCenterDelegate: UNUserNotificationCenterDelegate?
    
    @objc public func didFinishLaunch(_ application: UIApplication) {
        
        UNUserNotificationCenter.current().delegate = self
        
        AwesomeNotifications.didFinishLaunch = true
        if AwesomeNotifications.completionHandlerGetInitialAction != nil {
            AwesomeNotifications
                .completionHandlerGetInitialAction!(
                    ActionManager.shared.getInitialAction(
                        removeFromEvents: AwesomeNotifications.removeFromEvents))
        }
        
            
        if AwesomeNotifications.debug {
            Logger.shared.d(TAG, "Awesome Notifications attached for iOS")
        }
    }
    
    @available(iOS 10.0, *)
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ){
        Logger.shared.d(TAG, "Notification Category Identifier (action): \(response.notification.request.content.categoryIdentifier)")
        do {
            let buttonKeyPressed = response.actionIdentifier == UNNotificationDefaultActionIdentifier.description ?
                nil : response.actionIdentifier
            
            switch response.actionIdentifier {
            
                case UNNotificationDismissActionIdentifier.description:
                    try DismissedNotificationReceiver
                        .shared
                        .addNewDismissEvent(
                            fromResponse: response,
                            buttonKeyPressed: buttonKeyPressed,
                            whenFinished: { (success:Bool, error:Error?) in
                                
                                if !success && self._originalNotificationCenterDelegate != nil {
                                    self._originalNotificationCenterDelegate!
                                        .userNotificationCenter?(
                                            center,
                                            didReceive: response,
                                            withCompletionHandler: completionHandler)
                                }
                                else {
                                    completionHandler()
                                }
                            })
                    
                default:
                    try NotificationActionReceiver
                        .shared
                        .addNewActionEvent(
                            fromResponse: response,
                            buttonKeyPressed: buttonKeyPressed,
                            whenFinished: { (success:Bool, error:Error?) in
                                
                                if !success && self._originalNotificationCenterDelegate != nil {
                                    self._originalNotificationCenterDelegate!
                                        .userNotificationCenter?(
                                            center,
                                            didReceive: response,
                                            withCompletionHandler: completionHandler)
                                }
                                else {
                                    completionHandler()
                                }
                            })
            }
        } catch {
            if !(error is AwesomeNotificationsException) {
                ExceptionFactory
                    .shared
                    .registerNewAwesomeException(
                        className: TAG,
                        code: ExceptionCode.CODE_UNKNOWN_EXCEPTION,
                        message: "An unknow exception was found while receiving a notification action",
                        detailedCode: ExceptionCode.DETAILED_UNEXPECTED_ERROR,
                        originalException: error)
            }
            
            if self._originalNotificationCenterDelegate != nil {
                self._originalNotificationCenterDelegate!
                    .userNotificationCenter?(
                        center,
                        didReceive: response,
                        withCompletionHandler: completionHandler)
            }
            else {
                completionHandler()
            }
        }
    }
    
    @available(iOS 10.0, *)
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ){
        let jsonData:[String : Any?] =
                extractNotificationJsonMap(
                    fromContent: notification.request.content)
        
        if let notificationModel:NotificationModel =
            NotificationBuilder
                .newInstance()
                .jsonDataToNotificationModel(
                    jsonData: jsonData)
        {
            do {
                try StatusBarManager
                    .shared
                    .showNotificationOnStatusBar(
                        withNotificationModel: notificationModel,
                        whenFinished: { (notificationDisplayed:Bool, mustPlaySound:Bool) in
                            
                            if !notificationDisplayed && self._originalNotificationCenterDelegate != nil {
                                self._originalNotificationCenterDelegate?
                                    .userNotificationCenter?(
                                        center,
                                        willPresent: notification,
                                        withCompletionHandler: completionHandler)
                            }
                            else {
                                if notificationDisplayed {
                                    if mustPlaySound {
                                        completionHandler([.alert, .badge, .sound])
                                    }
                                    else {
                                        completionHandler([.alert, .badge])
                                    }
                                }
                                else {
                                    completionHandler([])
                                }
                            }
                        })
            } catch {
                if !(error is AwesomeNotificationsException) {
                    ExceptionFactory
                        .shared
                        .registerNewAwesomeException(
                            className: TAG,
                            code: ExceptionCode.CODE_UNKNOWN_EXCEPTION,
                            message: "An unknow exception was found while displaying a notification on Statusbar",
                            detailedCode: ExceptionCode.DETAILED_UNEXPECTED_ERROR,
                            originalException: error)
                }
            }
            
        }
        else {
            if _originalNotificationCenterDelegate != nil {
                _originalNotificationCenterDelegate?
                    .userNotificationCenter?(
                        center,
                        willPresent: notification,
                        withCompletionHandler: completionHandler)
            }
            else {
                completionHandler([.alert, .badge, .sound])
            }
        }
        
        do {
            let lostEvents = try LostEventsManager
                .shared
                .recoverLostNotificationEvents(
                    withReferenceLifeCycle: .Foreground,
                    createdHandle: DefaultsManager.shared.createdCallback,
                    displayedHandle: DefaultsManager.shared.displayedCallback,
                    actionHandle: DefaultsManager.shared.actionCallback,
                    dismissedHandle: DefaultsManager.shared.dismissedCallback
                )
            
            for lostEvent in lostEvents {
                notifyNotificationEvent(
                    eventName: lostEvent.eventName,
                    notificationReceived: lostEvent.notificationContent)
            }
        } catch {
            if !(error is AwesomeNotificationsException) {
                ExceptionFactory
                    .shared
                    .registerNewAwesomeException(
                        className: TAG,
                        code: ExceptionCode.CODE_UNKNOWN_EXCEPTION,
                        message: "An unknow exception was found while displaying a notification in foreground",
                        detailedCode: ExceptionCode.DETAILED_UNEXPECTED_ERROR,
                        originalException: error)
            }
        }
    }
    
    // *****************************  EXTRACT NOTIFICATION METHODS  **********************************
    
    private func extractNotificationJsonMap(fromContent content: UNNotificationContent) -> [String : Any?]{
        
        var jsonMap:[String : Any?]
        
        if(content.userInfo[Definitions.NOTIFICATION_JSON] != nil){
            let jsonData:String = content.userInfo[Definitions.NOTIFICATION_JSON] as! String
            jsonMap = JsonUtils.fromJson(jsonData) ?? [:]
        }
        else {
            jsonMap = content.userInfo as! [String : Any?]
            
            if(jsonMap[Definitions.NOTIFICATION_MODEL_CONTENT] is String){
                jsonMap[Definitions.NOTIFICATION_MODEL_CONTENT] = JsonUtils.fromJson(jsonMap[Definitions.NOTIFICATION_MODEL_CONTENT] as? String)
            }
            
            if(jsonMap[Definitions.NOTIFICATION_MODEL_BUTTONS] is String){
                jsonMap[Definitions.NOTIFICATION_MODEL_BUTTONS] = JsonUtils.fromJson(jsonMap[Definitions.NOTIFICATION_MODEL_BUTTONS] as? String)
            }
            
            if(jsonMap[Definitions.NOTIFICATION_MODEL_SCHEDULE] is String){
                jsonMap[Definitions.NOTIFICATION_MODEL_SCHEDULE] = JsonUtils.fromJson(jsonMap[Definitions.NOTIFICATION_MODEL_SCHEDULE] as? String)
            }
        }
        return jsonMap
    }
    
    
    // *****************************  NOTIFICATION METHODS  **********************************
    
    public func createNotification(
        fromNotificationModel notificationModel: NotificationModel,
        afterCreated completionHandler: @escaping (Bool, UNMutableNotificationContent?, Error?) -> ()
    ) throws {
        try NotificationSenderAndScheduler
                .send(
                    createdSource: NotificationSource.Local,
                    notificationModel: notificationModel,
                    completion: completionHandler,
                    appLifeCycle: LifeCycleManager
                                        .shared
                                        .currentLifeCycle)
    }
    
    // *****************************  CHANNEL METHODS  **********************************
    
    public func setChannel(channel:NotificationChannelModel) -> Bool {
        ChannelManager
            .shared
            .saveChannel(channel: channel, setOnlyNew: false)
        return true
    }
    
    public func removeChannel(channelKey:String) -> Bool {
        return ChannelManager
                    .shared
                    .removeChannel(channelKey: channelKey)
    }
    
    public func getAllChannels() -> [NotificationChannelModel] {
        return ChannelManager
                    .shared
                    .listChannels()
    }
    
    // *****************************  SCHEDULE METHODS  **********************************
    
    public func getNextValidDate(
        scheduleModel: NotificationScheduleModel,
        fixedDate: String,
        timeZoneName: String
    ) -> RealDateTime? {
        let fixedDateTime:RealDateTime = RealDateTime.init(
            fromDateText: fixedDate, inTimeZone: timeZoneName) ?? RealDateTime()
        scheduleModel.createdDate = fixedDateTime
        return scheduleModel.getNextValidDate(referenceDate: fixedDateTime)
    }
    
    public func getLocalTimeZone() -> TimeZone {
        return DateUtils.shared.localTimeZone
    }
    
    public func getUtcTimeZone() -> TimeZone {
        return DateUtils.shared.utcTimeZone
    }
    
    // ****************************  BADGE COUNTER METHODS  **********************************
    
    public func getGlobalBadgeCounter() -> Int {
        return BadgeManager
                    .shared
                    .globalBadgeCounter
    }
    
    public func setGlobalBadgeCounter(withAmmount ammount:Int) {
        BadgeManager
            .shared
            .globalBadgeCounter = ammount
    }
    
    public func resetGlobalBadgeCounter() {
        BadgeManager
            .shared
            .resetGlobalBadgeCounter()
    }
    
    public func incrementGlobalBadgeCounter() -> Int {
        return BadgeManager
                    .shared
                    .incrementGlobalBadgeCounter()
    }
    
    public func decrementGlobalBadgeCounter() -> Int {
        return BadgeManager
                    .shared
                    .decrementGlobalBadgeCounter()
    }
    
    public func getInitialAction(removeFromEvents:Bool, completionHandler: @escaping (ActionReceived?) -> Void) {
        if AwesomeNotifications.didFinishLaunch {
            completionHandler(ActionManager.shared.getInitialAction(removeFromEvents: removeFromEvents))
            return
        }
        AwesomeNotifications.removeFromEvents = removeFromEvents
        AwesomeNotifications.completionHandlerGetInitialAction = completionHandler
    }
    
    // *****************************  CANCELATION METHODS  **********************************
    
    public func dismissNotification(byId id: Int) -> Bool {
        let success:Bool =
                CancellationManager
                    .shared
                    .dismissNotification(byId: id)
        
        if AwesomeNotifications.debug {
            Logger.shared.d(TAG, "Notification id \(id) dismissed")
        }
        
        return success
    }
    
    public func cancelSchedule(byId id: Int) -> Bool {
        let success:Bool =
                CancellationManager
                    .shared
                    .cancelSchedule(byId: id)
        
        return success
    }
    
    public func cancelNotification(byId id: Int) -> Bool {
        let success:Bool =
                CancellationManager
                    .shared
                    .cancelNotification(byId: id)
        
        return success
    }
    
    public func dismissNotifications(byChannelKey channelKey: String) -> Bool {
        let success:Bool =
                CancellationManager
                    .shared
                    .dismissNotifications(
                        byChannelKey: channelKey)
        
        return success
    }
    
    public func cancelSchedules(byChannelKey channelKey: String) -> Bool {
        let success:Bool =
                CancellationManager
                    .shared
                    .cancelSchedules(
                        byChannelKey: channelKey)
        
        return success
    }
    
    public func cancelNotifications(byChannelKey channelKey: String) -> Bool {
        let success:Bool =
                CancellationManager
                    .shared
                    .cancelNotifications(
                        byChannelKey: channelKey)
        
        return success
    }
    
    public func dismissNotifications(byGroupKey groupKey: String) -> Bool {
        let success:Bool =
                CancellationManager
                    .shared
                    .dismissNotifications(
                        byGroupKey: groupKey)
        
        return success
    }
    
    public func cancelSchedules(byGroupKey groupKey: String) -> Bool {
        let success:Bool =
                CancellationManager
                    .shared
                    .cancelSchedules(
                        byGroupKey: groupKey)
        
        return success
    }
    
    public func cancelNotifications(byGroupKey groupKey: String) -> Bool {
        let success:Bool =
                CancellationManager
                    .shared
                    .cancelNotifications(
                        byGroupKey: groupKey)
        
        return success
    }
    
    public func dismissAllNotifications() -> Bool {
        let success:Bool =
                CancellationManager
                    .shared
                    .dismissAllNotifications()
        
        return success
    }
    
    public func cancelAllSchedules() -> Bool {
        let success:Bool =
                CancellationManager
                    .shared
                    .cancelAllSchedules()
        
        return success
        
    }
    
    public func cancelAllNotifications() -> Bool {
        let success:Bool =
                CancellationManager
                    .shared
                    .cancelAllNotifications()
        
        return success
    }
    
    // *****************************  PERMISSION METHODS  **********************************
    
    public func areNotificationsGloballyAllowed(whenCompleted completionHandler: @escaping (Bool) -> ()) {
        PermissionManager
            .shared
            .areNotificationsGloballyAllowed(
                whenGotResults: completionHandler)
    }
    
    public func showNotificationPage(whenUserReturns completionHandler: @escaping () -> ()){
        PermissionManager
            .shared
            .showNotificationConfigPage(
                whenUserReturns: completionHandler)
    }
    
    public func showPreciseAlarmPage(whenUserReturns completionHandler: @escaping () -> ()){
        PermissionManager
            .shared
            .showNotificationConfigPage(
                whenUserReturns: completionHandler)
    }
    
    public func showDnDGlobalOverridingPage(whenUserReturns completionHandler: @escaping () -> ()){
        PermissionManager
            .shared
            .showNotificationConfigPage(
                whenUserReturns: completionHandler)
    }
    
    public func arePermissionsAllowed(
        _ permissions:[String],
        filteringByChannelKey channelKey:String?,
        whenGotResults completion: @escaping ([String]) -> ()
    ){
        PermissionManager
            .shared
            .arePermissionsAllowed(
                permissions,
                filteringByChannelKey: channelKey,
                whenGotResults: completion)
    }
    
    public func shouldShowRationale(
        _ permissions:[String],
        filteringByChannelKey channelKey:String?,
        whenGotResults completion: @escaping ([String]) -> ()
    ){
        PermissionManager
            .shared
            .shouldShowRationale(
                permissions,
                filteringByChannelKey: channelKey,
                whenGotResults: completion)
    }
    
    public func requestUserPermissions(
        _ permissions:[String],
        filteringByChannelKey channelKey:String?,
        whenUserReturns completionHandler: @escaping ([String]) -> ()
    ) throws {
        try PermissionManager
            .shared
            .requestUserPermissions(
                permissions,
                filteringByChannelKey: channelKey,
                whenUserReturns: completionHandler)
        
    }
    
    public func setLocalization(languageCode:String?) -> Bool {
        return LocalizationManager
            .shared
            .setLocalization(
                languageCode: languageCode)
    }
    
    public func getLocalization() -> String {
        return LocalizationManager
            .shared
            .getLocalization()
    }
    
    public func isNotificationActiveOnStatusBar(
        id:Int,
        whenFinished completionHandler: @escaping (Bool) -> Void
    ){
        return StatusBarManager
            .shared
            .isNotificationActiveOnStatusBar(id: id, whenFinished: completionHandler)
    }

    public func getAllActiveNotificationIdsOnStatusBar(
        whenFinished completionHandler: @escaping ([Int]) -> Void
    ){
        return StatusBarManager
            .shared
            .getAllActiveNotificationIdsOnStatusBar(whenFinished: completionHandler)
    }
    
    public func listAllPendingSchedules(
        whenGotResults completionHandler: @escaping ([NotificationModel]) throws -> Void
    ){
        return ScheduleManager
            .shared
            .syncAllPendingSchedules(whenGotResults: completionHandler)
    }
}
