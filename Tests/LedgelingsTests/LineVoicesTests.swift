import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// A pretend local speech server at `line-voices.test`, counting what it is asked to say.
final class FakeSpeechServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var spoken: [String] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "line-voices.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let body: Data, type: String
        if url.path.hasSuffix("audio/voices") {
            body = Data(#"{"voices":["af_bella"]}"#.utf8); type = "application/json"
        } else {
            let data = request.httpBody ?? request.httpBodyStream.map { stream in
                stream.open(); defer { stream.close() }
                var all = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; all.append(buffer, count: n) }
                return all
            } ?? Data()
            let text = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["input"] as? String ?? ""
            Self.lock.withLock { Self.spoken.append(text) }
            body = Data("RIFF-\(text)".utf8); type = "audio/wav"
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// The built-in lines are made once in each voice, then played from disk.
@MainActor
@Suite(.serialized) struct LineVoicesTests {
    final class Setup {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-line-voices-\(UUID().uuidString)")
        let name = "ledgelings-line-voices-tests"
        let defaults: UserDefaults
        let settings: AppSettings
        @MainActor init() {
            defaults = UserDefaults(suiteName: name)!
            defaults.removePersistentDomain(forName: name)
            settings = AppSettings(defaults: defaults, keychain: Keychain(service: name))
            settings.voiceEngine = .local
            settings.localVoiceServer = "http://line-voices.test"
            URLProtocol.registerClass(FakeSpeechServer.self)
            FakeSpeechServer.lock.withLock { FakeSpeechServer.spoken = [] }
        }
        @MainActor func voice() -> Voice {
            Voice(settings: settings, spend: SpendLedger(directory: dir.appendingPathComponent("spend")),
                  archive: dir.appendingPathComponent("voices"), lineArchive: dir.appendingPathComponent("line-voices"))
        }
        func forget() {
            URLProtocol.unregisterClass(FakeSpeechServer.self)
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: dir)
        }
        var asked: [String] { FakeSpeechServer.lock.withLock { FakeSpeechServer.spoken } }
    }

    @Test func aBuiltInLineIsMadeOnceAndThenPlayedFromDiskEvenAfterARelaunch() async throws {
        let s = Setup()
        defer { s.forget() }
        let first = try #require(try await s.voice().sound(for: "Move that cursor, Zed.", as: "Blocky", builtIn: true))
        #expect(!first.kept && s.asked == ["Move that cursor, Zed."])
        let again = try #require(try await s.voice().sound(for: "Move that cursor, Zed.", as: "Blocky", builtIn: true))
        #expect(again.kept && again.audio == first.audio, "the saved copy, from a fresh start")
        #expect(s.asked.count == 1, "the server was not asked twice")
        #expect(s.voice().lineClips.count == 1)
    }

    @Test func aModelsLineAndAnySpeechWithSavingOffAreMadeEveryTime() async throws {
        let s = Setup()
        defer { s.forget() }
        let voice = s.voice()
        _ = try await voice.sound(for: "Something new.", as: "Blocky", builtIn: false)
        _ = try await voice.sound(for: "Something new.", as: "Blocky", builtIn: false)
        #expect(s.asked.count == 2 && voice.lineClips.isEmpty, "a model's words rarely come round again")
        s.settings.reuseLineVoices = false
        _ = try await voice.sound(for: "Hello.", as: "Blocky", builtIn: true)
        _ = try await voice.sound(for: "Hello.", as: "Blocky", builtIn: true)
        #expect(s.asked.count == 4 && voice.lineClips.isEmpty)
    }

    @Test func clearingForgetsTheSavedLines() async throws {
        let s = Setup()
        defer { s.forget() }
        let voice = s.voice()
        _ = try await voice.sound(for: "Hello.", as: "Blocky", builtIn: true)
        voice.clearLineArchive()
        #expect(voice.lineClips.isEmpty && s.voice().lineClips.isEmpty)
        let again = try #require(try await voice.sound(for: "Hello.", as: "Blocky", builtIn: true))
        #expect(!again.kept && s.asked.count == 2)
    }
}
