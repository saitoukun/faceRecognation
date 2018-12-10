
import UIKit
import AVFoundation
import Vision

// https://tech.recruit-mp.co.jp/mobile/ios-11-vision-framework/ 参考
extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .upMirrored:
            self = .upMirrored
        case .down:
            self = .down
        case .downMirrored:
            self = .downMirrored
        case .left:
            self = .left
        case .leftMirrored:
            self = .leftMirrored
        case .right:
            self = .right
        case .rightMirrored:
            self = .rightMirrored
        }
    }
}

// 画面上に認識矩形を描画するための custom view
class VisualizeRectanlgesView: UIView {
    
    var rectangles: [CGRect] = [] {
        didSet {
            setNeedsDisplay()
        }
    }
    
    private func convertedPoint(point: CGPoint, to size: CGSize) -> CGPoint {
        // view 上の座標に変換 座標系変換のためY 軸方向に反転
        return CGPoint(x: point.x * size.width, y: (1.0 - point.y) * size.height)
    }
    
    private func convertedRect(rect: CGRect, to size: CGSize) -> CGRect {
        // view 上の長方形に変換する 座標系変換のため、 Y 軸方向に反転
        return CGRect(x: rect.minX * size.width, y: (1.0 - rect.maxY) * size.height, width: rect.width * size.width, height: rect.height * size.height)
    }
    
    override func draw(_ rect: CGRect) {
        backgroundColor = UIColor.clear
        
        UIColor.red.setStroke()
        
        for rect in rectangles {
            let path = UIBezierPath(rect: convertedRect(rect: rect, to: frame.size))
            path.lineWidth = 2
            path.stroke()
        }
    }
}

class ViewController: UIViewController {
    
    @IBOutlet private weak var imageView: UIImageView!
    
    private let visualizeRectanglesView = VisualizeRectanlgesView(frame: CGRect.zero)
    private var session: AVCaptureSession?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        view.addSubview(visualizeRectanglesView)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setupAndStartAVCaptureSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        stopAVCaptureSession()
        super.viewWillDisappear(animated)
    }
    
    private func setupAndStartAVCaptureSession() {
        session = AVCaptureSession()
        session?.sessionPreset = AVCaptureSession.Preset.photo
        
        let device = AVCaptureDevice.default(for: AVMediaType.video)
        let input = try! AVCaptureDeviceInput(device: device!)
        session?.addInput(input)
        
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA)]
        output.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.default))
        session?.addOutput(output)
        
        session?.startRunning()
    }
    
    private func stopAVCaptureSession() {
        session?.stopRunning()
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    // UIViewController#view 上の画像表示領域 (frame) を計算する
    private func imageFrameOnViewController(uiImage: UIImage) -> CGRect {
        let imageAspectRatio = uiImage.size.width / uiImage.size.height
        let viewAspectRatio = imageView.bounds.width / imageView.bounds.height
        if imageAspectRatio > viewAspectRatio {
            let ratio = imageView.bounds.width / uiImage.size.width
            return CGRect(
                x: imageView.frame.minX + 0,
                y: imageView.frame.minY + (imageView.bounds.height - ratio * uiImage.size.height) * 0.5,
                width: imageView.bounds.width,
                height: ratio * uiImage.size.height)
        } else {
            let ratio = view.bounds.height / uiImage.size.height
            return CGRect(
                x: imageView.frame.minX + (imageView.bounds.width - ratio * uiImage.size.width) * 0.5,
                y: imageView.frame.minY + 0,
                width: ratio * uiImage.size.width,
                height: imageView.bounds.height)
        }
    }
    
    func sampleBufferToUIImage(sampleBuffer: CMSampleBuffer, with orientation: UIInterfaceOrientation) -> UIImage {
        let  imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        CVPixelBufferLockBaseAddress(imageBuffer!, CVPixelBufferLockFlags.readOnly)
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer!)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer!)
        let width = CVPixelBufferGetWidth(imageBuffer!)
        let height = CVPixelBufferGetHeight(imageBuffer!)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        let context = CGContext(data: baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)
        let quartzImage = context?.makeImage()
        CVPixelBufferUnlockBaseAddress(imageBuffer!, CVPixelBufferLockFlags.readOnly)
        
        // rear カメラの sampleBuffer は landscapeRight の向きなので、ここで orientation を補正
        if orientation == .landscapeLeft {
            return UIImage(cgImage: quartzImage!, scale: 1.0, orientation: .down)
        } else if orientation == .landscapeRight {
            return UIImage(cgImage: quartzImage!, scale: 1.0, orientation: .up)
        } else {
            return UIImage(cgImage: quartzImage!, scale: 1.0, orientation: .right)
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let uiImage = sampleBufferToUIImage(sampleBuffer: sampleBuffer, with: UIApplication.shared.statusBarOrientation)
        let orientation = CGImagePropertyOrientation(uiImage.imageOrientation)
        let ciImage = CIImage(image: uiImage)!
        
        // UI の変更はメインスレッドで実行
        DispatchQueue.main.async { [weak self] in
            if let frame = self?.imageFrameOnViewController(uiImage: uiImage) {
                self?.imageView.image = uiImage
                self?.visualizeRectanglesView.frame = frame
            }
        }
        
        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: orientation)
        let request = VNDetectFaceRectanglesRequest() { request, error in
            // 顔ブロックの矩形を取得
            let rects = request.results?.flatMap { result -> [CGRect] in
                guard let observation = result as? VNFaceObservation else { return [] }
                return [observation.boundingBox]
                } ?? []
        
            // UI の変更はメインスレッドで実行
            DispatchQueue.main.async { [weak self] in
                self?.visualizeRectanglesView.rectangles = rects
            }
        }
        
        try! handler.perform([request])
    }
    
    
}
