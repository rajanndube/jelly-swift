import XCTest
@testable import Jelly

/// Asserts the wire-format mappings (`composableHierarchy ↔ "reactComponents"`,
/// `syncedTo ↔ "_syncedTo"`) survive a round-trip and emit the right JSON
/// keys. The MCP `/sessions` endpoint is shared with the web and Android
/// clients — drift here makes annotations from iOS not parse on the server.
final class AnnotationCodableTests: XCTestCase {

    func test_composableHierarchy_serializesAsReactComponents() throws {
        let annotation = Annotation(
            id: "a1",
            x: 10,
            y: 20,
            comment: "test",
            element: "Button",
            elementPath: "Form > Button",
            timestamp: 0,
            composableHierarchy: "MyApp.LoginScreen"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(data: try encoder.encode(annotation), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"reactComponents\":\"MyApp.LoginScreen\""), json)
        XCTAssertFalse(json.contains("composableHierarchy"))
    }

    func test_syncedTo_serializesAsUnderscoreSyncedTo() throws {
        var annotation = Annotation(
            id: "a1",
            x: 0, y: 0,
            comment: "",
            element: "X",
            elementPath: "X",
            timestamp: 0
        )
        annotation.syncedTo = "session-42"
        let encoder = JSONEncoder()
        let json = String(data: try encoder.encode(annotation), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"_syncedTo\":\"session-42\""), json)
        XCTAssertFalse(json.contains("\"syncedTo\""))
    }

    func test_decodes_reactComponentsField_intoComposableHierarchy() throws {
        let json = """
        {
          "id":"a1","x":1,"y":2,"comment":"c","element":"e","elementPath":"p",
          "timestamp":0,"reactComponents":"MyApp.Login"
        }
        """
        let annotation = try JSONDecoder().decode(Annotation.self, from: Data(json.utf8))
        XCTAssertEqual(annotation.composableHierarchy, "MyApp.Login")
    }

    func test_intentEnum_lowercasedRawValues() throws {
        let json = """
        {"id":"a","x":0,"y":0,"comment":"","element":"e","elementPath":"p",
         "timestamp":0,"intent":"fix","severity":"blocking"}
        """
        let a = try JSONDecoder().decode(Annotation.self, from: Data(json.utf8))
        XCTAssertEqual(a.intent, .fix)
        XCTAssertEqual(a.severity, .blocking)
    }

    func test_roundTrip_preservesAllFields() throws {
        let original = Annotation(
            id: "a1", x: 1.5, y: 2.5,
            comment: "c", element: "e", elementPath: "p",
            timestamp: 1_700_000_000_000,
            boundingBox: BoundingBox(x: 1, y: 2, width: 3, height: 4),
            accessibility: "role=Button",
            composableHierarchy: "MyApp.Login",
            sourceFile: "Foo.swift:1",
            screenshotPath: "/tmp/x.jpg",
            url: "screen:Login",
            intent: .fix,
            severity: .important,
            syncedTo: "sess-1"
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let restored = try decoder.decode(Annotation.self, from: data)
        XCTAssertEqual(restored, original)
    }
}
