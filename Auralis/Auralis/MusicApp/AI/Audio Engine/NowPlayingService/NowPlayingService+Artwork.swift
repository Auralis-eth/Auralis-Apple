import Foundation
import MediaPlayer
import UIKit
import CoreGraphics
import ImageIO

@MainActor
extension NowPlayingService {
    static func detectRuntimeSupportedMIMEs() -> Set<String> {
        var supported: Set<String> = ["image/jpeg", "image/jpg", "image/pjpeg", "image/png"]
        if let utis = CGImageSourceCopyTypeIdentifiers() as? [String] {
            let set = Set(utis)
            if set.contains("org.webmproject.webp") { supported.insert("image/webp") }
            if set.contains("public.heic") { supported.insert("image/heic") }
            if set.contains("public.heif") { supported.insert("image/heif") }
        }
        return supported
    }

    func placeholderColor(for url: URL) -> UIColor {
        let s = url.absoluteString.unicodeScalars.reduce(UInt64(0)) { ($0 &* 1099511628211) ^ UInt64($1.value) }
        let hue = CGFloat((s % 360)) / 360.0
        return UIColor(hue: hue, saturation: 0.2, brightness: 0.9, alpha: 1.0)
    }

    func renderPlaceholderImage(pointSize: CGSize, baseColor: UIColor, scale: CGFloat, style: UIUserInterfaceStyle) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = max(1, scale)
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pointSize, format: format)
        let img = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: pointSize)
            baseColor.setFill()
            ctx.fill(rect)

            let cgCtx = ctx.cgContext
            let colors: [CGColor]
            if style == .dark {
                colors = [UIColor(white: 1.0, alpha: 0.06).cgColor,
                          UIColor(white: 0.0, alpha: 0.12).cgColor]
            } else {
                colors = [UIColor(white: 1.0, alpha: 0.12).cgColor,
                          UIColor(white: 0.0, alpha: 0.08).cgColor]
            }
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.0, 1.0]) {
                cgCtx.saveGState()
                cgCtx.addRect(rect)
                cgCtx.clip()
                let start = CGPoint(x: rect.midX, y: rect.minY)
                let end = CGPoint(x: rect.midX, y: rect.maxY)
                cgCtx.drawLinearGradient(gradient, start: start, end: end, options: [])
                cgCtx.restoreGState()
            }

            let inset: CGFloat = 0.5 / format.scale
            let innerRect = rect.insetBy(dx: inset, dy: inset)
            let path = UIBezierPath(roundedRect: innerRect, cornerRadius: min(pointSize.width, pointSize.height) * 0.08)
            path.lineWidth = max(0.5, 1.0 / format.scale)
            let strokeColor: UIColor = (style == .dark) ? UIColor(white: 1.0, alpha: 0.10) : UIColor(white: 0.0, alpha: 0.15)
            strokeColor.setStroke()
            path.stroke()
        }
        return img
    }

    func buildPlaceholderArtwork(for url: URL, scale: CGFloat) -> MPMediaItemArtwork {
        let boundsSize = CGSize(width: 512, height: 512)
        let color = placeholderColor(for: url)
        let pointSize = CGSize(width: max(1, 32), height: max(1, 32))

        let style = UIScreen.main.traitCollection.userInterfaceStyle
        let baseColor: UIColor
        if style == .dark {
            baseColor = color.withAlphaComponent(1.0)
        } else {
            baseColor = color.withAlphaComponent(1.0)
        }
        let img = renderPlaceholderImage(pointSize: pointSize, baseColor: baseColor, scale: scale, style: style)
        self.lastPlaceholderImage = img

        let artwork = MPMediaItemArtwork(boundsSize: boundsSize) { _ in
            return img
        }
        return artwork
    }

    func ensurePlaceholderAvailable(on control: ArtworkCacheControl) {
        if control.placeholder == nil {
            if let existing = self.lastPlaceholderImage {
                control.placeholder = existing
            } else {
                let size = CGSize(width: 32, height: 32)
                let style = UIScreen.main.traitCollection.userInterfaceStyle
                let neutralBase: UIColor = (style == .dark) ? UIColor(hue: 0.6, saturation: 0.18, brightness: 0.32, alpha: 1.0)
                                                            : UIColor(hue: 0.6, saturation: 0.10, brightness: 0.90, alpha: 1.0)
                let img = renderPlaceholderImage(pointSize: size, baseColor: neutralBase, scale: UIScreen.main.scale, style: style)
                self.lastPlaceholderImage = img
                control.placeholder = img
            }
        }
    }

    func enforceMimeSuppressionCap() {
        if suppressedMIMEUntil.count <= mimeSuppressionCap { return }
        let over = suppressedMIMEUntil.count - mimeSuppressionCap
        let sorted = suppressedMIMEUntil.sorted { $0.value < $1.value }
        for i in 0..<min(over, sorted.count) {
            suppressedMIMEUntil.removeValue(forKey: sorted[i].key)
        }
    }
}
