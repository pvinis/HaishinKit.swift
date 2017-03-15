import CoreImage
import Foundation
import AVFoundation

final class VideoIOComponent: IOComponent {
    let lockQueue:DispatchQueue = DispatchQueue(label: "com.github.shogo4405.lf.VideoIOComponent.lock")
    var drawable:NetStreamDrawable?
    var formatDescription:CMVideoFormatDescription? {
        didSet {
            decoder.formatDescription = formatDescription
        }
    }
    lazy var encoder:AVCEncoder = AVCEncoder()
    lazy var decoder:AVCDecoder = AVCDecoder()
    lazy var queue:ClockedQueue = {
        let queue:ClockedQueue = ClockedQueue()
        queue.delegate = self
        return queue
    }()
    fileprivate var effects:[VisualEffect] = []

    var fps:Float64 = AVMixer.defaultFPS {
        didSet {
            guard
                let device:AVCaptureDevice = (input as? AVCaptureDeviceInput)?.device,
                let data = DeviceUtil.getActualFPS(fps, device: device) else {
                return
            }

            fps = data.fps
            encoder.expectedFPS = data.fps
            //logger.info("\(data)")

            do {
                try device.lockForConfiguration()
                device.activeVideoMinFrameDuration = data.duration
                device.activeVideoMaxFrameDuration = data.duration
                device.unlockForConfiguration()
            } catch let error as NSError {
                //logger.error("while locking device for fps: \(error)")
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
                //logger.warning("focusMode(\(focusMode.rawValue)) is not supported")
                return
            }
            do {
                try device.lockForConfiguration()
                device.focusMode = focusMode
                device.unlockForConfiguration()
            }
            catch let error as NSError {
                //logger.error("while locking device for autofocus: \(error)")
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
            } catch let error as NSError {
                //logger.error("while locking device for focusPointOfInterest: \(error)")
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
            } catch let error as NSError {
                //logger.error("while locking device for exposurePointOfInterest: \(error)")
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
                //logger.warning("exposureMode(\(exposureMode.rawValue)) is not supported")
                return
            }
            do {
                try device.lockForConfiguration()
                device.exposureMode = exposureMode
                device.unlockForConfiguration()
            } catch let error as NSError {
                //logger.error("while locking device for autoexpose: \(error)")
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

    fileprivate(set) var input:AVCaptureInput? = nil {
        didSet {
            guard oldValue != input else {
                return
            }
            if let oldValue:AVCaptureInput = oldValue {
                mixer?.session.removeInput(oldValue)
            }
            if let input:AVCaptureInput = input {
                mixer?.session.addInput(input)
            }
        }
    }

    #if !os(OSX)
    fileprivate(set) var screen:ScreenCaptureSession? = nil {
        didSet {
            guard oldValue != screen else {
                return
            }
            if let oldValue:ScreenCaptureSession = oldValue {
                oldValue.delegate = nil
            }
            if let screen:ScreenCaptureSession = screen {
                screen.delegate = self
            }
        }
    }
    #endif

    override init(mixer: AVMixer) {
        super.init(mixer: mixer)
        encoder.lockQueue = lockQueue
        decoder.delegate = self
            if let orientation:AVCaptureVideoOrientation = DeviceUtil.videoOrientation(by: UIDevice.current.orientation) {
                self.orientation = orientation
                }
        
    }

    func attachCamera(_ camera:AVCaptureDevice?) {
        mixer?.session.beginConfiguration()
        output = nil
        guard let camera:AVCaptureDevice = camera else {
            input = nil
            mixer?.session.commitConfiguration()
            return
        }
        screen = nil
        do {
            input = try AVCaptureDeviceInput(device: camera)
            mixer?.session.addOutput(output)
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
        } catch let error as NSError {
            //logger.error("\(error)")
        }

        fps = fps * 1
        position = camera.position
        drawable?.position = camera.position
        mixer?.session.commitConfiguration()
    }

  
    func attachScreen(_ screen:ScreenCaptureSession?, useScreenSize:Bool = true) {
        guard let screen:ScreenCaptureSession = screen else {
            self.screen?.stopRunning()
            self.screen = nil
            return
        }
        input = nil
        output = nil
        if (useScreenSize) {
            encoder.setValuesForKeys([
                "width": screen.attributes["Width"]!,
                "height": screen.attributes["Height"]!,
            ])
        }
        self.screen = screen
    }
  
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

  var zoomFactor: CGFloat {
    get {
      guard let device:AVCaptureDevice = (input as? AVCaptureDeviceInput)?.device else { return 0 }
      return device.videoZoomFactor
    }
  }
  
  func setZoomFactor(_ zoomFactor: CGFloat, ramping: Bool) {
    guard let device:AVCaptureDevice = (input as? AVCaptureDeviceInput)?.device,
          1 <= zoomFactor && zoomFactor < device.activeFormat.videoMaxZoomFactor else {
      return
    }
    do {
      try device.lockForConfiguration()
      if (ramping) {
        device.ramp(toVideoZoomFactor: zoomFactor, withRate: 2.0)
      } else {
        device.videoZoomFactor = zoomFactor
      }
      device.unlockForConfiguration()
    } catch let error as NSError {
          //logger.error("while locking device for ramp: \(error)")
    }
  }

    func dispose() {
        drawable?.attachStream(nil)
        input = nil
        output = nil
    }
}

extension VideoIOComponent: AVCaptureVideoDataOutputSampleBufferDelegate {
    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ captureOutput:AVCaptureOutput!, didOutputSampleBuffer sampleBuffer:CMSampleBuffer!, from connection:AVCaptureConnection!) {
        guard var buffer:CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let image:CIImage = effect(buffer)
        if (!effects.isEmpty) {

          drawable?.render(image: image, to: buffer)
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

extension VideoIOComponent: VideoDecoderDelegate {
    // MARK: VideoDecoderDelegate
    func sampleOutput(video sampleBuffer:CMSampleBuffer) {
        queue.enqueue(sampleBuffer)
    }
}

extension VideoIOComponent: ClockedQueueDelegate {
    // MARK: ClockedQueueDelegate
    func queue(_ buffer: CMSampleBuffer) {
        drawable?.draw(image: CIImage(cvPixelBuffer: buffer.imageBuffer!))
    }
}

extension VideoIOComponent: ScreenCaptureOutputPixelBufferDelegate {
    // MARK: ScreenCaptureOutputPixelBufferDelegate
    func didSet(size: CGSize) {
        lockQueue.async {
            self.encoder.width = Int32(size.width)
            self.encoder.height = Int32(size.height)
        }
    }
    func output(pixelBuffer:CVPixelBuffer, withPresentationTime:CMTime) {
        if (!effects.isEmpty) {
            drawable?.render(image: effect(pixelBuffer), to: pixelBuffer)
        }
        encoder.encodeImageBuffer(
            pixelBuffer,
            presentationTimeStamp: withPresentationTime,
            duration: kCMTimeInvalid
        )
        mixer?.recorder.appendPixelBuffer(pixelBuffer, withPresentationTime: withPresentationTime)
    }
}
