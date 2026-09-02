import UIKit
import Foundation

// MARK: - ESP Overlay View
class ESPOverlayView: UIView {
    
    private var entities: [ESPBox] = []
    
    var settings: ESPSettings = ESPSettings()
    
    private let lock = NSLock()
    
    // Overlay state
    private var overlayState: OverlayState = .waiting
    private var waitTick: Int = 0
    private var connectTick: Int = 0
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = .clear
        isOpaque = false
        clearsContextBeforeDrawing = true
        contentMode = .redraw
    }
    
    // MARK: - State management
    func setOverlayState(_ state: OverlayState) {
        lock.lock()
        overlayState = state
        entities.removeAll()
        lock.unlock()
        setNeedsDisplay()
    }
    
    func updateWaitingTick(_ tick: Int) {
        waitTick = tick
        setNeedsDisplay()
    }
    
    func updateConnectingTick() {
        connectTick += 1
        setNeedsDisplay()
    }
    
    func updateEntities(_ newEntities: [ESPBox]) {
        lock.lock()
        entities = newEntities
        lock.unlock()
        setNeedsDisplay()
    }
    
    // MARK: - Draw
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        
        switch overlayState {
        case .waiting:
            drawWaitingWidget(ctx: ctx)
            
        case .connecting:
            drawConnectingWidget(ctx: ctx)
            
        case .active:
            drawActiveESP(ctx: ctx)
            
        case .lost:
            drawWaitingWidget(ctx: ctx)
        }
    }
    
    // MARK: - Waiting Widget (floating on screen)
    private func drawWaitingWidget(ctx: CGContext) {
        let screenW = bounds.width
        let screenH = bounds.height
        
        // Widget position — top center
        let widgetW: CGFloat = 220
        let widgetH: CGFloat = 70
        let widgetX = (screenW - widgetW) / 2
        let widgetY: CGFloat = 60
        
        let widgetRect = CGRect(x: widgetX, y: widgetY, width: widgetW, height: widgetH)
        
        // Semi-transparent dark background
        ctx.setFillColor(UIColor(red: 0.08, green: 0.02, blue: 0.02, alpha: 0.85).cgColor)
        
        // Rounded rect path
        let path = CGPath(
            roundedRect: widgetRect,
            cornerWidth: 14,
            cornerHeight: 14,
            transform: nil
        )
        ctx.addPath(path)
        ctx.fillPath()
        
        // Red border
        ctx.addPath(path)
        ctx.setStrokeColor(UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.7).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokePath()
        
        // Pulsing indicator dot
        let pulse = (sin(Double(waitTick) * 0.15) + 1.0) / 2.0 // 0 to 1
        let dotAlpha = CGFloat(0.3 + pulse * 0.7)
        
        let dotX = widgetX + 20
        let dotY = widgetY + widgetH / 2
        let dotRect = CGRect(x: dotX - 5, y: dotY - 5, width: 10, height: 10)
        
        // Glow
        ctx.setShadow(offset: .zero, blur: 8, color: UIColor(red: 1, green: 0.3, blue: 0.3, alpha: dotAlpha).cgColor)
        ctx.setFillColor(UIColor(red: 1, green: 0.3, blue: 0.3, alpha: dotAlpha).cgColor)
        ctx.fillEllipse(in: dotRect)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        
        // Text
        let titleText = "ESP-BOX"
        let titleFont = UIFont.systemFont(ofSize: 14, weight: .heavy)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1.0)
        ]
        let titleStr = NSAttributedString(string: titleText, attributes: titleAttrs)
        titleStr.draw(at: CGPoint(x: dotX + 15, y: widgetY + 14))
        
        let subtitleText = "Waiting for MLBB..."
        let subtitleFont = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: UIColor(red: 0.7, green: 0.5, blue: 0.5, alpha: 0.8)
        ]
        let subtitleStr = NSAttributedString(string: subtitleText, attributes: subtitleAttrs)
        subtitleStr.draw(at: CGPoint(x: dotX + 15, y: widgetY + 34))
        
        // Animated dots
        let dotCount = (waitTick / 20) % 4
        var dots = ""
        for _ in 0..<dotCount {
            dots += "."
        }
        let dotsAttrs: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: UIColor(red: 1, green: 0.4, blue: 0.4, alpha: 0.6)
        ]
        let dotsStr = NSAttributedString(string: dots, attributes: dotsAttrs)
        dotsStr.draw(at: CGPoint(x: dotX + 15 + 130, y: widgetY + 34))
        
        // "Open Mobile Legends" instruction
        let hintText = "Open Mobile Legends to activate"
        let hintFont = UIFont.systemFont(ofSize: 9)
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: hintFont,
            .foregroundColor: UIColor(red: 0.5, green: 0.4, blue: 0.4, alpha: 0.6)
        ]
        let hintStr = NSAttributedString(string: hintText, attributes: hintAttrs)
        hintStr.draw(at: CGPoint(x: widgetX + 12, y: widgetY + widgetH - 16))
    }
    
    // MARK: - Connecting Widget
    private func drawConnectingWidget(ctx: CGContext) {
        let screenW = bounds.width
        
        // Same position as waiting
        let widgetW: CGFloat = 220
        let widgetH: CGFloat = 70
        let widgetX = (screenW - widgetW) / 2
        let widgetY: CGFloat = 60
        
        let widgetRect = CGRect(x: widgetX, y: widgetY, width: widgetW, height: widgetH)
        
        // Background
        let path = CGPath(
            roundedRect: widgetRect,
            cornerWidth: 14,
            cornerHeight: 14,
            transform: nil
        )
        ctx.addPath(path)
        ctx.setFillColor(UIColor(red: 0.08, green: 0.04, blue: 0.02, alpha: 0.85).cgColor)
        ctx.fillPath()
        
        // Green border
        ctx.addPath(path)
        ctx.setStrokeColor(UIColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 0.7).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokePath()
        
        // Spinning circle
        let spinAngle = CGFloat(connectTick) * 0.1
        let centerX = widgetX + 25
        let centerY = widgetY + widgetH / 2
        
        ctx.saveGState()
        ctx.translateBy(x: centerX, y: centerY)
        ctx.rotate(by: spinAngle)
        
        ctx.setStrokeColor(UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 0.9).cgColor)
        ctx.setLineWidth(2.5)
        ctx.setLineCap(.round)
        
        // Arc (3/4 circle)
        ctx.addArc(
            center: .zero,
            radius: 12,
            startAngle: 0,
            endAngle: CGFloat.pi * 1.5,
            clockwise: false
        )
        ctx.strokePath()
        ctx.restoreGState()
        
        // Text
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .heavy),
            .foregroundColor: UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1.0)
        ]
        NSAttributedString(string: "ESP-BOX", attributes: titleAttrs)
            .draw(at: CGPoint(x: centerX + 18, y: widgetY + 14))
        
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor(red: 0.5, green: 0.7, blue: 0.5, alpha: 0.8)
        ]
        NSAttributedString(string: "Connecting to MLBB...", attributes: subtitleAttrs)
            .draw(at: CGPoint(x: centerX + 18, y: widgetY + 34))
        
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor(red: 0.4, green: 0.5, blue: 0.4, alpha: 0.6)
        ]
        NSAttributedString(string: "Attaching to game process...", attributes: hintAttrs)
            .draw(at: CGPoint(x: widgetX + 12, y: widgetY + widgetH - 16))
    }
    
    // MARK: - Active ESP
    private func drawActiveESP(ctx: CGContext) {
        lock.lock()
        let currentEntities = entities
        lock.unlock()
        
        if currentEntities.isEmpty { return }
        
        for entity in currentEntities {
            if entity.isDead { continue }
            if entity.isSelf { continue }
            
            let color = entity.isEnemy ? settings.enemyColor : settings.allyColor
            
            if settings.showBoxESP {
                drawBox(ctx: ctx, entity: entity, color: color)
            }
            
            if settings.showHealthBar {
                drawHealthBar(ctx: ctx, entity: entity, color: color)
            }
            
            if settings.showDistance {
                drawDistance(ctx: ctx, entity: entity, color: color)
            }
            
            if settings.showLevel {
                drawLevel(ctx: ctx, entity: entity)
            }
        }
    }
    
    // MARK: - Box Drawing
    private func drawBox(ctx: CGContext, entity: ESPBox, color: UIColor) {
        let boxRect = CGRect(
            x: entity.screenX - entity.width / 2,
            y: entity.screenY - entity.height / 2,
            width: entity.width,
            height: entity.height
        )
        
        // Glow
        ctx.setShadow(offset: .zero, blur: settings.boxGlow, color: color.cgColor)
        
        // Border
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(settings.boxThickness)
        ctx.stroke(boxRect)
        
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        
        // Corner accents
        let cornerLen: CGFloat = min(10, entity.width / 4)
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: boxRect.minX, y: boxRect.minY + cornerLen),
             CGPoint(x: boxRect.minX, y: boxRect.minY),
             CGPoint(x: boxRect.minX + cornerLen, y: boxRect.minY)),
            (CGPoint(x: boxRect.maxX - cornerLen, y: boxRect.minY),
             CGPoint(x: boxRect.maxX, y: boxRect.minY),
             CGPoint(x: boxRect.maxX, y: boxRect.minY + cornerLen)),
            (CGPoint(x: boxRect.minX, y: boxRect.maxY - cornerLen),
             CGPoint(x: boxRect.minX, y: boxRect.maxY),
             CGPoint(x: boxRect.minX + cornerLen, y: boxRect.maxY)),
            (CGPoint(x: boxRect.maxX - cornerLen, y: boxRect.maxY),
             CGPoint(x: boxRect.maxX, y: boxRect.maxY),
             CGPoint(x: boxRect.maxX, y: boxRect.maxY - cornerLen))
        ]
        
        ctx.setLineWidth(settings.boxThickness + 0.5)
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.8).cgColor)
        
        for (start, corner, end) in corners {
            ctx.beginPath()
            ctx.move(to: start)
            ctx.addLine(to: corner)
            ctx.addLine(to: end)
            ctx.strokePath()
        }
    }
    
    // MARK: - Health Bar
    private func drawHealthBar(ctx: CGContext, entity: ESPBox, color: UIColor) {
        guard entity.healthMax > 0 else { return }
        
        let barWidth = entity.width + 4
        let barHeight: CGFloat = 4
        let barX = entity.screenX - entity.width / 2 - 2
        let barY = entity.screenY - entity.height / 2 - barHeight - 4
        
        let bgRect = CGRect(x: barX, y: barY, width: barWidth, height: barHeight)
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.7).cgColor)
        ctx.fill(bgRect)
        
        let healthRatio = CGFloat(entity.health) / CGFloat(entity.healthMax)
        let healthWidth = barWidth * min(healthRatio, 1.0)
        
        let healthColor: UIColor
        if healthRatio > 0.6 {
            healthColor = UIColor(red: 0.2, green: 0.9, blue: 0.2, alpha: 0.9)
        } else if healthRatio > 0.3 {
            healthColor = UIColor(red: 0.9, green: 0.9, blue: 0.2, alpha: 0.9)
        } else {
            healthColor = UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.9)
        }
        
        let healthRect = CGRect(x: barX, y: barY, width: healthWidth, height: barHeight)
        ctx.setFillColor(healthColor.cgColor)
        ctx.fill(healthRect)
        
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(0.5)
        ctx.stroke(bgRect)
        
        if settings.showHealthText {
            let hpText = "\(entity.health)/\(entity.healthMax)"
            drawText(
                ctx: ctx,
                text: hpText,
                at: CGPoint(x: barX, y: barY - 12),
                color: .white,
                fontSize: 8
            )
        }
    }
    
    // MARK: - Distance
    private func drawDistance(ctx: CGContext, entity: ESPBox, color: UIColor) {
        let distText = String(format: "%.0fm", entity.distance)
        drawText(
            ctx: ctx,
            text: distText,
            at: CGPoint(
                x: entity.screenX - entity.width / 2,
                y: entity.screenY + entity.height / 2 + 3
            ),
            color: color,
            fontSize: 9
        )
    }
    
    // MARK: - Level
    private func drawLevel(ctx: CGContext, entity: ESPBox) {
        let levelText = "Lv.\(entity.level)"
        drawText(
            ctx: ctx,
            text: levelText,
            at: CGPoint(
                x: entity.screenX + entity.width / 2 + 2,
                y: entity.screenY - entity.height / 2
            ),
            color: .systemYellow,
            fontSize: 9
        )
    }
    
    // MARK: - Text Helper
    private func drawText(
        ctx: CGContext,
        text: String,
        at point: CGPoint,
        color: UIColor,
        fontSize: CGFloat
    ) {
        let font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .strokeWidth: -2.0,
            .strokeColor: UIColor.black
        ]
        
        NSAttributedString(string: text, attributes: attributes).draw(at: point)
    }
}

// MARK: - ESP Settings
struct ESPSettings {
    var showBoxESP = true
    var showHealthBar = true
    var showHealthText = false
    var showDistance = true
    var showLevel = true
    var showNames = false
    var showSelf = false
    var showDeadPlayers = false
    
    var enemyColor = UIColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 0.9)
    var allyColor = UIColor(red: 0.25, green: 1.0, blue: 0.25, alpha: 0.9)
    
    var boxThickness: CGFloat = 1.5
    var boxGlow: CGFloat = 4.0
}
