import Foundation

/// Metadata only. Audio IO can mean monitoring, playback or a call; it is not proof
/// that an application is recording to a file. No audio samples are captured.
public struct OCRWorkActivity: Equatable, Sendable {
    public enum Audio: Equatable, Sendable { case quiet, input, output, inputAndOutput, unavailable }
    public var protectedApp: String?
    public var audio: Audio
    public init(protectedApp: String? = nil, audio: Audio = .quiet) {
        self.protectedApp = protectedApp; self.audio = audio
    }
}
