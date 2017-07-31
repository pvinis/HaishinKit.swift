import Foundation

struct Preference {
    static var defaultInstance:Preference = Preference()
    
    var uri:String? = "rtmp://stream-staging-eu.mycujoo.tv/live"
    var streamName:String? = "ecf34b4aea4f41b99ef4933c775baf8c"
}
