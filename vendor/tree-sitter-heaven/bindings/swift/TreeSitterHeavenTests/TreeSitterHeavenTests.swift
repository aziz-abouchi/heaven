import XCTest
import SwiftTreeSitter
import TreeSitterHeaven

final class TreeSitterHeavenTests: XCTestCase {
    func testCanLoadGrammar() throws {
        let parser = Parser()
        let language = Language(language: tree_sitter_heaven())
        XCTAssertNoThrow(try parser.setLanguage(language),
                         "Error loading Heaven grammar")
    }
}
