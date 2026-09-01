import UIKit
import Foundation

// MARK: - ESP Overlay View
class ESPOverlayView: UIView {
    
    private var entities: [ESPBox] = []
    
    var settings: ESPSettings = ESPSettings()
    
    private let lock = NSLock()
    
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
    
    func updateEntities(_ newEntities: [ESPBox]) {
        lock.lock()
        entities = newEntities
        lock.unlock()
        setNeedsDisplay()
    }
    
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        lock.lock()
        let currentEntities = entities
        lock.unlock()
        
        if currentEntities.isEmpty { return }
        
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        
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
        
        // Glow effect
        ctx.setShadow(
            offset: CGSize(width: 0, height: 0),
            blur: settings.boxGlow,
            color: color.cgColor
        )
        
        // Border
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(settings.boxThickness)
        ctx.stroke(boxRect)
        
        // Clear shadow
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        
        // Corner accents
        let cornerLen: CGFloat = min(10, entity.width / 4)
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            // Top-left
            (CGPoint(x: boxRect.minX, y: boxRect.minY + cornerLen),
             CGPoint(x: boxRect.minX, y: boxRect.minY),
             CGPoint(x: boxRect.minX + cornerLen, y: boxRect.minY)),
            // Top-right
            (CGPoint(x: boxRect.maxX - cornerLen, y: boxRect.minY),
             CGPoint(x: boxRect.maxX, y: boxRect.minY),
             CGPoint(x: boxRect.maxX, y: boxRect.minY + cornerLen)),
            // Bottom-left
            (CGPoint(x: boxRect.minX, y: boxRect.maxY - cornerLen),
             CGPoint(x: boxRect.minX, y: boxRect.maxY),
             CGPoint(x: boxRect.minX + cornerLen, y: boxRect.maxY)),
            // Bottom-right
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
        
        // Background
        let bgRect = CGRect(x: barX, y: barY, width: barWidth, height: barHeight)
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.7).cgColor)
        ctx.fill(bgRect)
        
        // Health fill
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
        
        // Border
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(0.5)
        ctx.stroke(bgRect)
        
        // HP text
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
        let font = UIFont.monospacedDigitSystemFont(
           (ofSize: fontSize,
             weight: .medium
            )
        )
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .strokeWidth: -2.0,
            .strokeColor: UIColor.black
        ]
        
        let attributedString = NSAttributedString(
            string: text,
            attributes: attributes
        )
        
        attributedString.draw(at: point)
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
