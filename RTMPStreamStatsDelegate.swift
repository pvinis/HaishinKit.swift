import Foundation

public protocol RTMPStreamStatsDelegate: class {
    func stats(
        bitrate: UInt,
        currentBytesOutPerSecond: UInt,
        previousQueueBytesOut: UInt
    )
}
