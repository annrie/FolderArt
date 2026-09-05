import XCTest
@testable import FolderArt

/// UserDefaults の suite を注入する。suite の検索リストには NSGlobalDomain も入るので、
/// 「消えたこと」は object(forKey:) ではなく persistentDomain (suite 自身の中身) で確かめる
@MainActor
final class LanguageSettingTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "LanguageSettingTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private var stored: [String: Any] { defaults.persistentDomain(forName: suiteName) ?? [:] }

    func testDefaultIsSystemEvenWhenAppleLanguagesExists() {
        defaults.set(["fr"], forKey: LanguageSetting.appleLanguagesKey)   // 自前キーが無ければシステム扱い
        let setting = LanguageSetting(defaults: defaults)
        XCTAssertEqual(setting.selection, .system)
        XCTAssertFalse(setting.needsRelaunch)
    }

    func testSelectingLanguageWritesBothKeysAndFlagsRelaunch() {
        let setting = LanguageSetting(defaults: defaults)
        setting.selection = .en
        XCTAssertEqual(stored[LanguageSetting.key] as? String, "en")
        XCTAssertEqual(stored[LanguageSetting.appleLanguagesKey] as? [String], ["en"])
        XCTAssertTrue(setting.needsRelaunch)

        setting.needsRelaunch = false
        setting.selection = .zhHant
        XCTAssertEqual(stored[LanguageSetting.appleLanguagesKey] as? [String], ["zh-Hant"])
        XCTAssertTrue(setting.needsRelaunch)
    }

    func testSystemRemovesBothKeys() {
        let setting = LanguageSetting(defaults: defaults)
        setting.selection = .ja
        setting.selection = .system
        XCTAssertNil(stored[LanguageSetting.key])
        XCTAssertNil(stored[LanguageSetting.appleLanguagesKey])
        XCTAssertTrue(setting.needsRelaunch)
    }

    func testRestoredFromOwnKey() {
        defaults.set("pt-BR", forKey: LanguageSetting.key)
        XCTAssertEqual(LanguageSetting(defaults: defaults).selection, .ptBR)
    }

    func testUnknownStoredValueFallsBackToSystem() {
        defaults.set("xx-YY", forKey: LanguageSetting.key)
        XCTAssertEqual(LanguageSetting(defaults: defaults).selection, .system)
    }

    func testReselectingSameValueDoesNotFlagRelaunch() {
        let setting = LanguageSetting(defaults: defaults)
        setting.selection = .en
        setting.needsRelaunch = false
        setting.selection = .en
        XCTAssertFalse(setting.needsRelaunch)
    }

    func testNineChoicesWithDistinctNamesAndCodes() {
        XCTAssertEqual(AppLanguage.allCases.count, 9)
        XCTAssertEqual(AppLanguage.allCases.first, .system)
        XCTAssertEqual(Set(AppLanguage.allCases.map(\.displayName)).count, 9)
        XCTAssertEqual(Set(AppLanguage.allCases.map(\.rawValue)), ["system", "ja", "en", "de", "es", "fr", "ko", "pt-BR", "zh-Hant"])
    }
}
