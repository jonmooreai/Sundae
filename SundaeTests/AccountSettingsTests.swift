import Testing
@testable import Sundae

/// Saving settings sends only what changed, so a copy that went stale on another device or
/// window can't undo a newer change, and auto-approves nobody can see are found.
struct AccountSettingsTests {
    private func person(_ id: ID) -> User {
        User(id: id, username: id, name: "Pat Doe", bio: "", avatar: nil, isPublic: false, timezone: "UTC")
    }

    @Test func aPatchCarriesOnlyTheChangedFields() {
        var wanted = AccountSettings()
        wanted.notifyLastCall = false
        let patch = AccountSettingsPatch(from: AccountSettings(), to: wanted)
        #expect(patch.notifyLastCall == false)
        #expect(patch.isPublic == nil)
        #expect(patch.autoApproveUserIDs == nil)
        #expect(!patch.isEmpty)
    }

    @Test func nothingChangedIsAnEmptyPatch() {
        #expect(AccountSettingsPatch(from: AccountSettings(), to: AccountSettings()).isEmpty)
    }

    @Test func aStaleCopyCantUndoANewerChange() {
        // Since this copy was made, the account went Private and dropped Pat elsewhere.
        var stale = AccountSettings()
        stale.isPublic = true
        stale.autoApproveUserIDs = ["u_pat"]
        let server = AccountSettings()
        var wanted = stale
        wanted.notifyLastCall = false
        let merged = AccountSettingsPatch(from: stale, to: wanted).applied(to: server)
        #expect(merged.isPublic == false)
        #expect(merged.autoApproveUserIDs.isEmpty)
        #expect(merged.notifyLastCall == false)
    }

    @Test func goingBackAfterASaveIsSentToo() {
        var publicAccount = AccountSettings()
        publicAccount.isPublic = true
        let first = AccountSettingsPatch(from: AccountSettings(), to: publicAccount)
        #expect(first.isPublic == true)
        // The next save starts from what the server took, so Private again is a change as well.
        let second = AccountSettingsPatch(from: first.applied(to: AccountSettings()), to: AccountSettings())
        #expect(second.isPublic == false)
    }

    @Test func autoApprovesForPeopleWhoCantTagYouAreFound() {
        var settings = AccountSettings()
        settings.autoApproveUserIDs = ["u_pat", "u_sam", "u_lee"]
        #expect(settings.autoApprovedIDs(notIn: [person("u_sam")]) == ["u_pat", "u_lee"])
        #expect(settings.autoApprovedIDs(notIn: [person("u_pat"), person("u_sam"), person("u_lee")]).isEmpty)
        #expect(settings.autoApprovedIDs(notIn: []) == ["u_pat", "u_sam", "u_lee"])
    }

    @Test func theMockKeepsWhatAPatchLeavesOut() async throws {
        let api = MockSundaeAPI(clock: SundayClock())
        _ = try await api.createAccount(ticket: "mock-signup-ticket", username: "", name: nil)
        var noLastCall = AccountSettingsPatch()
        noLastCall.notifyLastCall = false
        try await api.updateAccountSettings(noLastCall)
        var goPublic = AccountSettingsPatch()
        goPublic.isPublic = true
        try await api.updateAccountSettings(goPublic)
        let settings = try await api.accountSettings()
        #expect(settings.isPublic)
        #expect(settings.notifyLastCall == false)
        #expect(settings.notifySundayReminder)
    }
}
