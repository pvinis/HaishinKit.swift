import CoreImage
import Foundation
import AVFoundation

public typealias CIContextFactory = () -> CIContext

final class VideoIOComponent: IOComponent {
    let lockQueue:DispatchQueue = DispatchQueue(label: "com.haishinkit.HaishinKit.VideoIOComponent.lock")
    var context:CIContext?
    var drawable:NetStreamDrawable?
    var formatDescription:CMVideoFormatDescription?

    lazy var encoder:H264Encoder = H264Encoder()
    lazy var queue:ClockedQueue = {
        let queue:ClockedQueue = ClockedQueue()
        queue.delegate = self
        return queue
    }()

    var effects:[VisualEffect] = []
    var contextFactory:CIContextFactory?


    var fps:Float64 = AVMixer.defaultFPS {
        didSet {
            guard
                let device:AVCaptureDevice = (input as? AVCaptureDeviceInput)?.device,
                let data = DeviceUtil.getActualFPS(fps, device: device) else {
                return
            }

            fps = data.fps
            encoder.expectedFPS = data.fps
            lfLogger?.info("\(data)")

            do {
                try device.lockForConfiguration()
                device.activeVideoMinFrameDuration = data.duration
                device.activeVideoMaxFrameDuration = data.duration
                device.unlockForConfiguration()
            } catch let error {
                lfLogger?.error("while locking device for fps: \(error)")
            }
        }
    }

    var position:AVCaptureDevicePosition = .back

    var videoSettings:[NSObject:AnyObject] = AVMixer.defaultVideoSettings {
        didSet {
            output.videoSettings = videoSettings
        }
    }

    var orientation:AVCaptureVideoOrientation = .portrait {
        didSet {
            guard orientation != oldValue else {
                return
            }
            for connection in output.connections {
                if let connection:AVCaptureConnection = connection as? AVCaptureConnection {
                    if (connection.isVideoOrientationSupported) {
                        connection.videoOrientation = orientation
                        
                    }
                }
            }
            drawable?.orientation = orientation
        }
    }

    var continuousAutofocus:Bool = false {
        didSet {
            guard continuousAutofocus != oldValue else {
                return
            }
            let focusMode:AVCaptureFocusMode = continuousAutofocus ? .continuousAutoFocus : .autoFocus
            guard let device:AVCaptureDevice = (input as? AVCaptureDeviceInput)?.device,
                device.isFocusModeSupported(focusMode) else {
                lfLogger?.warning("focusMode(\(focusMode.rawValue)) is not supported")
                return
            }
            do {
                try device.lockForConfiguration()
                device.focusMode = focusMode
                device.unlockForConfiguration()
            }
            catch let error {
                lfLogger?.error("while locking device for autofocus: \(error)")
            }
        }
    }

    var focusPointOfInterest:CGPoint? {
        didSet {
            guard
                let device:AVCaptureDevice = (input as? AVCaptureDeviceInput)?.device,
                let point:CGPoint = focusPointOfInterest,
                device.isFocusPointOfInterestSupported else {
                return
            }
            do {
                try device.lockForConfiguration()
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
                device.unlockForConfiguration()
            } catch let error {
                lfLogger?.error("while locking device for focusPointOfInterest: \(error)")
            }
        }
    }

    var exposurePointOfInterest:CGPoint? {
        didSet {
            guard
                let device:AVCaptureDevice = (input as? AVCaptureDeviceInput)?.device,
                let point:CGPoint = exposurePointOfInterest,
                device.isExposurePointOfInterestSupported else {
                return
            }
            do {
                try device.lockForConfiguration()
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
                device.unlockForConfiguration()
            } catch let error {
                lfLogger?.error("while locking device for exposurePointOfInterest: \(error)")
            }
        }
    }

    var continuousExposure:Bool = false {
        didSet {
            guard continuousExposure != oldValue else {
                return
            }
            let exposureMode:AVCaptureExposureMode = continuousExposure ? .continuousAutoExposure : .autoExpose
            guard let device:AVCaptureDevice = (input as? AVCaptureDeviceInput)?.device,
                device.isExposureModeSupported(exposureMode) else {
                lfLogger?.warning("exposureMode(\(exposureMode.rawValue)) is not supported")
                return
            }
            do {
                try device.lockForConfiguration()
                device.exposureMode = exposureMode
                device.unlockForConfiguration()
            } catch let error {
                lfLogger?.error("while locking device for autoexpose: \(error)")
            }
        }
    }

    fileprivate var _output:AVCaptureVideoDataOutput? = nil
    var output:AVCaptureVideoDataOutput! {
        get {
            if (_output == nil) {
                _output = AVCaptureVideoDataOutput()
                _output!.alwaysDiscardsLateVideoFrames = true
                _output!.videoSettings = videoSettings
            }
            return _output!
        }
        set {
            if (_output == newValue) {
                return
            }
            if let output:AVCaptureVideoDataOutput = _output {
                output.setSampleBufferDelegate(nil, queue: nil)
                mixer?.session.removeOutput(output)
            }
            _output = newValue
        }
    }

    var input:AVCaptureInput? = nil {
        didSet {
            guard let mixer:AVMixer = mixer, oldValue != input else {
                return
            }
            if let oldValue:AVCaptureInput = oldValue {
                mixer.session.removeInput(oldValue)
            }
            if let input:AVCaptureInput = input, mixer.session.canAddInput(input) {
                mixer.session.addInput(input)
            }
        }
    }


    override init(mixer: AVMixer) {
        super.init(mixer: mixer)
        encoder.lockQueue = lockQueue
            if let orientation:AVCaptureVideoOrientation = DeviceUtil.videoOrientation(by: UIDevice.current.orientation) {
                self.orientation = orientation
                }
    }

#if os(iOS) || os(macOS)
    func attachCamera(_ camera:AVCaptureDevice?) throws {
        guard let mixer:AVMixer = mixer else {
            return
        }
        
        mixer.session.beginConfiguration()
        defer {
            mixer.session.commitConfiguration()
        }

        output = nil
        guard let camera:AVCaptureDevice = camera else {
            input = nil
            return
        }


        input = try AVCaptureDeviceInput(device: camera)
        mixer.session.addOutput(output)
        for connection in output.connections {
            guard let connection:AVCaptureConnection = connection as? AVCaptureConnection else {
                continue
            }
            if (connection.isVideoOrientationSupported) {
                connection.videoOrientation = orientation
            }
            if (connection.isVideoStabilizationSupported) {
                connection.preferredVideoStabilizationMode = .standard
            }
        }
        output.setSampleBufferDelegate(self, queue: lockQueue)

        fps = fps * 1
        position = camera.position
        drawable?.position = camera.position
    }
    func dispose() {
        drawable?.attachStream(nil)
        input = nil
        output = nil
    }
#else
    func dispose() {
        drawable?.attachStream(nil)
    }
#endif

    func effect(_ buffer:CVImageBuffer) -> CIImage {
        var image:CIImage = CIImage(cvPixelBuffer: buffer)
        for effect in effects {
            image = effect.execute(image)
        }
        return image
    }
    
    func registerEffect(_ effect:VisualEffect) -> Bool {
        objc_sync_enter(effects)
        defer {
            objc_sync_exit(effects)
        }
        if let _:Int = effects.index(of: effect) {
            return false
        }
        effects.append(effect)
        return true
    }

    func unregisterEffect(_ effect:VisualEffect) -> Bool {
        objc_sync_enter(effects)
        defer {
            objc_sync_exit(effects)
        }
        if let i:Int = effects.index(of: effect) {
            effects.remove(at: i)
            return true
        }
        return false
    }
}

extension VideoIOComponent: AVCaptureVideoDataOutputSampleBufferDelegate {
    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ captureOutput:AVCaptureOutput!, didOutputSampleBuffer sampleBuffer:CMSampleBuffer!, from connection:AVCaptureConnection!) {
        guard var buffer:CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let image:CIImage = effect(buffer)
        if !effects.isEmpty {
            #if os(macOS)
            // green edge hack for OSX
            buffer = CVPixelBuffer.create(image)!
            #endif
            context?.render(image, to: buffer)
        }
        encoder.encodeImageBuffer(
            buffer,
            presentationTimeStamp: sampleBuffer.presentationTimeStamp,
            duration: sampleBuffer.duration
        )
        drawable?.draw(image: image)
        mixer?.recorder.appendSampleBuffer(sampleBuffer, mediaType: AVMediaTypeVideo)
    }
}

extension VideoIOComponent: ClockedQueueDelegate {
    // MARK: ClockedQueueDelegate
    func queue(_ buffer: CMSampleBuffer) {
        drawable?.draw(image: CIImage(cvPixelBuffer: buffer.imageBuffer!))
    }
}
