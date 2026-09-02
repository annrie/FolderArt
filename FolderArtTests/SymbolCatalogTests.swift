import XCTest
import AppKit
@testable import FolderArt

final class SymbolCatalogTests: XCTestCase {

    func testRestrictedSymbolsAreExcluded() {
        let catalog = SymbolCatalog.load(bundle: Bundle(for: SymbolCatalogTests.self))
        let restricted = SymbolCatalog.restrictedNames(bundle: Bundle(for: SymbolCatalogTests.self))
        XCTAssertGreaterThan(restricted.count, 400)
        XCTAssertTrue(restricted.contains("airplay.audio"))   // symbol_restrictions.strings に必ずある
        XCTAssertTrue(Set(catalog.names).isDisjoint(with: restricted))
        XCTAssertGreaterThan(catalog.names.count, 3000)
    }

    func testEveryCatalogNameIsRenderable() {
        // 抜き取りで 200 個: NSImage(systemSymbolName:) が nil を返さない
        let catalog = SymbolCatalog.load()
        for name in catalog.names.prefix(200) {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), name)
        }
    }

    func testSearchMatchesNameAndTerms() {
        let catalog = SymbolCatalog.load()
        let byName = catalog.search("folder")
        XCTAssertTrue(byName.contains("folder"))
        XCTAssertTrue(byName.contains("folder.fill"))
        XCTAssertTrue(byName.allSatisfy { !$0.isEmpty })

        let byTerm = catalog.search("sports")      // symbol_search.plist の検索語
        XCTAssertFalse(byTerm.isEmpty)

        XCTAssertEqual(catalog.search("").prefix(5).map { $0 }, Array(SymbolCatalog.popularNames.prefix(5)))
    }

    func testSearchLogicWithFixture() {
        // 実機の CoreGlyphs に依存しない検索ロジックの検査
        let catalog = SymbolCatalog(names: ["folder", "folder.fill", "star.fill", "figure.run"],
                                    searchTerms: ["figure.run": ["running", "sports"]])
        XCTAssertEqual(catalog.search("folder"), ["folder", "folder.fill"])
        XCTAssertEqual(catalog.search("sport"), ["figure.run"])
        XCTAssertEqual(catalog.search("  "), ["star.fill", "folder.fill", "folder", "figure.run"]) // popular が先頭
        XCTAssertEqual(catalog.search("zzz"), [])
    }

    func testFallbackListIsBundled() {
        let url = Bundle(for: SymbolCatalogTests.self).url(forResource: "restricted-symbols", withExtension: "txt")
            ?? Bundle.main.url(forResource: "restricted-symbols", withExtension: "txt")
        XCTAssertNotNil(url)
    }
}
