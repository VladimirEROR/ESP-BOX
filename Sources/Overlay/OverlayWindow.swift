import UIKit
import Foundation

// MARK: - Overlay Controller
class OverlayController {
    
    private var memory: MemoryManager
    private var baseAddress: UInt64
    private var overlayWindow: OverlayWindow?
    private var displayLink: CADisplayLink?
    private var entityParser: EntityParser?
    
    private weak var hackState: HackState?
    
    private var frameCount = 0
    private var lastFpsUpdate = Date()
    
    private var isRunning = false
    
    init(memoryManager: MemoryManager, baseAddress: UInt64, settings: HackState) {
        self.memory = memoryManager
        self.baseAddress = baseAddress
        self.hackState = settings
    }
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        
        entityParser = EntityParser(memory: memory, baseAddress: baseAddress)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.overlayWindow = OverlayWindow(frame: UIScreen.main.bounds)
            self.overlayWindow?.isHidden = false
            
            self.displayLink = CADisplayLink(
                target: self,
                selector: #selector(self.renderFrame)
            )
            self.displayLink?.add(to: .main, forMode: .common)
        }
    }
    
    func stop() {
        isRunning = false
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.displayLink?.invalidate()
            self.displayLink = nil
            self.overlayWindow?.isHidden = true
            self.overlayWindow = nil
        }
    }
    
    @objc private func renderFrame() {
        guard isRunning else { return }
        
        if let parser = entityParser {
            let entities = parser.parseEntities()
            
            // Sync settings from HackState to overlay
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
            
            // FPS counter
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
