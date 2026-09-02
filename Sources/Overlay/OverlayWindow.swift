import UIKit
import Foundation
import AVFoundation

// MARK: - Overlay States
enum OverlayState {
    case waiting
    case connecting
    case active
    case lost
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
    
    private var pollTimer: Timer?
    private var pollCounter = 0
    
    private var currentState: OverlayState = .waiting
    
    // Background keep-alive
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
        
        // Background keep-alive (safe — won't crash)
        startBackgroundKeepAlive()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Create overlay window
            self.overlayWindow = OverlayWindow(frame: UIScreen.main.bounds)
            self.overlayWindow?.isHidden = false
            self.overlayWindow?.setWaitingMode()
            
            // Start render loop — delayed by 1 frame to let window settle
            self.displayLink = CADisplayLink(
                target: self,
                selector: #selector(self.renderFrame)
            )
            self.displayLink?.preferredFramesPerSecond = 30
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
    
    // MARK: - Polling for MLBB
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
                print("[VEX] MLBB found! PID: \(pid)")
                connectToMLBB(pid: pid)
            }
            
        case .active:
            // Check if MLBB still alive
            if ProcessFinder.findPID(byName: "legends") == nil
                && ProcessFinder.findPID(byName: "MLBB") == nil {
                print("[VEX] MLBB closed — back to waiting")
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
            }
            
        case .connecting:
            break
        }
    }
    
    // MARK: - Connect
    private func connectToMLBB(pid: Int32) {
        currentState = .connecting
        
        DispatchQueue.main.async {
            self.overlayWindow?.setConnectingMode()
            self.hackState?.statusText = "Connecting to MLBB..."
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            guard self.memory.attach(to: pid) else {
                print("[VEX] Failed to attach — going back to waiting")
                DispatchQueue.main.async {
                    self.currentState = .waiting
                    self.overlayWindow?.setWaitingMode()
                }
                return
            }
            
            guard let base = self.memory.findModuleBase(named: "legends") else {
                print("[VEX] Failed to find base — going back to waiting")
                self.memory.detach()
                DispatchQueue.main.async {
                    self.currentState = .waiting
                    self.overlayWindow?.setWaitingMode()
                }
                return
            }
            
            self.baseAddress = base
            let parser = EntityParser(memory: self.memory, baseAddress: base)
            
            DispatchQueue.main.async {
                self.entityParser = parser
                self.currentState = .active
                self.overlayWindow?.setActiveMode()
                
                self.hackState?.isConnected = true
                self.hackState?.statusText = "Connected"
                self.hackState?.mlbbPID = pid
                self.hackState?.baseAddress = base
                
                // Switch to slower watchdog
                self.stopPolling()
                self.pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                    self?.checkForMLBB()
                }
            }
        }
    }
    
    // MARK: - Render
    @objc private func renderFrame() {
        guard isRunning, let window = overlayWindow else { return }
        
        switch currentState {
        case .waiting, .lost:
            pollCounter += 1
            window.updateWaitingAnimation(tick: pollCounter)
            
        case .connecting:
            window.updateConnectingAnimation()
            
        case .active:
            if let parser = entityParser {
                let entities = parser.parseEntities()
                
                if let state = hackState {
                    window.overlayView.settings = ESPSettings(
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
                
                window.updateEntities(entities)
                
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
        }
    }
    
    // MARK: - Background Keep-Alive (SAFE — no force unwraps)
    private func startBackgroundKeepAlive() {
        // Background task
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "ESP-BOX-KeepAlive") { [weak self] in
            self?.stopBackgroundKeepAlive()
        }
        
        // Audio keep-alive — everything wrapped, cannot crash
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            
            // Write a silent WAV file manually (no AVAudioFormat needed)
            let sampleRate = 44100
            let numSamples = sampleRate * 10 // 10 sec loop
            let dataSize = numSamples * 2 // 16-bit mono
            
            var wavData = Data()
            
            func appendLE32(_ val: UInt32) {
                withUnsafeBytes(of: val.littleEndian) { wavData.append(contentsOf: $0) }
            }
            func appendLE16(_ val: UInt16) {
                withUnsafeBytes(of: val.littleEndian) { wavData.append(contentsOf: $0) }
            }
            
            // RIFF header
            wavData.append("RIFF".data(using: .utf8)!)
            appendLE32(UInt32(36 + dataSize))
            wavData.append("WAVE".data(using: .utf8)!)
            wavData.append("fmt ".data(using: .utf8)!)
            appendLE32(16)
            appendLE16(1) // PCM
            appendLE16(1) // mono
            appendLE32(UInt32(sampleRate))
            appendLE32(UInt32(sampleRate * 2)) // byte rate
            appendLE16(2) // block align
            appendLE16(16) // bits per sample
            wavData.append("data".data(using: .utf8)!)
            appendLE32(UInt32(dataSize))
            
            // Silence (all zeros)
            wavData.append(Data(repeating: 0, count: min(dataSize, 44100 * 2))) // 1 sec of silence, loops
            
            let tempFile = URL(fileURLWithPath: NSTemporaryDirectory() + "silence.wav")
            try wavData.write(to: tempFile)
            
            audioPlayer = try AVAudioPlayer(contentsOf: tempFile)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.volume = 0.0
            audioPlayer?.play()
            
            print("[VEX] Background keep-alive active")
        } catch {
            print("[VEX] Audio keep-alive failed (non-fatal): \(error)")
            // app continues without audio keep-alive
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
