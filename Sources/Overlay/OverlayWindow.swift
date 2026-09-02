import UIKit
import Foundation
import AVFoundation

// MARK: - Overlay States
enum OverlayState {
    case waiting       // waiting for MLBB to open
    case connecting    // found MLBB, attaching
    case active        // ESP running
    case lost          // was active, MLBB closed
}

// MARK: - Overlay Controller
class OverlayController {
    
    private var memory: MemoryManager
    private var baseAddress: UInt64 = 0
    private var overlayWindow: OverlayWindow?
    private var displayLink: CADisplayLink?
    private var entityParser: EntityParser?
    
    private weak var hackState: HackState?
    
    private var frameCount = 0
    private var lastFpsUpdate = Date()
    
    private var isRunning = false
    
    // Polling for MLBB process
    private var pollTimer: Timer?
    private var pollCounter = 0
    private let pollInterval: TimeInterval = 2.0
    
    // Current overlay state
    private var currentState: OverlayState = .waiting
    
    // Background keep-alive (silent audio)
    private var audioPlayer: AVAudioPlayer?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    
    init(memoryManager: MemoryManager, baseAddress: UInt64, settings: HackState) {
        self.memory = memoryManager
        self.baseAddress = baseAddress
        self.hackState = settings
    }
    
    // MARK: - Start (immediately — no MLBB needed)
    func start() {
        guard !isRunning else { return }
        isRunning = true
        currentState = .waiting
        
        // Start background keep-alive
        startBackgroundKeepAlive()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Create overlay window immediately
            self.overlayWindow = OverlayWindow(frame: UIScreen.main.bounds)
            self.overlayWindow?.isHidden = false
            self.overlayWindow?.setWaitingMode()
            
            // Start render loop
            self.displayLink = CADisplayLink(
                target: self,
                selector: #selector(self.renderFrame)
            )
            self.displayLink?.add(to: .main, forMode: .common)
            
            // Start polling for MLBB
            self.startPolling()
        }
    }
    
    // MARK: - Stop
    func stop() {
        isRunning = false
        currentState = .waiting
        
        stopPolling()
        stopBackgroundKeepAlive()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.displayLink?.invalidate()
            self.displayLink = nil
            self.overlayWindow?.isHidden = true
            self.overlayWindow = nil
        }
    }
    
    // MARK: - Polling for MLBB process
    private func startPolling() {
        stopPolling()
        
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
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
            // Look for MLBB process
            if let pid = ProcessFinder.findPID(byName: "legends")
                    ?? ProcessFinder.findPID(byName: "MLBB") {
                // Found it — attach
                print("[VEX] MLBB found! PID: \(pid)")
                connectToMLBB(pid: pid)
            }
            
        case .active:
            // Check if MLBB is still alive
            if ProcessFinder.findPID(byName: "legends")
                ?? ProcessFinder.findPID(byName: "MLBB") == nil {
                // MLBB closed
                print("[VEX] MLBB closed — going back to waiting")
                memory.detach()
                entityParser = nil
                currentState = .lost
                
                DispatchQueue.main.async {
                    self.overlayWindow?.setWaitingMode()
                    self.hackState?.isConnected = false
                    self.hackState?.statusText = "Game Closed — Waiting..."
                    self.hackState?.mlbbPID = 0
                    self.hackState?.entityCount = 0
                    self.hackState?.currentFPS = 0
                }
                
                // Restart polling
                startPolling()
            }
            
        case .connecting:
            break
        }
    }
    
    // MARK: - Connect to MLBB
    private func connectToMLBB(pid: Int32) {
        currentState = .connecting
        
        DispatchQueue.main.async {
            self.overlayWindow?.setConnectingMode()
            self.hackState?.statusText = "Connecting to MLBB..."
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Attach
            guard self.memory.attach(to: pid) else {
                print("[VEX] Failed to attach")
                DispatchQueue.main.async {
                    self.currentState = .waiting
                    self.overlayWindow?.setWaitingMode()
                }
                return
            }
            
            // Find module base
            guard let base = self.memory.findModuleBase(named: "legends") else {
                print("[VEX] Failed to find module base")
                self.memory.detach()
                DispatchQueue.main.async {
                    self.currentState = .waiting
                    self.overlayWindow?.setWaitingMode()
                }
                return
            }
            
            self.baseAddress = base
            
            // Create parser
            let parser = EntityParser(memory: self.memory, baseAddress: base)
            
            DispatchQueue.main.async {
                self.entityParser = parser
                self.currentState = .active
                self.overlayWindow?.setActiveMode()
                
                self.hackState?.isConnected = true
                self.hackState?.statusText = "Connected"
                self.hackState?.mlbbPID = pid
                self.hackState?.baseAddress = base
                
                // Stop polling — we're connected
                // (render loop checks if MLBB dies)
                self.stopPolling()
                
                // Start a slower watchdog (every 5s check if MLBB alive)
                self.pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                    self?.checkForMLBB()
                }
            }
        }
    }
    
    // MARK: - Render Frame
    @objc private func renderFrame() {
        guard isRunning else { return }
        
        switch currentState {
        case .waiting:
            // Draw waiting animation
            pollCounter += 1
            overlayWindow?.updateWaitingAnimation(tick: pollCounter)
            
        case .connecting:
            overlayWindow?.updateConnectingAnimation()
            
        case .active:
            // Full ESP rendering
            if let parser = entityParser {
                let entities = parser.parseEntities()
                
                // Sync settings
                if let state = hackState {
                    overlayWindow?.overlayView.settings = ESPSettings(
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
                
                overlayWindow?.updateEntities(entities)
                
                // FPS
                frameCount += 1
                let now = Date()
                if now.timeIntervalSince(lastFpsUpdate) >= 1.0 {
                    let fps = frameCount
                    frameCount = 0
                    lastFpsUpdate = now
                    
                    DispatchQueue.main.async {
                        self.hackState?.currentFPS = fps
                        self.hackState?.entityCount = entities.count
                    }
                }
            }
            
        case .lost:
            overlayWindow?.updateWaitingAnimation(tick: pollCounter)
        }
    }
    
    // MARK: - Background Keep-Alive
    private func startBackgroundKeepAlive() {
        // Request background time
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "ESP-BOX-KeepAlive") { [weak self] in
            self?.stopBackgroundKeepAlive()
        }
        
        // Play silent audio to keep alive indefinitely
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            
            // Generate 10 seconds of silence
            let sampleRate: Double = 44100
            let duration: Double = 10.0
            let numSamples = Int(sampleRate * duration)
            var samples = [Int16](repeating: 0, count: numSamples)
            
            let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: false)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples))!
            buffer.frameLength = AVAudioFrameCount(numSamples)
            
            let channelData = buffer.int16ChannelData![0]
            for i in 0..<numSamples {
                channelData[i] = samples[i]
            }
            
            let tempFile = URL(fileURLWithPath: NSTemporaryDirectory() + "silence.wav")
            let file = try AVAudioFile(forWriting: tempFile, settings: format.settings)
            try file.write(from: buffer)
            
            audioPlayer = try AVAudioPlayer(contentsOf: tempFile)
            audioPlayer?.numberOfLoops = -1 // infinite
            audioPlayer?.volume = 0.0 // silent
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

// MARK: - Overlay Window
class OverlayWindow: UIWindow {
    
    var overlayView: ESPOverlayView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        windowLevel = UIWindow.Level.alert + 100
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        clearsContextBeforeDrawing = true
        
        overlayView = ESPOverlayView(frame: UIScreen.main.bounds)
        overlayView.backgroundColor = .clear
        overlayView.isUserInteractionEnabled = false
        
        rootViewController = OverlayViewController(overlayView: overlayView)
    }
    
    // MARK: - Mode switching
    func setWaitingMode() {
        overlayView.setOverlayState(.waiting)
    }
    
    func setConnectingMode() {
        overlayView.setOverlayState(.connecting)
    }
    
    func setActiveMode() {
        overlayView.setOverlayState(.active)
    }
    
    func updateWaitingAnimation(tick: Int) {
        overlayView.updateWaitingTick(tick)
    }
    
    func updateConnectingAnimation() {
        overlayView.updateConnectingTick()
    }
    
    func updateEntities(_ entities: [ESPBox]) {
        overlayView.updateEntities(entities)
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return nil
    }
}

// MARK: - Overlay View Controller
class OverlayViewController: UIViewController {
    
    init(overlayView: ESPOverlayView) {
        super.init(nibName: nil, bundle: nil)
        self.view = overlayView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    override var prefersStatusBarHidden: Bool { return true }
    override var prefersHomeIndicatorAutoHidden: Bool { return true }
}
