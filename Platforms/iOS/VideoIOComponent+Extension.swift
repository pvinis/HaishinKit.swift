import CoreMedia
import Foundation
import AVFoundation

extension VideoIOComponent {
    
    var zoomFactor: CGFloat {
        get {
            guard let device: AVCaptureDevice = (input as? AVCaptureDeviceInput)?.device
                else { return 0 }

            return device.videoZoomFactor
        }
    }

    func setZoomFactor(_ zoomFactor: CGFloat, ramping: Bool, withRate: Float) {
        guard let device:AVCaptureDevice = (input as? AVCaptureDeviceInput)?.device,
            1 <= zoomFactor && zoomFactor < device.activeFormat.videoMaxZoomFactor
            else { return }
        do {
            try device.lockForConfiguration()
            if (ramping) {
                device.ramp(toVideoZoomFactor: zoomFactor, withRate: withRate)
            } else {
                device.videoZoomFactor = zoomFactor
            }
            device.unlockForConfiguration()
        } catch let error {
            lfLogger?.error("while locking device for ramp: \(error)")
        }
    }
}
