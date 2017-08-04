import Foundation

public protocol RTMPStreamStatsDelegate: class {
    func stats(
        bitrate: UInt,
        currentBytesInPerSecond: UInt,
        currentBytesOutPerSecond: UInt,
        previousQueueBytesOut: UInt
    )
}
