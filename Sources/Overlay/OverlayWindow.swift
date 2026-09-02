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
class OverlayController {
    
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
    
    // MARK: - Init
    init(memoryManager: MemoryManager, baseAddress: UInt64, settings: HackState) {
        self.memory = memoryManager
        self.baseAddress = baseAddress
        self.hackState = settings
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
    }
    
    // MARK: - Setup PIP Layer
    private func setupPIPLayer() {
        // Create the display layer for PIP
        let layer = AVSampleBufferDisplayLayer()
        layer.frame = CGRect(x: 0, y: 0, width: 300, height: 150)
        layer.videoGravity = .resizeAspect
        
        // Create a hidden host view for the layer
        let hostView = UIView(frame: CGRect(x: -1000, y: -1000, width: 300, height: 150))
        hostView.layer.addSublayer(layer)
        // Add to window so it has a rendering context
        if let window = UIApplication.shared.windows.first {
            window.addSubview(hostView)
        }
        
        displayLayer = layer
        pipView = hostView
        
        // Create PIP controller
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let pip = AVPictureInPictureController(contentLayer: layer)
            pip.delegate = self
            pipController = pip
            
            print("[VEX] PIP supported — attempting to start")
            
            // Start PIP after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startPIP()
            }
        } else {
            print("[VEX] PIP not supported on this device — falling back to window overlay")
            setupFallbackWindow()
        }
    }
    
    // MARK: - Start PIP
    private func startPIP() {
        guard let pip = pipController else { return }
        
        pip.startPictureInPicture()
        
        // Check after 1 second if it started
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, let pip = self.pipController else { return }
            
            if !pip.isPictureInPictureActive {
                print("[VEX] PIP didn't start — trying window fallback")
                self.setupFallbackWindow()
            } else {
                print("[VEX] PIP ACTIVE — overlay floating")
            }
        }
    }
    
    // MARK: - Stop PIP
    private func stopPIP() {
        pipController?.stopPictureInPicture()
        pipController = nil
        displayLayer = nil
        pipView?.removeFromSuperview()
        pipView = nil
    }
    
    // MARK: - Fallback Window (if PIP not available)
    private var fallbackWindow: UIWindow?
    private var fallbackView: ESPOverlayView?
    
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
        
        // Update the display layer to point to our view
        displayLayer = nil // PIP not available, render via view instead
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
        
        // Render current state into either PIP layer or fallback view
        if let view = fallbackView {
            // Fallback: render into ESPOverlayView
            renderToView(view)
        } else if let layer = displayLayer {
            // PIP: render into a pixel buffer and push to display layer
            renderToPIPLayer(layer)
        }
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
    
    private func renderToPIPLayer(_ layer: AVSampleBufferDisplayLayer) {
        // Create a pixel buffer with the ESP widget rendered into it
        let width = 300
        let height = 150
        
        var pixelBuffer: CVPixelBuffer?
        
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return }
        
        // Lock the buffer for drawing
        CVPixelBufferLockBaseAddress(buffer, [])
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return
        }
        
        // Clear
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        
        // Draw the widget based on state
        switch currentState {
        case .waiting, .lost:
            drawPIPWaiting(ctx: context, width: width, height: height)
            
        case .connecting:
            drawPIPConnecting(ctx: context, width: width, height: height)
            
        case .active:
            if let parser = entityParser {
                let entities = parser.parseEntities()
                drawPIPActive(ctx: context, width: width, height: height, entities: entities)
                updateFPS(entities.count)
            }
        }
        
        CVPixelBufferUnlockBaseAddress(buffer, [])
        
        // Convert to CMSampleBuffer and push to display layer
        pushToDisplayLayer(layer, pixelBuffer: buffer, width: width, height: height)
    }
    
    private func pushToDisplayLayer(_ layer: AVSampleBufferDisplayLayer, pixelBuffer: CVPixelBuffer, width: Int, height: Int) {
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        guard let format = formatDescription else { return }
        
        let timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 20),
            presentationTimeStamp: CMTime(value: CMTimeValue(pollCounter), timescale: 20),
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataIsReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        
        guard let sample = sampleBuffer else { return }
        
        // Push to the display layer
        if layer.status == .failed {
            layer.flush()
        }
        
        layer.enqueue(sample)
    }
    
    // MARK: - PIP Widget Drawing (small format 300x150)
    private func drawPIPWaiting(ctx: CGContext, width: Int, height: Int) {
        pollCounter += 1
        
        // Background — semi-transparent dark red
        let bgPath = CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
            cornerWidth: 20,
            cornerHeight: 20,
            transform: nil
        )
        ctx.addPath(bgPath)
        ctx.setFillColor(UIColor(red: 0.08, green: 0.02, blue: 0.02, alpha: 0.92).cgColor)
        ctx.fillPath()
        
        // Border
        ctx.addPath(bgPath)
        ctx.setStrokeColor(UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.8).cgColor)
        ctx.setLineWidth(2)
        ctx.strokePath()
        
        // Pulsing dot
        let pulse = (sin(Double(pollCounter) * 0.1) + 1.0) / 2.0
        let dotAlpha = CGFloat(0.3 + pulse * 0.7)
        
        let dotRect = CGRect(x: 20, y: CGFloat(height/2 - 8), width: 16, height: 16)
        ctx.setShadow(offset: .zero, blur: 8, color: UIColor(red: 1, green: 0.3, blue: 0.3, alpha: dotAlpha).cgColor)
        ctx.setFillColor(UIColor(red: 1, green: 0.3, blue: 0.3, alpha: dotAlpha).cgColor)
        ctx.fillEllipse(in: dotRect)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        
        // Text
        drawText(ctx: ctx, text: "ESP-BOX", at: CGPoint(x: 48, y: 40), size: 20, color: UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1))
        
        let dots = String(repeating: ".", count: (pollCounter / 10) % 4)
        drawText(ctx: ctx, text: "Waiting for MLBB\(dots)", at: CGPoint(x: 48, y: 68), size: 14, color: UIColor(red: 0.7, green: 0.5, blue: 0.5, alpha: 0.9))
        
        drawText(ctx: ctx, text: "Open Mobile Legends to activate", at: CGPoint(x: 20, y: height - 30), size: 11, color: UIColor(red: 0.5, green: 0.4, blue: 0.4, alpha: 0.7))
    }
    
    private func drawPIPConnecting(ctx: CGContext, width: Int, height: Int) {
        // Background — dark green
        let bgPath = CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
            cornerWidth: 20,
            cornerHeight: 20,
            transform: nil
        )
        ctx.addPath(bgPath)
        ctx.setFillColor(UIColor(red: 0.02, green: 0.08, blue: 0.02, alpha: 0.92).cgColor)
        ctx.fillPath()
        
        ctx.addPath(bgPath)
        ctx.setStrokeColor(UIColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 0.8).cgColor)
        ctx.setLineWidth(2)
        ctx.strokePath()
        
        // Spinning arc
        let spinAngle = CGFloat(pollCounter) * 0.15
        let centerX = CGFloat(width - 40)
        let centerY = CGFloat(height / 2)
        
        ctx.saveGState()
        ctx.translateBy(x: centerX, y: centerY)
        ctx.rotate(by: spinAngle)
        ctx.setStrokeColor(UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 0.9).cgColor)
        ctx.setLineWidth(3)
        ctx.setLineCap(.round)
        ctx.addArc(center: .zero, radius: 14, startAngle: 0, endAngle: .pi * 1.5, clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()
        
        drawText(ctx: ctx, text: "ESP-BOX", at: CGPoint(x: 20, y: 40), size: 20, color: UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1))
        drawText(ctx: ctx, text: "Connecting to MLBB...", at: CGPoint(x: 20, y: 68), size: 14, color: UIColor(red: 0.5, green: 0.7, blue: 0.5, alpha: 0.9))
    }
    
    private func drawPIPActive(ctx: CGContext, width: Int, height: Int, entities: [ESPBox]) {
        // Show mini status — PIP is too small for full ESP
        // This shows: connected status, player count, HP of enemies nearby
        
        let bgPath = CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
            cornerWidth: 20,
            cornerHeight: 20,
            transform: nil
        )
        ctx.addPath(bgPath)
        ctx.setFillColor(UIColor(red: 0.02, green: 0.08, blue: 0.02, alpha: 0.92).cgColor)
        ctx.fillPath()
        
        ctx.addPath(bgPath)
        ctx.setStrokeColor(UIColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 0.8).cgColor)
        ctx.setLineWidth(2)
        ctx.strokePath()
        
        drawText(ctx: ctx, text: "ESP ACTIVE", at: CGPoint(x: 20, y: 25), size: 16, color: UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1))
        drawText(ctx: ctx, text: "Players: \(entities.filter({ !$0.isSelf }).count)", at: CGPoint(x: 20, y: 50), size: 14, color: .white)
        
        // Enemy HP list (up to 3 closest enemies)
        let enemies = entities.filter({ $0.isEnemy && !$0.isDead }).sorted { $0.distance < $1.distance }
        
        var yPos = 75
        for enemy in enemies.prefix(3) {
            let hpRatio = CGFloat(enemy.health) / CGFloat(max(enemy.healthMax, 1))
            
            // HP bar
            let barWidth = CGFloat(width - 80)
            let barRect = CGRect(x: 70, y: yPos, width: barWidth, height: 6)
            ctx.setFillColor(UIColor.black.withAlphaComponent(0.5).cgColor)
            ctx.fill(barRect)
            
            let hpColor = hpRatio > 0.5 
                ? UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.9)
                : UIColor(red: 0.9, green: 0.6, blue: 0.1, alpha: 0.9)
            
            let hpRect = CGRect(x: 70, y: yPos, width: barWidth * hpRatio, height: 6)
            ctx.setFillColor(hpColor.cgColor)
            ctx.fill(hpRect)
            
            // Distance
            drawText(ctx: ctx, text: String(format: "%.0fm", enemy.distance), at: CGPoint(x: 20, y: yPos - 4), size: 12, color: .white)
            
            // HP text
            drawText(ctx: ctx, text: "\(enemy.health)", at: CGPoint(x: Int(width) - 40, y: yPos - 4), size: 12, color: .white)
            
            yPos += 18
        }
    }
    
    private func drawText(ctx: CGContext, text: String, at point: CGPoint, size: CGFloat, color: UIColor) {
        let font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        
        UIGraphicsPushContext(ctx)
        NSAttributedString(string: text, attributes: attrs).draw(at: point)
        UIGraphicsPopContext()
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

// MARK: - PIP Controller Delegate
extension OverlayController: AVPictureInPictureControllerDelegate {
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[VEX] PIP starting...")
    }
    
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[VEX] PIP started — overlay is now floating")
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("[VEX] PIP failed: \(error.localizedDescription) — falling back to window")
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
