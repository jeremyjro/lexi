import Cocoa
import Vision
import ScreenCaptureKit

class ScreenCaptureManager {
    func captureScreenText() -> String {
        print("\n" + String(repeating: "=", count: 60))
        print("SCREEN CAPTURE: Capturing screenshot and OCRing text")
        print(String(repeating: "=", count: 60))
        
        // Capture screenshot of main screen
        guard let screen = NSScreen.main else {
            print("❌ No main screen found")
            return ""
        }
        
        let screenFrame = screen.frame
        let rect = CGRect(x: 0, y: 0, width: screenFrame.width, height: screenFrame.height)
        
        // Capture screenshot using CGDisplay
        guard let cgImage = CGDisplayCreateImage(CGMainDisplayID(), rect: rect) else {
            print("❌ Failed to capture screenshot")
            return ""
        }
        
        print("✅ Screenshot captured: \(Int(rect.width))x\(Int(rect.height))")
        
        // OCR the screenshot using Vision framework
        let text = performOCR(on: cgImage)
        
        print("✅ OCR complete: \(text.count) characters extracted")
        print("✅ OCR preview: \(String(text.prefix(200)))...")
        print(String(repeating: "=", count: 60) + "\n")
        
        return text
    }
    
    func captureScreenshot() -> Data? {
        print("\n" + String(repeating: "=", count: 60))
        print("SCREEN CAPTURE: Capturing screenshot for Vision API")
        print(String(repeating: "=", count: 60))
        
        guard let screen = NSScreen.main else {
            print("❌ No main screen found")
            return nil
        }
        
        let screenFrame = screen.frame
        let rect = CGRect(x: 0, y: 0, width: screenFrame.width, height: screenFrame.height)
        
        guard let cgImage = CGDisplayCreateImage(CGMainDisplayID(), rect: rect) else {
            print("❌ Failed to capture screenshot")
            return nil
        }
        
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        let imageData = bitmapRep.representation(using: .png, properties: [:])
        
        if let data = imageData {
            print("✅ Screenshot captured for Vision API: \(data.count) bytes")
            print("✅ Dimensions: \(Int(rect.width))x\(Int(rect.height))")
            print(String(repeating: "=", count: 60) + "\n")
        }
        
        return imageData
    }
    
    private func performOCR(on image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        
        do {
            try handler.perform([request])
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                print("❌ No text observations found")
                return ""
            }
            
            var recognizedText = ""
            for observation in observations {
                guard let topCandidate = observation.topCandidates(1).first else { continue }
                recognizedText += topCandidate.string + "\n"
            }
            
            return recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("❌ OCR failed: \(error)")
            return ""
        }
    }
}