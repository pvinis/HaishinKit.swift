import Foundation

struct Preference {
    static var defaultInstance:Preference = Preference()
    
    var uri:String? = "rtmp://stream-staging-eu.mycujoo.tv/live"
    var streamName:String? = "9acb05f05e434f47bf4b8f8fbe8a4fe0"
}
