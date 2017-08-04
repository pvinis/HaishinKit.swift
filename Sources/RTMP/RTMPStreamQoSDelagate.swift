import Foundation

public protocol RTMPStreamQoSDelegate: class {
    func didPublishSufficientBW(_ stream:RTMPStream, withConnection:RTMPConnection)
    func didPublishInsufficientBW(_ stream:RTMPStream, withConnection:RTMPConnection)
    func reset()
}
