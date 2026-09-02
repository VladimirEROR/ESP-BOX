import UIKit
import Foundation
import AVFoundation
import AVKit
import CoreVideo
import CoreMedia

// MARK: - Overlay States
enum OverlayState {
    case waiting
    case connecting
    case active
    case lost
}

// MARK: - PIP Overlay Controller
class OverlayController: NSObject {
    
    private var memory: MemoryManager
    private var baseAddress: UInt64 = 0
    private var displayLink: CADisplayLink?
    private var entityParser: EntityParser?
    
    private weak var hackState: HackState?
    
    private var frameCount = 0
    private var lastFpsUpdate = Date()
    
    private var isRunning = false
    
    private var pollTimer: Timer?
    private var pollCounter = 0
    
    private var currentState: OverlayState = .waiting
    
    // Background keep-alive
    private var audioPlayer: AVAudioPlayer?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    
    // PIP overlay
    private var pipController: AVPictureInPictureController?
    private var displayLayer: AVSampleBufferDisplayLayer?
    private var pipView: UIView?
    
    // Fallback window
    private var fallbackWindow: UIWindow?
    private var fallbackView: ESPOverlayView?
    
    // MARK: - Init
    init(memoryManager: MemoryManager, baseAddress: UInt64, settings: HackState) {
        self.memory = memoryManager
        self.baseAddress = baseAddress
        self.hackState = settings
        super.init()
    }
    
    // MARK: - Start
    func start() {
        guard !isRunning else { return }
        isRunning = true
        currentState = .waiting
        
        startBackgroundKeepAlive()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.setupPIPLayer()
            self.startDisplayLink()
            self.startPolling()
        }
    }
    
    // MARK: - Stop
    func stop() {
        isRunning = false
        currentState = .waiting
        
        stopPolling()
        stopDisplayLink()
        stopPIP()
        stopBackgroundKeepAlive()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.fallbackWindow?.isHidden = true
            self.fallbackWindow = nil
            self.fallbackView = nil
        }
    }
    
    // MARK: - Setup PIP Layer
    private func setupPIPLayer() {
        let layer = AVSampleBufferDisplayLayer()
        layer.frame = CGRect(x: 0, y: 0, width: 300, height: 150)
        layer.videoGravity = .resizeAspect
        
        // Hidden host view for the layer
        let hostView = UIView(frame: CGRect(x: -1000, y: -1000, width: 300, height: 150))
        hostView.layer.addSublayer(layer)
        
        // Add to a window so it has a rendering context
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
           let window = scene.windows.first {
            window.addSubview(hostView)
        }
        
        displayLayer = layer
        pipView = hostView
        
        if AVPictureInPictureController.isPictureInPictureSupported() {
            // iOS 15+ — use the initializer with content source
            if #available(iOS 15.0, *) {
                let sampleBufferPlaybackCoordinator = AVSampleBufferPlaybackCoordinator()
                // Not available — we need AVPlayerLayer approach
                
                // PIP with AVSampleBufferDisplayLayer isn't directly supported on iOS
                // We need to use AVPlayerLayer instead
                setupWithAVPlayer()
                return
            }
        } else {
            print("[VEX] PIP not supported — using window fallback")
            setupFallbackWindow()
        }
    }
    
    // MARK: - PIP with AVPlayerLayer (the correct way)
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    
    private func setupWithAVPlayer() {
        // Create a blank video item
        let videoUrl = generateBlankVideo()
        
        guard let url = videoUrl else {
            print("[VEX] Failed to generate video — using fallback")
            setupFallbackWindow()
            return
        }
        
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .varispeed
        
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.isMuted = true
        avPlayer.playImmediately(atRate: 0.1)
        
        player = avPlayer
        
        // Create player layer
        let layer = AVPlayerLayer(player: avPlayer)
        layer.frame = CGRect(x: 0, y: 0, width: 300, height: 150)
        layer.videoGravity = .resizeAspect
        
        // Hidden host view
        let hostView = UIView(frame: CGRect(x: -1000, y: -1000, width: 300, height: 150))
        hostView.layer.addSublayer(layer)
        
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
           let window = scene.windows.first {
            window.addSubview(hostView)
        }
        
        playerLayer = layer
        pipView = hostView
        
        // Loop the video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.player?.play()
        }
        
        // Create PIP controller with the player layer
        if #available(iOS 15.0, *) {
            let pip = AVPictureInPictureController(playerLayer: layer)
            pip.delegate = self
            pipController = pip
            
            print("[VEX] PIP supported — starting...")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startPIP()
            }
        }
    }
    
    // MARK: - Generate a tiny blank video for PIP
    private func generateBlankVideo() -> URL? {
        // Write a minimal MP4 file — just a black frame
        // We use AVAssetWriter for this
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "blank.mp4")
        
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            return nil
        }
        
        let width = 320
        let height = 160
        let fps: Int32 = 10
        
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        
        guard let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings) else {
            return nil
        }
        
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        
        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        // Write 30 frames (3 seconds at 10fps)
        for frame in 0..<30 {
            while !writerInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }
            
            var pixelBuffer: CVPixelBuffer?
            
            let attrs: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32ARGB,
                attrs as CFDictionary,
                &pixelBuffer
            )
            
            guard let buffer = pixelBuffer else { continue }
            
            // Draw a dark red frame
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            ) {
                context.setFillColor(UIColor(red: 0.08, green: 0.02, blue: 0.02, alpha: 1.0).cgColor)
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                
                // ESP-BOX text
                UIGraphicsPushContext(context)
                let font = UIFont.systemFont(ofSize: 24, weight: .black)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1.0)
                ]
                NSAttributedString(string: "ESP-BOX", attributes: attrs)
                    .draw(at: CGPoint(x: 80, y: 60))
                UIGraphicsPopContext()
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            
            let time = CMTime(value: CMTimeValue(frame), timescale: fps)
            adaptor.append(buffer, withPresentationTime: time)
        }
        
        writerInput.markAsFinished()
        writer.finishWriting {
            print("[VEX] Blank video generated: \(outputURL)")
        }
        
        // Wait for writing to complete
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            while writer.status == .writing {
                Thread.sleep(forTimeInterval: 0.05)
            }
            semaphore.signal()
        }
        semaphore.wait()
        
        if writer.status == .completed {
            return outputURL
        }
        
        print("[VEX] Video generation failed: \(writer.error?.localizedDescription ?? "unknown")")
        return nil
    }
    
    // MARK: - Start PIP
    private func startPIP() {
        guard let pip = pipController else { return }
        
        pip.startPictureInPicture()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, let pip = self.pipController else { return }
            
            if !pip.isPictureInPictureActive {
                print("[VEX] PIP didn't start — using window fallback")
                self.setupFallbackWindow()
            } else {
                print("[VEX] PIP ACTIVE — overlay floating on screen")
            }
        }
    }
    
    // MARK: - Stop PIP
    private func stopPIP() {
        pipController?.stopPictureInPicture()
        pipController = nil
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        displayLayer = nil
        pipView?.removeFromSuperview()
        pipView = nil
    }
    
    // MARK: - Fallback Window
    private func setupFallbackWindow() {
        guard fallbackWindow == nil else { return }
        
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }
        
        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = UIWindow.Level.alert + 100
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isUserInteractionEnabled = false
        
        let view = ESPOverlayView(frame: windowScene.coordinateSpace.bounds)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        
        window.rootViewController = OverlayViewController(overlayView: view)
        window.isHidden = false
        
        fallbackWindow = window
        fallbackView = view
    }
    
    // MARK: - Display Link
    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(renderFrame))
        displayLink?.preferredFramesPerSecond = 20
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    // MARK: - Polling
    private func startPolling() {
        stopPolling()
        
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkForMLBB()
        }
    }
    
    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
    
    private func checkForMLBB() {
        guard isRunning else { return }
        
        switch currentState {
        case .waiting, .lost:
            if let pid = ProcessFinder.findPID(byName: "legends")
                    ?? ProcessFinder.findPID(byName: "MLBB") {
                connectToMLBB(pid: pid)
            }
            
        case .active:
            if ProcessFinder.findPID(byName: "legends") == nil
                && ProcessFinder.findPID(byName: "MLBB") == nil {
                memory.detach()
                entityParser = nil
                currentState = .lost
                
                DispatchQueue.main.async {
                    self.hackState?.isConnected = false
                    self.hackState?.statusText = "Game Closed — Waiting..."
                    self.hackState?.mlbbPID = 0
                    self.hackState?.entityCount = 0
                    self.hackState?.currentFPS = 0
                }
            }
            
        case .connecting:
            break
        }
    }
    
    // MARK: - Connect
    private func connectToMLBB(pid: Int32) {
        currentState = .connecting
        
        DispatchQueue.main.async {
            self.hackState?.statusText = "Connecting to MLBB..."
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            guard self.memory.attach(to: pid) else {
                DispatchQueue.main.async {
                    self.currentState = .waiting
                }
                return
            }
            
            guard let base = self.memory.findModuleBase(named: "legends") else {
                self.memory.detach()
                DispatchQueue.main.async {
                    self.currentState = .waiting
                }
                return
            }
            
            self.baseAddress = base
            let parser = EntityParser(memory: self.memory, baseAddress: base)
            
            DispatchQueue.main.async {
                self.entityParser = parser
                self.currentState = .active
                
                self.hackState?.isConnected = true
                self.hackState?.statusText = "Connected"
                self.hackState?.mlbbPID = pid
                self.hackState?.baseAddress = base
            }
        }
    }
    
    // MARK: - Render
    @objc private func renderFrame() {
        guard isRunning else { return }
        
        // If fallback view exists, render there
        if let view = fallbackView {
            renderToView(view)
        }
        // If PIP is active, the video loops automatically
        // (we can't draw into PIP live — it plays a video)
        // For live updates we rely on the fallback window while in foreground
    }
    
    private func renderToView(_ view: ESPOverlayView) {
        switch currentState {
        case .waiting, .lost:
            pollCounter += 1
            view.updateWaitingTick(pollCounter)
            
        case .connecting:
            view.updateConnectingTick()
            
        case .active:
            if let parser = entityParser {
                let entities = parser.parseEntities()
                
                if let state = hackState {
                    view.settings = ESPSettings(
                        showBoxESP: state.showBoxESP,
                        showHealthBar: state.showHealthBar,
                        showHealthText: state.showHealthText,
                        showDistance: state.showDistance,
                        showLevel: state.showLevel,
                        showNames: state.showNames,
                        showSelf: false,
                        showDeadPlayers: false,
                        enemyColor: state.enemyColor,
                        allyColor: state.allyColor,
                        boxThickness: CGFloat(state.boxThickness),
                        boxGlow: CGFloat(state.boxGlow)
                    )
                }
                
                view.updateEntities(entities)
                updateFPS(entities.count)
            }
        }
    }
    
    private func updateFPS(_ count: Int) {
        frameCount += 1
        let now = Date()
        if now.timeIntervalSince(lastFpsUpdate) >= 1.0 {
            let fps = frameCount
            frameCount = 0
            lastFpsUpdate = now
            
            DispatchQueue.main.async {
                self.hackState?.currentFPS = fps
                self.hackState?.entityCount = count
            }
        }
    }
    
    // MARK: - Background Keep-Alive
    private func startBackgroundKeepAlive() {
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "ESP-BOX-KeepAlive") { [weak self] in
            self?.stopBackgroundKeepAlive()
        }
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            
            let sampleRate = 44100
            let dataSize = 44100 * 2
            
            var wavData = Data()
            
            func appendLE32(_ val: UInt32) {
                withUnsafeBytes(of: val.littleEndian) { wavData.append(contentsOf: $0) }
            }
            func appendLE16(_ val: UInt16) {
                withUnsafeBytes(of: val.littleEndian) { wavData.append(contentsOf: $0) }
            }
            
            wavData.append("RIFF".data(using: .utf8)!)
            appendLE32(UInt32(36 + dataSize))
            wavData.append("WAVE".data(using: .utf8)!)
            wavData.append("fmt ".data(using: .utf8)!)
            appendLE32(16)
            appendLE16(1)
            appendLE16(1)
            appendLE32(UInt32(sampleRate))
            appendLE32(UInt32(sampleRate * 2))
            appendLE16(2)
            appendLE16(16)
            wavData.append("data".data(using: .utf8)!)
            appendLE32(UInt32(dataSize))
            
            wavData.append(Data(repeating: 0, count: min(dataSize, 44100 * 2)))
            
            let tempFile = URL(fileURLWithPath: NSTemporaryDirectory() + "silence.wav")
            try wavData.write(to: tempFile)
            
            audioPlayer = try AVAudioPlayer(contentsOf: tempFile)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.volume = 0.0
            audioPlayer?.play()
            
            print("[VEX] Background keep-alive active")
        } catch {
            print("[VEX] Audio keep-alive failed: \(error)")
        }
    }
    
    private func stopBackgroundKeepAlive() {
        audioPlayer?.stop()
        audioPlayer = nil
        
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - PIP Delegate
extension OverlayController: AVPictureInPictureControllerDelegate {
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[VEX] PIP starting...")
    }
    
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[VEX] PIP started — overlay floating")
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("[VEX] PIP failed: \(error.localizedDescription) — using window fallback")
        DispatchQueue.main.async {
            self.setupFallbackWindow()
        }
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[VEX] PIP stopped")
    }
}

// MARK: - Overlay View Controller (fallback)
class OverlayViewController: UIViewController {
    
    private let overlayView: ESPOverlayView
    
    init(overlayView: ESPOverlayView) {
        self.overlayView = overlayView
        super.init(nibName: nil, bundle: nil)
        self.view = overlayView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    override var prefersStatusBarHidden: Bool { return true }
    override var prefersHomeIndicatorAutoHidden: Bool { return true }
}
