import Testing
@testable import ElevateCore

@Suite("Account-scoped session persistence")
struct SessionPersistencePolicyTests {
    private let accountA = SkywardCredentials(
        username: "account-a", password: "password-a", baseURL: CredentialStore.baseURL
    )
    private let accountB = SkywardCredentials(
        username: "account-b", password: "password-b", baseURL: CredentialStore.baseURL
    )

    @Test("An unchanged active account may persist its authenticated session")
    func currentAccount() {
        #expect(SessionPersistencePolicy.permitsSave(
            requestedCredentials: accountA, currentCredentials: accountA,
            isCancelled: false, requestGeneration: 4, currentGeneration: 4
        ))
    }

    @Test("Disconnect cancellation prevents an old authentication from repopulating Keychain")
    func disconnectRace() {
        #expect(!SessionPersistencePolicy.permitsSave(
            requestedCredentials: accountA, currentCredentials: nil,
            isCancelled: true, requestGeneration: 4, currentGeneration: 5
        ))
    }

    @Test("An account switch prevents the previous account session from being persisted")
    func accountSwitchRace() {
        #expect(!SessionPersistencePolicy.permitsSave(
            requestedCredentials: accountA, currentCredentials: accountB,
            isCancelled: false, requestGeneration: 4, currentGeneration: 4
        ))
    }

    @Test("Cancellation rejects credential verification even when it does not persist a session")
    func cancelledVerification() {
        #expect(!AuthenticationRequestPolicy.permitsCompletion(
            isCancelled: true, requestGeneration: 4, currentGeneration: 4
        ))
    }

    @Test("Account invalidation rejects a completed credential verification")
    func invalidatedVerification() {
        #expect(!AuthenticationRequestPolicy.permitsCompletion(
            isCancelled: false, requestGeneration: 4, currentGeneration: 5
        ))
    }

    @Test("A disconnect owns the transition before a deferred save can commit")
    func deferredSaveLosesOwnershipToDisconnect() async {
        var ownership = CredentialSaveOwnership()
        let saveID = ownership.begin()

        await Task.yield()
        ownership.cancel()

        #expect(!ownership.owns(saveID))
    }

    @Test("A newer save owns the transition before an older save can commit")
    func deferredSaveLosesOwnershipToReplacement() async {
        var ownership = CredentialSaveOwnership()
        let olderID = ownership.begin()

        await Task.yield()
        let newerID = ownership.begin()

        #expect(!ownership.owns(olderID))
        #expect(ownership.owns(newerID))
    }
}
