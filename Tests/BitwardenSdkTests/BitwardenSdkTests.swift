import Foundation
import XCTest
@testable import BitwardenSdk

final class BitwardenSdkTests: XCTestCase {
    private let connectionId = "11111111-1111-4111-8111-111111111111"

    func testCanonicalAliasReferenceV1FailsClosed() throws {
        let identity = AliasIdentity(
            version: 1,
            connectionId: connectionId,
            aliasId: "remote/object:7",
            address: "alias@example.test"
        )
        let encoded = try createAliasReference(identity: identity)
        let expected =
            "{\"version\":1,\"connectionId\":\"" + connectionId + "\"," +
            "\"aliasId\":\"remote/object:7\",\"address\":\"alias@example.test\"}"

        XCTAssertEqual(encoded, expected)
        let parsed = try parseAliasReference(value: encoded)
        XCTAssertEqual(parsed.version, 1)
        XCTAssertEqual(parsed.connectionId, connectionId)
        XCTAssertEqual(parsed.aliasId, "remote/object:7")
        XCTAssertEqual(try serializeAliasReference(reference: parsed), encoded)

        let rejected = [
            encoded.replacingOccurrences(of: "\"version\":1,", with: ""),
            encoded.replacingOccurrences(of: "\"version\":1", with: "\"version\":0"),
            encoded.replacingOccurrences(of: "\"version\":1", with: "\"version\":2"),
            encoded.replacingOccurrences(
                of: "\"aliasId\":\"remote/object:7\"",
                with: "\"aliasId\":7"
            ),
            encoded.replacingOccurrences(
                of: "}",
                with: ",\"provider\":\"example\"}"
            ),
            "{\"version\":"
        ]

        for value in rejected {
            XCTAssertThrowsError(try parseAliasReference(value: value))
        }
    }

    func testInjectedAdapterSupportsCompleteOneClickLifecycle() async throws {
        let adapter = FixtureAdapter(connectionId: connectionId)
        let client = try AliasClient(adapter: adapter)
        let created = try await client.create(
            request: CreateAliasRequest(hostname: "Example.Test")
        )

        XCTAssertEqual(client.connection(), adapter.connection)
        XCTAssertEqual(created.identity.connectionId, connectionId)
        XCTAssertEqual(created.identity.aliasId, "remote/object:7")
        XCTAssertEqual(adapter.lastHostname, "example.test")
        let listed = try await client.list(request: ListAliasesRequest(pageToken: nil))
        let fetched = try await client.get(identity: created.identity)
        XCTAssertEqual(listed.aliases, [created])
        XCTAssertEqual(fetched, created)

        let disabled = try await client.setEnabled(identity: created.identity, enabled: false)
        XCTAssertEqual(disabled.lifecycle, .disabled)

        let reply = try await client.createSendReplyIdentity(
            request: CreateSendReplyIdentityRequest(
                alias: created.identity,
                recipient: "recipient@example.test"
            )
        )
        let listedReplies = try await client.listSendReplyIdentities(
            alias: created.identity,
            pageToken: nil
        )
        let blocked = try await client.setSendReplyBlocked(identity: reply, blocked: true)
        XCTAssertEqual(listedReplies.identities, [reply])
        XCTAssertEqual(blocked.blocked, true)
        try await client.removeSendReplyIdentity(identity: reply)
        let deleted = try await client.delete(identity: created.identity)
        XCTAssertTrue(deleted.deleted)
    }

    func testForeignConnectionIsRejectedBeforeAdapterMutation() async throws {
        let adapter = FixtureAdapter(connectionId: connectionId)
        let client = try AliasClient(adapter: adapter)
        let foreign = AliasIdentity(
            version: 1,
            connectionId: "22222222-2222-4222-8222-222222222222",
            aliasId: "remote/object:7",
            address: "alias@example.test"
        )

        do {
            _ = try await client.delete(identity: foreign)
            XCTFail("foreign connection unexpectedly authorized")
        } catch let error as AliasError {
            XCTAssertEqual(error, .PermissionDenied)
        }
        XCTAssertEqual(adapter.deleteCalls, 0)
    }

    func testUnknownMutationOutcomeRemainsExplicit() async throws {
        let adapter = FixtureAdapter(
            connectionId: connectionId,
            createError: .OutcomeUnknown
        )
        let client = try AliasClient(adapter: adapter)

        do {
            _ = try await client.create(request: CreateAliasRequest(hostname: nil))
            XCTFail("ambiguous mutation unexpectedly succeeded")
        } catch let error as AliasError {
            XCTAssertEqual(error, .OutcomeUnknown)
        }
        XCTAssertEqual(adapter.createCalls, 1)
    }

    func testJournalTombstoneAndEncryptedVaultReferenceConverge() throws {
        let identity = AliasIdentity(
            version: 1,
            connectionId: connectionId,
            aliasId: "remote/object:7",
            address: "alias@example.test"
        )
        let reference = try createAliasReference(identity: identity)
        let bound = try bindAliasReference(
            value: reference,
            cipher: cipher(id: 1, username: "alias@example.test")
        )

        XCTAssertTrue(bound.changed)
        XCTAssertEqual(bound.cipher.login?.aliasReference, reference)
        XCTAssertTrue((bound.cipher.fields ?? []).isEmpty)

        let alias = makeAlias(identity: identity, enabled: true)
        let plan = try planAliasReconciliation(
            connectionId: connectionId,
            aliases: [alias],
            ciphers: [bound.cipher]
        )
        XCTAssertEqual(plan.summary.matched, 1)
        XCTAssertTrue(
            try applyAliasReconciliation(
                plan: plan,
                aliases: [alias],
                ciphers: [bound.cipher]
            ).result.changedCipherIds.isEmpty
        )

        let event = AliasJournalEvent(
            version: 1,
            eventId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            operationId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            replicaId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
            sequence: 1,
            causal: [],
            operation: .delete,
            phase: .acknowledged,
            target: identity,
            lifecycle: .deleted,
            error: nil
        )
        let journal = try canonicalizeAliasJournal(
            journal: AliasJournal(version: 1, connectionId: connectionId, events: [event])
        )
        let merged = try mergeAliasJournals(
            left: AliasJournal(version: 1, connectionId: connectionId, events: []),
            right: journal
        )
        let reduced = try reduceAliasJournal(journal: merged)
        XCTAssertEqual(reduced.resources.count, 1)
        XCTAssertEqual(reduced.resources[0].identity.aliasId, identity.aliasId)
        XCTAssertTrue(reduced.resources[0].tombstoned)
    }

    func testUsernameEditClearsOnlyAliasReference() throws {
        let identity = AliasIdentity(
            version: 1,
            connectionId: connectionId,
            aliasId: "opaque:not-a-number",
            address: "alias@example.test"
        )
        let bound = try bindAliasReference(
            value: createAliasReference(identity: identity),
            cipher: cipher(id: 1, username: "alias@example.test")
        ).cipher
        let edited = cipher(
            id: 1,
            username: "edited@example.test",
            aliasReference: bound.login?.aliasReference
        )

        let cleared = try clearAliasReferenceIfUsernameChanged(cipher: edited)
        XCTAssertTrue(cleared.changed)
        XCTAssertNil(cleared.cipher.login?.aliasReference)
        XCTAssertEqual(cleared.cipher.login?.username, "edited@example.test")
        XCTAssertEqual(cleared.cipher.name, edited.name)
        XCTAssertEqual(cleared.cipher.id, edited.id)
    }

    private func makeAlias(identity: AliasIdentity, enabled: Bool) -> Alias {
        Alias(
            identity: identity,
            lifecycle: enabled ? .enabled : .disabled,
            freshness: .current,
            consistency: .clean,
            label: nil,
            capabilities: capabilities
        )
    }

    private var capabilities: AliasProviderCapabilities {
        AliasProviderCapabilities(
            create: true,
            list: true,
            get: true,
            enableDisable: true,
            delete: true,
            createSendReplyIdentity: true,
            listSendReplyIdentities: true,
            removeSendReplyIdentity: true,
            extensions: ["send-reply.block"]
        )
    }

    private func cipher(
        id: Int,
        username: String,
        aliasReference: String? = nil
    ) -> CipherView {
        CipherView(
            id: String(format: "00000000-0000-4000-8000-%012x", id),
            organizationId: nil,
            folderId: nil,
            collectionIds: [],
            key: nil,
            name: "Alias (id)",
            notes: nil,
            type: .login,
            login: LoginView(
                username: username,
                password: nil,
                aliasReference: aliasReference,
                passwordRevisionDate: nil,
                uris: nil,
                totp: nil,
                autofillOnPageLoad: nil,
                fido2Credentials: nil
            ),
            identity: nil,
            card: nil,
            secureNote: nil,
            sshKey: nil,
            bankAccount: nil,
            driversLicense: nil,
            passport: nil,
            favorite: false,
            reprompt: .none,
            organizationUseTotp: false,
            edit: true,
            permissions: nil,
            viewPassword: true,
            localData: nil,
            attachments: nil,
            attachmentDecryptionFailures: nil,
            fields: [],
            passwordHistory: nil,
            creationDate: Date(timeIntervalSince1970: 0),
            deletedDate: nil,
            revisionDate: Date(timeIntervalSince1970: 0),
            archivedDate: nil
        )
    }
}

private final class FixtureAdapter: AliasProviderAdapter, @unchecked Sendable {
    let connection: AliasConnection
    private let createError: AliasError?
    private(set) var createCalls = 0
    private(set) var deleteCalls = 0
    private(set) var lastHostname: String?

    init(connectionId: String, createError: AliasError? = nil) {
        self.createError = createError
        let capabilities = AliasProviderCapabilities(
            create: true,
            list: true,
            get: true,
            enableDisable: true,
            delete: true,
            createSendReplyIdentity: true,
            listSendReplyIdentities: true,
            removeSendReplyIdentity: true,
            extensions: ["send-reply.block"]
        )
        connection = AliasConnection(
            version: 1,
            connectionId: connectionId,
            adapter: AliasAdapterDescriptor(
                adapterId: "example.adapter",
                capabilities: capabilities
            )
        )
    }

    func descriptor() throws -> AliasAdapterDescriptor { connection.adapter }

    func connectionId() throws -> String { connection.connectionId }

    func create(request: CreateAliasRequest) async throws -> Alias {
        createCalls += 1
        lastHostname = request.hostname
        if let createError {
            throw createError
        }
        return alias(enabled: true)
    }

    func list(request: ListAliasesRequest) async throws -> AliasPage {
        AliasPage(aliases: [alias(enabled: true)], nextPageToken: nil)
    }

    func get(identity: AliasIdentity) async throws -> Alias { alias(enabled: true) }

    func setEnabled(identity: AliasIdentity, enabled: Bool) async throws -> Alias {
        alias(enabled: enabled)
    }

    func delete(identity: AliasIdentity) async throws -> DeleteAliasResult {
        deleteCalls += 1
        return DeleteAliasResult(identity: identity, deleted: true)
    }

    func createSendReplyIdentity(
        request: CreateSendReplyIdentityRequest
    ) async throws -> SendReplyIdentity {
        sendReplyIdentity(alias: request.alias, recipient: request.recipient)
    }

    func listSendReplyIdentities(
        alias: AliasIdentity,
        pageToken: String?
    ) async throws -> SendReplyIdentityPage {
        SendReplyIdentityPage(
            identities: [sendReplyIdentity(
                alias: alias,
                recipient: "recipient@example.test"
            )],
            nextPageToken: nil
        )
    }

    func removeSendReplyIdentity(identity: SendReplyIdentity) async throws {}

    func setSendReplyBlocked(
        identity: SendReplyIdentity,
        blocked: Bool
    ) async throws -> SendReplyIdentity {
        SendReplyIdentity(
            alias: identity.alias,
            identityId: identity.identityId,
            recipient: identity.recipient,
            address: identity.address,
            valid: identity.valid,
            blocked: blocked
        )
    }

    private func alias(enabled: Bool) -> Alias {
        Alias(
            identity: AliasIdentity(
                version: 1,
                connectionId: connection.connectionId,
                aliasId: "remote/object:7",
                address: "alias@example.test"
            ),
            lifecycle: enabled ? .enabled : .disabled,
            freshness: .current,
            consistency: .clean,
            label: nil,
            capabilities: connection.adapter.capabilities
        )
    }

    private func sendReplyIdentity(
        alias: AliasIdentity,
        recipient: String
    ) -> SendReplyIdentity {
        SendReplyIdentity(
            alias: alias,
            identityId: "reply/object:9",
            recipient: recipient,
            address: "reply@example.test",
            valid: true,
            blocked: false
        )
    }
}
