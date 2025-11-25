import XCTest
import AVFoundation
@testable import DrumGateCore

final class GateProcessorTests: XCTestCase {
    func testGateReducesLowLevelSignal() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let frameCount: AVAudioFrameCount = 256
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            XCTFail("Failed to allocate buffer")
            return
        }
        buffer.frameLength = frameCount
        XCTAssertEqual(buffer.frameLength, frameCount)
        XCTAssertEqual(Int(buffer.format.channelCount), 1)
        if let channel = buffer.floatChannelData?[0] {
            for i in 0..<Int(frameCount) {
                channel[i] = 0.05 // -26 dBFS approx
            }
        }
        
        var gate = GateProcessor()
        let configured = gate.reconfigure(
            gate: GateSettings(threshold: -6, attack: 0.001, release: 0.05, active: true),
            sampleRate: Float(format.sampleRate),
            profile: DrumProfiles.profile(for: .snare)
        )
        XCTAssertTrue(configured, "Gate should configure when active is true")
        let beforeMax = (0..<Int(frameCount)).reduce(0 as Float) { acc, idx in
            max(acc, fabsf(buffer.floatChannelData![0][idx]))
        }
        gate.process(buffer: buffer)
        
        guard let processed = buffer.floatChannelData?[0] else {
            XCTFail("No channel data")
            return
        }
        let maxSample = (0..<Int(frameCount)).reduce(0 as Float) { acc, idx in
            max(acc, fabsf(processed[idx]))
        }
        XCTAssertLessThan(maxSample, beforeMax, "Gate should reduce signal")
        XCTAssertLessThan(maxSample, 0.02, "Gate should reduce signal below original level")
    }
}
