import Foundation
import Testing
@testable import Ledgelings

/// OpenRouter's model list, parsed, searched and ranked without a network.
@Suite struct ModelCatalogTests {
    static let sample = Data("""
    {"data":[
      {"id":"google/gemini-2.5-flash-lite","name":"Google: Gemini 2.5 Flash Lite","context_length":1048576,
       "pricing":{"prompt":"0.0000001","completion":"0.0000004"}},
      {"id":"anthropic/claude-haiku-4.5","name":"Anthropic: Claude Haiku 4.5","context_length":200000,
       "pricing":{"prompt":"0.000001","completion":"0.000005"}},
      {"id":"google/gemma-4-26b-a4b-it:free","name":"Google: Gemma 4 26B (free)","context_length":131072,
       "pricing":{"prompt":"0","completion":"0"}},
      {"id":"weird/no-price","name":"No Price"}
    ]}
    """.utf8)

    @Test func pricesComeOutPerMillionTokens() throws {
        let models = try ModelCatalog.parse(Self.sample)
        #expect(models.count == 4)
        let lite = try #require(models.first { $0.id == "google/gemini-2.5-flash-lite" })
        #expect(lite.name == "Google: Gemini 2.5 Flash Lite")
        #expect(lite.promptPerMillion == 0.1)
        #expect(lite.completionPerMillion == 0.4)
        #expect(lite.context == 1_048_576)
        let free = try #require(models.first { $0.id.hasSuffix(":free") })
        #expect(free.isFree)
        let unpriced = try #require(models.first { $0.id == "weird/no-price" })
        #expect(unpriced.promptPerMillion == nil)
    }

    @Test func aBanterExchangeIsPricedFromBothRates() throws {
        let models = try ModelCatalog.parse(Self.sample)
        let lite = try #require(models.first { $0.id == "google/gemini-2.5-flash-lite" })
        // Two calls of 300 tokens in and 80 out: 2 * (300 * 0.1 + 80 * 0.4) / 1e6 dollars.
        let cost = try #require(lite.exchangeCost)
        #expect(abs(cost - 0.000124) < 1e-9)
    }

    @Test func searchMatchesEveryWordAgainstIdOrName() throws {
        let catalog = ModelCatalog(models: try ModelCatalog.parse(Self.sample))
        #expect(catalog.search("flash lite").map(\.id) == ["google/gemini-2.5-flash-lite"])
        #expect(catalog.search("GOOGLE").map(\.id).sorted() == ["google/gemini-2.5-flash-lite", "google/gemma-4-26b-a4b-it:free"])
        #expect(catalog.search("haiku anthropic").map(\.id) == ["anthropic/claude-haiku-4.5"])
        #expect(catalog.search("nothing-like-this").isEmpty)
    }

    @Test func emptySearchRanksCheapestFirstWithUnpricedLast() throws {
        let catalog = ModelCatalog(models: try ModelCatalog.parse(Self.sample))
        #expect(catalog.search("").map(\.id) == [
            "google/gemma-4-26b-a4b-it:free", "google/gemini-2.5-flash-lite", "anthropic/claude-haiku-4.5", "weird/no-price",
        ])
    }

    @Test func priceLabelsReadAtAGlance() throws {
        let models = try ModelCatalog.parse(Self.sample)
        let labels = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0.priceLabel) })
        #expect(labels["google/gemini-2.5-flash-lite"] == "$0.10 in · $0.40 out per M")
        #expect(labels["google/gemma-4-26b-a4b-it:free"] == "free")
        #expect(labels["weird/no-price"] == "price unknown")
    }
}
