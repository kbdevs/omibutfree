public enum NotificationLifeCycle : String, CaseIterable {
    
    case Foreground = "Foreground"
    case Background = "Background"
    case Terminated = "Terminated"
    
    static var AppKilled:NotificationLifeCycle {
        get { return .Terminated }
    }
}
