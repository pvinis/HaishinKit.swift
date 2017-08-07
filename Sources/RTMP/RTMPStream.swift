import Foundation
import AVFoundation

/**
 flash.net.NetStreamInfo for Swift
 */
public struct RTMPStreamInfo {
    public internal(set) var byteCount:Int64 = 0
    public internal(set) var resourceName:String? = nil
    public internal(set) var currentBytesPerSecond:Int32 = 0

    private var previousByteCount:Int64 = 0

    mutating func on(timer:Timer) {
        let byteCount:Int64 = self.byteCount
        currentBytesPerSecond = Int32(byteCount - previousByteCount)
        previousByteCount = byteCount
    }

    mutating func clear() {
        byteCount = 0
        currentBytesPerSecond = 0
        previousByteCount = 0
    }
}

extension RTMPStreamInfo: CustomStringConvertible {
    // MARK: CustomStringConvertible
    public var description:String {
        return Mirror(reflecting: self).description
    }
}

// MARK: -
/**
 flash.net.NetStream for Swift
 */
open class RTMPStream: NetStream {
    /**
     NetStatusEvent#info.code for NetStream
     */
    public enum Code: String {
        case bufferEmpty               = "NetStream.Buffer.Empty"
        case bufferFlush               = "NetStream.Buffer.Flush"
        case bufferFull                = "NetStream.Buffer.Full"
        case connectClosed             = "NetStream.Connect.Closed"
        case connectFailed             = "NetStream.Connect.Failed"
        case connectRejected           = "NetStream.Connect.Rejected"
        case connectSuccess            = "NetStream.Connect.Success"
        case drmUpdateNeeded           = "NetStream.DRM.UpdateNeeded"
        case failed                    = "NetStream.Failed"
        case multicastStreamReset      = "NetStream.MulticastStream.Reset"
        case pauseNotify               = "NetStream.Pause.Notify"
        case publishBadName            = "NetStream.Publish.BadName"
        case publishIdle               = "NetStream.Publish.Idle"
        case publishStart              = "NetStream.Publish.Start"
        case recordAlreadyExists       = "NetStream.Record.AlreadyExists"
        case recordFailed              = "NetStream.Record.Failed"
        case recordNoAccess            = "NetStream.Record.NoAccess"
        case recordStart               = "NetStream.Record.Start"
        case recordStop                = "NetStream.Record.Stop"
        case recordDiskQuotaExceeded   = "NetStream.Record.DiskQuotaExceeded"
        case secondScreenStart         = "NetStream.SecondScreen.Start"
        case secondScreenStop          = "NetStream.SecondScreen.Stop"
        case seekFailed                = "NetStream.Seek.Failed"
        case seekInvalidTime           = "NetStream.Seek.InvalidTime"
        case seekNotify                = "NetStream.Seek.Notify"
        case stepNotify                = "NetStream.Step.Notify"
        case unpauseNotify             = "NetStream.Unpause.Notify"
        case unpublishSuccess          = "NetStream.Unpublish.Success"
        case videoDimensionChange      = "NetStream.Video.DimensionChange"

        public var level:String {
            switch self {
            case .bufferEmpty:
                return "status"
            case .bufferFlush:
                return "status"
            case .bufferFull:
                return "status"
            case .connectClosed:
                return "status"
            case .connectFailed:
                return "error"
            case .connectRejected:
                return "error"
            case .connectSuccess:
                return "status"
            case .drmUpdateNeeded:
                return "status"
            case .failed:
                return "error"
            case .multicastStreamReset:
                return "status"
            case .pauseNotify:
                return "status"
            case .publishBadName:
                return "error"
            case .publishIdle:
                return "status"
            case .publishStart:
                return "status"
            case .recordAlreadyExists:
                return "status"
            case .recordFailed:
                return "error"
            case .recordNoAccess:
                return "error"
            case .recordStart:
                return "status"
            case .recordStop:
                return "status"
            case .recordDiskQuotaExceeded:
                return "error"
            case .secondScreenStart:
                return "status"
            case .secondScreenStop:
                return "status"
            case .seekFailed:
                return "error"
            case .seekInvalidTime:
                return "error"
            case .seekNotify:
                return "status"
            case .stepNotify:
                return "status"
            case .unpauseNotify:
                return "status"
            case .unpublishSuccess:
                return "status"
            case .videoDimensionChange:
                return "status"
            }
        }

        func data(_ description:String) -> ASObject {
            return [
                "code": rawValue,
                "level": level,
                "description": description,
            ]
        }
    }

    public enum WhatToDo {
        case stream
        case record
        case both
    }

    public enum WhatWillServerDo: String {
        case live          = "live"
        case record        = "record"
        case append        = "append"
        case appendWithGap = "appendWithGap"
    }

    enum ReadyState: UInt8 {
        case initialized = 0
        case open        = 1
        case publish     = 4
        case publishing  = 5
        case closed      = 6
    }

    enum RecordingState: UInt8 {
        case notRecording = 0
        case recording = 1
    }

    static let defaultID:UInt32 = 0
    open static let defaultAudioBitrate:UInt32 = AACEncoder.defaultBitrate
    open static let defaultVideoBitrate:UInt32 = H264Encoder.defaultBitrate
    open var qosDelegate:RTMPStreamQoSDelegate? = nil
    open var statsDelegate:RTMPStreamStatsDelegate? = nil
    open internal(set) var info:RTMPStreamInfo = RTMPStreamInfo()
    open fileprivate(set) var objectEncoding:UInt8 = RTMPConnection.defaultObjectEncoding
    open fileprivate(set) dynamic var currentFPS:UInt16 = 0

    var id:UInt32 = RTMPStream.defaultID
    var readyState:ReadyState = .initialized {
        didSet {
            switch readyState {
            case .open:
                currentFPS = 0
                frameCount = 0
                info.clear()
                qosDelegate?.reset()
            case .publishing:
                send(handlerName: "@setDataFrame", arguments: "onMetaData", createMetaData())
                mixer.audioIO.encoder.startRunning()
                mixer.videoIO.encoder.startRunning()
                sampler?.startRunning()
            default:
                break
            }
        }
    }
    var recordingState: RecordingState = .notRecording {
        didSet {
            switch recordingState {
            case .notRecording: break

            case .recording: break

            }
        }
    }


    var audioTimestamp:Double = 0
    var videoTimestamp:Double = 0
    fileprivate(set) var muxer:RTMPMuxer = RTMPMuxer()
    fileprivate var paused:Bool = false
    fileprivate var sampler:MP4Sampler? = nil
    fileprivate var frameCount:UInt16 = 0
    fileprivate var dispatcher:IEventDispatcher!
    fileprivate var audioWasSent:Bool = false
    fileprivate var videoWasSent:Bool = false
    fileprivate var rtmpConnection:RTMPConnection
    fileprivate var previousTotalBytesOut:Int64 = 0

    public init(connection: RTMPConnection) {
        self.rtmpConnection = connection
        super.init()
        dispatcher = EventDispatcher(target: self)
        rtmpConnection.addEventListener(Event.RTMP_STATUS, selector: #selector(RTMPStream.on(status:)), observer: self)
        if (rtmpConnection.connected) {
            rtmpConnection.createStream(self)
        }
    }

    deinit {
        mixer.stopRunning()
        rtmpConnection.removeEventListener(Event.RTMP_STATUS, selector: #selector(RTMPStream.on(status:)), observer: self)
    }

    open func publish(_ name: String?, whatToDo: WhatToDo = .stream, whatWillServerDo: WhatWillServerDo = .live) {
        lockQueue.async {
            guard let name:String = name else {
                // stop publishing

                if (self.recordingState == .recording) {
                    self.mixer.recorder.stopRunning()
                    self.recordingState = .notRecording
                }
                switch self.readyState {
                case .publish, .publishing:
                    self.readyState = .open

                    self.mixer.audioIO.encoder.delegate = nil
                    self.mixer.videoIO.encoder.delegate = nil
                    self.mixer.audioIO.encoder.stopRunning()
                    self.mixer.videoIO.encoder.stopRunning()
                    self.sampler?.stopRunning()
                    self.FCUnpublish()
                    self.rtmpConnection.socket.doOutput(chunk: RTMPChunk(
                        type: .zero,
                        streamId: RTMPChunk.StreamID.audio.rawValue,
                        message: RTMPCommandMessage(
                            streamId: self.id,
                            transactionId: 0,
                            objectEncoding: self.objectEncoding,
                            commandName: "closeStream",
                            commandObject: nil,
                            arguments: []
                    )), locked: nil)
                default:
                    break
                }
                return
            }

            // start publishing

            if (whatToDo == .record || whatToDo == .both) {
                if (self.info.resourceName == name) {
                    self.mixer.recorder.fileName = self.info.resourceName
                    self.mixer.recorder.startRunning()
                    self.recordingState = .recording
                }
            }

            if (whatToDo == .stream || whatToDo == .both) {
                while (self.readyState == .initialized) {
                    usleep(100)
                }

                self.info.resourceName = name
                self.muxer.dispose()
                self.muxer.delegate = self
               
                self.mixer.audioIO.encoder.delegate = self.muxer
                self.mixer.videoIO.encoder.delegate = self.muxer
                self.sampler?.delegate = self.muxer
                self.mixer.startRunning()
                self.videoWasSent = false
                self.audioWasSent = false
                self.FCPublish()
                self.rtmpConnection.socket.doOutput(chunk: RTMPChunk(
                    type: .zero,
                    streamId: RTMPChunk.StreamID.audio.rawValue,
                    message: RTMPCommandMessage(
                        streamId: self.id,
                        transactionId: 0,
                        objectEncoding: self.objectEncoding,
                        commandName: "publish",
                        commandObject: nil,
                        arguments: [name, whatWillServerDo.rawValue]
                )), locked: nil)

                self.readyState = .publish
            }
        }
    }

    open func close() {
        if (readyState == .closed || readyState == .initialized) {
            return
        }
        publish(nil)
        lockQueue.sync {
            self.rtmpConnection.socket.doOutput(chunk: RTMPChunk(
                type: .zero,
                streamId: RTMPChunk.StreamID.command.rawValue,
                message: RTMPCommandMessage(
                    streamId: 0,
                    transactionId: 0,
                    objectEncoding: self.objectEncoding,
                    commandName: "deleteStream",
                    commandObject: nil,
                    arguments: [self.id]
            )), locked: nil)
            self.readyState = .closed
        }
    }

    open func send(handlerName:String, arguments:Any?...) {
        lockQueue.async {
            if (self.readyState == .closed) {
                return
            }
            let length:Int = self.rtmpConnection.socket.doOutput(chunk: RTMPChunk(message: RTMPDataMessage(
                streamId: self.id,
                objectEncoding: self.objectEncoding,
                handlerName: handlerName,
                arguments: arguments
            )), locked: nil)
            OSAtomicAdd64(Int64(length), &self.info.byteCount)
        }
    }

    open func pause() {
        lockQueue.async {
            self.paused = true
            switch self.readyState {
            case .publish, .publishing:
                self.mixer.audioIO.encoder.muted = true
                self.mixer.videoIO.encoder.muted = true
            default:
                break
            }
        }
    }

    open func resume() {
        lockQueue.async {
            self.paused = false
            switch self.readyState {
            case .publish, .publishing:
                self.mixer.audioIO.encoder.muted = false
                self.mixer.videoIO.encoder.muted = false
            default:
                break
            }
        }
    }

    open func togglePause() {
        lockQueue.async {
            switch self.readyState {
            case .publish, .publishing:
                self.paused = !self.paused
                self.mixer.audioIO.encoder.muted = self.paused
                self.mixer.videoIO.encoder.muted = self.paused
            default:
                break
            }
        }
    }

    open override func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer, withType: CMSampleBufferType, options: [NSObject : AnyObject]? = nil) {
        guard readyState == .publishing else {
            return
        }
        super.appendSampleBuffer(sampleBuffer, withType: withType, options: options)
    }

    open func appendFile(_ file:URL, completionHandler: MP4Sampler.Handler? = nil) {
        lockQueue.async {
            if (self.sampler == nil) {
                self.sampler = MP4Sampler()
                self.sampler?.delegate = self.muxer
                switch self.readyState {
                case .publishing:
                    self.sampler?.startRunning()
                default:
                    break
                }
            }
            self.sampler?.appendFile(file, completionHandler: completionHandler)
        }
    }

    func createMetaData() -> ASObject {
        metadata.removeAll()
#if os(iOS) || os(macOS)
        if let _:AVCaptureInput = mixer.videoIO.input {
            metadata["width"] = mixer.videoIO.encoder.width
            metadata["height"] = mixer.videoIO.encoder.height
            metadata["framerate"] = mixer.videoIO.fps
            metadata["videocodecid"] = FLVVideoCodec.avc.rawValue
            metadata["videodatarate"] = mixer.videoIO.encoder.bitrate
        }
        if let _:AVCaptureInput = mixer.audioIO.input {
            metadata["audiocodecid"] = FLVAudioCodec.aac.rawValue
            metadata["audiodatarate"] = mixer.audioIO.encoder.bitrate
        }
#endif
        return metadata
    }

    func on(timer:Timer) {
        currentFPS = frameCount
        frameCount = 0
        info.on(timer: timer)

        let currentBytesOutPerSecond = rtmpConnection.totalBytesOut - previousTotalBytesOut
        previousTotalBytesOut = rtmpConnection.totalBytesOut
        statsDelegate?.stats(
            bitrate:videoSettings["bitrate"] as! UInt,
            currentBytesOutPerSecond: UInt(currentBytesOutPerSecond),
            previousQueueBytesOut: UInt(rtmpConnection.socket.queueBytesOut)
        )
    }

    @objc private func on(status:Notification) {
        let e:Event = Event.from(status)
        guard let data:ASObject = e.data as? ASObject, let code:String = data["code"] as? String else {
            return
        }
        switch code {
        case RTMPConnection.Code.connectSuccess.rawValue:
            readyState = .initialized
            rtmpConnection.createStream(self)
        case RTMPStream.Code.publishStart.rawValue:
            readyState = .publishing
        default:
            break
        }
    }
}

extension RTMPStream {
    func FCPublish() {
        guard let name:String = info.resourceName, rtmpConnection.flashVer.contains("FMLE/") else {
            return
        }
        rtmpConnection.call("FCPublish", responder: nil, arguments: name)
    }

    func FCUnpublish() {
        guard let name:String = info.resourceName , rtmpConnection.flashVer.contains("FMLE/") else {
            return
        }
        rtmpConnection.call("FCUnpublish", responder: nil, arguments: name)
    }
}

extension RTMPStream: IEventDispatcher {
    // MARK: IEventDispatcher
    public func addEventListener(_ type:String, selector:Selector, observer:AnyObject? = nil, useCapture:Bool = false) {
        dispatcher.addEventListener(type, selector: selector, observer: observer, useCapture: useCapture)
    }
    public func removeEventListener(_ type:String, selector:Selector, observer:AnyObject? = nil, useCapture:Bool = false) {
        dispatcher.removeEventListener(type, selector: selector, observer: observer, useCapture: useCapture)
    }
    public func dispatch(event:Event) {
        dispatcher.dispatch(event: event)
    }
    public func dispatch(_ type:String, bubbles:Bool, data:Any?) {
        dispatcher.dispatch(type, bubbles: bubbles, data: data)
    }
}

extension RTMPStream: RTMPMuxerDelegate {
    // MARK: RTMPMuxerDelegate
    func metadata(_ metadata:ASObject) {
        send(handlerName: "@setDataFrame", arguments: "onMetaData", metadata)
    }

    func sampleOutput(audio buffer:Data, withTimestamp:Double, muxer:RTMPMuxer) {
        guard readyState == .publishing else {
            return
        }
        let type:FLVTagType = .audio
        let length:Int = rtmpConnection.socket.doOutput(chunk: RTMPChunk(
            type: audioWasSent ? .one : .zero,
            streamId: type.streamId,
            message: RTMPAudioMessage(streamId: id, timestamp: UInt32(audioTimestamp), payload: buffer)
        ), locked: nil)
        audioWasSent = true
        OSAtomicAdd64(Int64(length), &info.byteCount)
        audioTimestamp = withTimestamp + (audioTimestamp - floor(audioTimestamp))
    }

    func sampleOutput(video buffer:Data, withTimestamp:Double, muxer:RTMPMuxer) {
        guard readyState == .publishing else {
            return
        }
        let type:FLVTagType = .video
        OSAtomicOr32Barrier(1, &mixer.videoIO.encoder.locked)
        let length:Int = rtmpConnection.socket.doOutput(chunk: RTMPChunk(
            type: videoWasSent ? .one : .zero,
            streamId: type.streamId,
            message: RTMPVideoMessage(streamId: id, timestamp: UInt32(videoTimestamp), payload: buffer)
        ), locked: &mixer.videoIO.encoder.locked)
        videoWasSent = true
        OSAtomicAdd64(Int64(length), &info.byteCount)
        videoTimestamp = withTimestamp + (videoTimestamp - floor(videoTimestamp))
        frameCount += 1
    }
}
