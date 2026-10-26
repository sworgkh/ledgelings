import AVFoundation
import AppKit
import LedgelingsCore

/// The microphone for dictation (§7.13): AVAudioEngine's input, turned into
/// 16 kHz mono 16-bit samples as it comes and kept in memory only. Nothing is
/// written to disk; the samples are dropped once the model has them. The level
/// of the last moment is read for the creature's meter.
final class DictationRecorder: @unchecked Sendable {
    enum Failure: Error, CustomStringConvertible {
        case noMicrophone, notAllowed, couldNotStart(String)
        var description: String {
            switch self {
            case .noMicrophone: Dictation.Trouble.noMicrophone.line
            case .notAllowed: Dictation.Trouble.microphoneRefused.line
            case .couldNotStart(let why): tr("The microphone would not start: %@", why)
            }
        }
    }

    /// The Microphone permission for this build: granted, refused, or not asked yet.
    enum Permission { case granted, refused, notAsked }

    static var permission: Permission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notAsked
        default: .refused
        }
    }

    /// Asks macOS; once refused it no longer asks, so System Settings opens on the switch instead.
    @discardableResult
    static func askForPermission() async -> Bool {
        if permission == .notAsked { return await AVCaptureDevice.requestAccess(for: .audio) }
        if permission == .refused, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            await MainActor.run { _ = NSWorkspace.shared.open(url) }
        }
        return permission == .granted
    }

    /// The microphone macOS would record from, by name, or nil when there is none.
    static var microphoneName: String? { AVCaptureDevice.default(for: .audio)?.localizedName }

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Int16] = []
    private var lastRMS: Float = 0
    private var converter: AVAudioConverter?
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(Dictation.sampleRate), channels: 1, interleaved: true)!

    /// Starts listening. Throws when there is no microphone or no permission.
    func start() throws {
        guard Self.permission == .granted else { throw Failure.notAllowed }
        guard Self.microphoneName != nil else { throw Failure.noMicrophone }
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw Failure.noMicrophone }
        // The first channel only: a stereo interface's left input is the voice.
        guard let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: mono, to: target) else { throw Failure.couldNotStart("no converter") }
        self.converter = converter
        lock.withLock { samples = []; samples.reserveCapacity(Dictation.sampleRate * 30); lastRMS = 0 }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in self?.heard(buffer, mono: mono) }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            throw Failure.couldNotStart(error.localizedDescription)
        }
    }

    /// Stops listening and hands back everything heard; the recorder keeps nothing.
    func stop() -> [Int16] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return lock.withLock {
            let heard = samples
            samples = []
            lastRMS = 0
            return heard
        }
    }

    /// How loud the last moment was, 0 to 1.
    var level: Double { Dictation.level(rms: lock.withLock { lastRMS }) }

    /// Seconds heard so far.
    var seconds: Double { Double(lock.withLock { samples.count }) / Double(Dictation.sampleRate) }

    /// On the audio thread: the level, and the first channel converted to 16 kHz.
    private func heard(_ buffer: AVAudioPCMBuffer, mono: AVAudioFormat) {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0,
              let one = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: buffer.frameLength) else { return }
        let count = Int(buffer.frameLength)
        one.frameLength = buffer.frameLength
        one.floatChannelData![0].update(from: channel, count: count)
        let rms = Dictation.rms(UnsafeBufferPointer(start: channel, count: count))
        let capacity = AVAudioFrameCount(Double(count) * target.sampleRate / mono.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity), let converter else { return }
        var given = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true
            status.pointee = .haveData
            return one
        }
        guard error == nil, let ints = out.int16ChannelData?[0] else { return }
        let converted = UnsafeBufferPointer(start: ints, count: Int(out.frameLength))
        lock.withLock {
            samples.append(contentsOf: converted)
            lastRMS = rms
        }
    }
}
