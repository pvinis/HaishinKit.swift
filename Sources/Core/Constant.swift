
class Logger {
  func error(_ message: String) {
    print(message)
  }
}

var logger = Logger()

public enum CMSampleBufferType: String {
    case video = "video"
    case audio = "audio"
}
