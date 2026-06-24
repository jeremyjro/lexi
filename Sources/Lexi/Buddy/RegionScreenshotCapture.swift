import AppKit
import CoreGraphics
import ScreenCaptureKit

struct RegionScreenshot {
    let base64Data: String
    let mediaType: String
    let thumbnail: NSImage
    let pixelWidth: Int
    let pixelHeight: Int
}

enum RegionScreenshotError: LocalizedError {
    case emptyRegion
    case noDisplay
    case captureFailed
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .emptyRegion: return "The selected region was too small to capture."
        case .noDisplay: return "Couldn't find the display to capture."
        case .captureFailed: return "Screen capture failed. Check Screen Recording permission."
        case .encodeFailed: return "Couldn't encode the captured image."
        }
    }
}

/// Captures the dragged region (Feature 4 §7) via ScreenCaptureKit. Captures the
/// whole display the rect lives on, then crops to the rect in pixel space — robust
/// to Retina backing scale and multi-monitor origins — and downscales before send.
@MainActor
enum RegionScreenshotCapture {
    static let maxLongestEdge = 900
    static let minRegionSize: CGFloat = 8
    nonisolated static let mediaType = "image/jpeg"
    private static let maxEncodedBytes = 18_000
    private static let fallbackMaxEdges = [900, 720, 560, 420, 320, 240, 180, 140]
    private static let compressionFactors: [CGFloat] = [0.54, 0.4, 0.28, 0.2, 0.14]

    /// `regionInScreenCoordinates` is an AppKit global rect (bottom-left origin),
    /// as produced by the overlay's rubber-band selection.
    static func captureRegion(_ regionInScreenCoordinates: CGRect) async throws -> RegionScreenshot {
        guard regionInScreenCoordinates.width >= minRegionSize,
              regionInScreenCoordinates.height >= minRegionSize else {
            throw RegionScreenshotError.emptyRegion
        }

        guard let screen = screen(containing: regionInScreenCoordinates) else {
            throw RegionScreenshotError.noDisplay
        }

        let displayImage = try await captureDisplay(for: screen)

        // Map the AppKit rect into the captured image's pixel space using the
        // actual returned pixel dimensions (robust to any HiDPI rounding).
        let scaleX = CGFloat(displayImage.width) / screen.frame.width
        let scaleY = CGFloat(displayImage.height) / screen.frame.height
        let cropRect = CGRect(
            x: (regionInScreenCoordinates.minX - screen.frame.minX) * scaleX,
            y: (screen.frame.maxY - regionInScreenCoordinates.maxY) * scaleY,
            width: regionInScreenCoordinates.width * scaleX,
            height: regionInScreenCoordinates.height * scaleY
        ).integral

        let clamped = cropRect.intersection(CGRect(x: 0, y: 0, width: displayImage.width, height: displayImage.height))
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1,
              let cropped = displayImage.cropping(to: clamped) else {
            throw RegionScreenshotError.emptyRegion
        }

        return try encode(downscale(cropped, maxEdge: maxLongestEdge))
    }

    /// Fallback for "spoke but drew no region": grab the frontmost window so the
    /// spoken question still has something to ground on (section 15 default).
    static func captureFocusedWindow() async throws -> RegionScreenshot? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownBundleID = Bundle.main.bundleIdentifier
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        guard let window = content.windows.first(where: { window in
            guard let bundleID = window.owningApplication?.bundleIdentifier else { return false }
            guard bundleID != ownBundleID, bundleID == frontmostBundleID else { return false }
            return window.isOnScreen && window.frame.width > 100 && window.frame.height > 100
        }) else {
            return nil
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width))
        configuration.height = max(1, Int(window.frame.height))
        configuration.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return try encode(downscale(image, maxEdge: maxLongestEdge))
    }

    // MARK: - Capture

    private static func captureDisplay(for screen: NSScreen) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let displayID = screen.displayID,
              let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw RegionScreenshotError.noDisplay
        }

        // Never capture Lexi's own overlay/panel.
        let ownBundleID = Bundle.main.bundleIdentifier
        let ownWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == ownBundleID && ownBundleID != nil }

        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let configuration = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        configuration.width = max(1, Int((screen.frame.width * scale).rounded()))
        configuration.height = max(1, Int((screen.frame.height * scale).rounded()))
        configuration.showsCursor = false

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    // MARK: - Image processing

    private static func downscale(_ image: CGImage, maxEdge: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxEdge else { return image }

        let ratio = CGFloat(maxEdge) / CGFloat(longest)
        let targetWidth = max(1, Int((CGFloat(image.width) * ratio).rounded()))
        let targetHeight = max(1, Int((CGFloat(image.height) * ratio).rounded()))

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage() ?? image
    }

    private static func encode(_ image: CGImage) throws -> RegionScreenshot {
        var bestImage = image
        var bestData: Data?

        for maxEdge in fallbackMaxEdges {
            let candidateImage = downscale(image, maxEdge: maxEdge)
            let bitmap = NSBitmapImageRep(cgImage: candidateImage)
            for compressionFactor in compressionFactors {
                guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor]) else {
                    continue
                }
                bestImage = candidateImage
                bestData = data
                if data.count <= maxEncodedBytes {
                    return screenshot(image: candidateImage, data: data)
                }
            }
        }

        guard let bestData else {
            throw RegionScreenshotError.encodeFailed
        }
        return screenshot(image: bestImage, data: bestData)
    }

    private static func screenshot(image: CGImage, data: Data) -> RegionScreenshot {
        let thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        return RegionScreenshot(
            base64Data: data.base64EncodedString(),
            mediaType: mediaType,
            thumbnail: thumbnail,
            pixelWidth: image.width,
            pixelHeight: image.height
        )
    }

    private static func screen(containing rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })
            ?? NSScreen.screens.first(where: { $0.frame.intersects(rect) })
            ?? NSScreen.main
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let displayID = deviceDescription[key] as? CGDirectDisplayID {
            return displayID
        }
        if let number = deviceDescription[key] as? NSNumber {
            return CGDirectDisplayID(number.uint32Value)
        }
        return nil
    }
}
