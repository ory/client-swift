import Testing
import OryClientTestDoubles

@Suite("InMemorySessionStorage")
struct SessionStorageTests {

    @Test("stores, reads, and clears the token")
    func lifecycle() async throws {
        // Given an empty store
        let storage = InMemorySessionStorage()
        var token = try await storage.sessionToken()
        #expect(token == nil)

        // When a token is stored
        try await storage.store(sessionToken: "abc")
        token = try await storage.sessionToken()
        #expect(token == "abc")

        // Then clearing removes it
        try await storage.clear()
        token = try await storage.sessionToken()
        #expect(token == nil)
    }

    @Test("seeds from an initial token")
    func initialToken() async throws {
        let storage = InMemorySessionStorage(initialToken: "seed")
        let token = try await storage.sessionToken()
        #expect(token == "seed")
    }
}
