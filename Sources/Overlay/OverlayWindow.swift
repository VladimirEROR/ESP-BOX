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
    private var overlayWindow: UIWindow?
    private var overlayView: ESPOverlayView!
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
    
    // MARK: - Start
    func start() {
        guard !isRunning else { return }
        isRunning = true
        currentState = .waiting
        
        startBackgroundKeepAlive()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.createOverlayWindow()
            
            self.displayLink = CADisplayLink(
                target: self,
                selector: #selector(self.renderFrame)
            )
            self.displayLink?.preferredFramesPerSecond = 30
            self.displayLink?.add(to: .main, forMode: .common)
            
            self.startPolling()
        }
    }
    
    // MARK: - Create overlay window attached to scene
    private func createOverlayWindow() {
        // Get the active window scene
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            print("[VEX] No window scene found!")
            return
        }
        
        // Create window WITH the scene
        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = UIWindow.Level.alert + 100
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isUserInteractionEnabled = false
        
        // Create the view
        overlayView = ESPOverlayView(frame: windowScene.coordinateSpace.bounds)
        overlayView.backgroundColor = .clear
        overlayView.isUserInteractionEnabled = false
        
        let rootVC = OverlayViewController(overlayView: overlayView)
        window.rootViewController = rootVC
        
        // Show it
        window.isHidden = false
        window.makeKeyAndVisible()
        // Bring back the original key window so SwiftUI stays in control
        // (don't steal key permanently)
        
        overlayWindow = window
        
        print("[VEX] Overlay window created on scene: \(windowScene)")
        
        // Set initial state
        overlayView.setOverlayState(.waiting)
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
            self.overlayWindow?.rootViewController = nil
            self.overlayWindow = nil
            self.overlayView = nil
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
            if ProcessFinder.findPID(byName: "legends") == nil
                && ProcessFinder.findPID(byName: "MLBB") == nil {
                print("[VEX] MLBB closed — back to waiting")
                memory.detach()
                entityParser = nil
                currentState = .lost
                
                DispatchQueue.main.async {
                    self.overlayView?.setOverlayState(.waiting)
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
            self.overlayView?.setOverlayState(.connecting)
            self.hackState?.statusText = "Connecting to MLBB..."
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            guard self.memory.attach(to: pid) else {
                print("[VEX] Failed to attach")
                DispatchQueue.main.async {
                    self.currentState = .waiting
                    self.overlayView?.setOverlayState(.waiting)
                }
                return
            }
            
            guard let base = self.memory.findModuleBase(named: "legends") else {
                print("[VEX] Failed to find base")
                self.memory.detach()
                DispatchQueue.main.async {
                    self.currentState = .waiting
                    self.overlayView?.setOverlayState(.waiting)
                }
                return
            }
            
            self.baseAddress = base
            let parser = EntityParser(memory: self.memory, baseAddress: base)
            
            DispatchQueue.main.async {
                self.entityParser = parser
                self.currentState = .active
                self.overlayView?.setOverlayState(.active)
                
                self.hackState?.isConnected = true
                self.hackState?.statusText = "Connected"
                self.hackState?.mlbbPID = pid
                self.hackState?.baseAddress = base
                
                self.stopPolling()
                self.pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                    self?.checkForMLBB()
                }
            }
        }
    }
    
    // MARK: - Render
    @objc private func renderFrame() {
        guard isRunning, let view = overlayView else { return }
        
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
                
                frameCount += 1
                let now = Date()
                if now.timeTimeIntervalSince(lastFpsUpdate) >= 1.0 {
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
            print("[VEX] Audio keep-alive failed (non-fatal): \(error)")
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

// MARK: - Overlay View Controller
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
