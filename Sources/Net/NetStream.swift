import UIKit
import CoreImage
import Foundation
import AVFoundation

protocol NetStreamDrawable: class {
    var orientation:AVCaptureVideoOrientation { get set }

    func draw(image:CIImage)
    func attachStream(_ stream:NetStream?)
    func render(image: CIImage, to toCVPixelBuffer: CVPixelBuffer)
}

// MARK: -
open class NetStream: NSObject {
    public private(set) var mixer:AVMixer = AVMixer()
    public let lockQueue:DispatchQueue = DispatchQueue(label: "com.github.shogo4405.lf.NetStream.lock")

    deinit {
        metadata.removeAll()
        NotificationCenter.default.removeObserver(self)
    }

    open var metadata:[String:NSObject] = [:]

    open var orientation:AVCaptureVideoOrientation {
        get {
            return mixer.videoIO.orientation
        }
        set {
            self.mixer.videoIO.orientation = newValue
        }
    }
    open var syncOrientation:Bool = false {
        didSet {
            guard syncOrientation != oldValue else {
                return
            }
            if (syncOrientation) {
                NotificationCenter.default.addObserver(self, selector: #selector(NetStream.on(uiDeviceOrientationDidChange:)), name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
            } else {
                NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
            }
        }
    }
  

    open var audioSettings:[String:Any] {
        get {
            var audioSettings:[String:Any]!
            lockQueue.sync {
                audioSettings = self.mixer.audioIO.encoder.dictionaryWithValues(forKeys: AACEncoder.supportedSettingsKeys)
            }
            return  audioSettings
        }
        set {
            lockQueue.sync {
                self.mixer.audioIO.encoder.setValuesForKeys(newValue)
            }
        }
    }

    open var videoSettings:[String:Any] {
        get {
            var videoSettings:[String:Any]!
            lockQueue.sync {
                videoSettings = self.mixer.videoIO.encoder.dictionaryWithValues(forKeys: AVCEncoder.supportedSettingsKeys)
            }
            return videoSettings
        }
        set {
            lockQueue.sync {
                self.mixer.videoIO.encoder.setValuesForKeys(newValue)
            }
        }
    }

    open var captureSettings:[String:Any] {
        get {
            var captureSettings:[String:Any]!
            lockQueue.sync {
                captureSettings = self.mixer.dictionaryWithValues(forKeys: AVMixer.supportedSettingsKeys)
            }
            return captureSettings
        }
        set {
            lockQueue.sync {
                self.mixer.setValuesForKeys(newValue)
            }
        }
    }

    open var recorderSettings:[String:[String:Any]] {
        get {
            var recorderSettings:[String:[String:Any]]!
            lockQueue.sync {
                recorderSettings = self.mixer.recorder.outputSettings
            }
            return recorderSettings
        }
        set {
            lockQueue.sync {
                self.mixer.recorder.outputSettings = newValue
            }
        }
    }

    open func attachCamera(_ camera:AVCaptureDevice?) {
        lockQueue.async {
            self.mixer.videoIO.attachCamera(camera)
        }
    }

    open func attachAudio(_ audio:AVCaptureDevice?, automaticallyConfiguresApplicationAudioSession:Bool = true) {
        lockQueue.async {
            self.mixer.audioIO.attachAudio(audio,
                automaticallyConfiguresApplicationAudioSession: automaticallyConfiguresApplicationAudioSession
            )
        }
    }
  
  open var zoomFactor: CGFloat {
    get {
      return self.mixer.videoIO.zoomFactor
    }
  }
  
  open func setZoomFactor(_ zoomFactor: CGFloat, ramping: Bool = false) {
    self.mixer.videoIO.setZoomFactor(zoomFactor, ramping: ramping)
  }
  
    open func appendSampleBuffer(_ sampleBuffer:CMSampleBuffer, withType: CMSampleBufferType, options:[NSObject: AnyObject]? = nil) {
        switch withType {
        case .audio:
            mixer.audioIO.captureOutput(nil, didOutputSampleBuffer: sampleBuffer, from: nil)
        case .video:
            mixer.videoIO.captureOutput(nil, didOutputSampleBuffer: sampleBuffer, from: nil)
        }
    }

    open func registerEffect(video effect:VisualEffect) -> Bool {
        return mixer.videoIO.registerEffect(effect)
    }

    open func unregisterEffect(video effect:VisualEffect) -> Bool {
        return mixer.videoIO.unregisterEffect(effect)
    }

    open func setPointOfInterest(_ focus:CGPoint, exposure:CGPoint) {
        mixer.videoIO.focusPointOfInterest = focus
        mixer.videoIO.exposurePointOfInterest = exposure
    }

    open func dispose() {
        lockQueue.async {
            self.mixer.dispose()
        }
    }

  
    @objc private func on(uiDeviceOrientationDidChange:Notification) {
        if let orientation:AVCaptureVideoOrientation = DeviceUtil.videoOrientation(by: uiDeviceOrientationDidChange) {
            self.orientation = orientation
        }
    }
}
