import XCTest
@testable import Jelly

/// Asserts byte-for-byte parity with the Kotlin `OutputGenerator` and the web
/// `generateOutput()`. Field labels (`**Composables:**`, `**Source:**`,
/// `**Accessibility:**`, etc.) are the contract that downstream agents
/// regex on, so any drift here breaks the agent pipeline for all clients.
final class OutputGeneratorParityTests: XCTestCase {

    private let fixedNow: () -> String = { "2026-05-09T00:00:00Z" }
    private let device = "Apple iPhone simulator; iOS 26.0"
    private let dpr: Float = 3.0
    private let viewportWidth = 390
    private let viewportHeight = 844
    private let screenKey = "LoginScreen"

    private var sut: OutputGenerator {
        OutputGenerator(
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            nowIso: fixedNow,
            deviceInfo: device,
            devicePixelRatio: dpr
        )
    }

    private func sampleAnnotation(
        sourceFile: String? = "ContentView.swift:42",
        accessibility: String? = #"role=Button, contentDescription="Submit form""#,
        composables: String? = "MyApp.LoginScreen"
    ) -> Annotation {
        Annotation(
            id: "a1",
            x: 42.5,
            y: 120,
            comment: "Move this up",
            element: "Button \"Submit\"",
            elementPath: "LoginScreen > Form > Button",
            timestamp: 1_234_567_890,
            boundingBox: BoundingBox(x: 40, y: 110, width: 80, height: 36),
            accessibility: accessibility,
            composableHierarchy: composables,
            sourceFile: sourceFile
        )
    }

    func test_emptyAnnotations_returnsEmptyString() {
        XCTAssertEqual(sut.generate(annotations: [], screenKey: screenKey), "")
    }

    func test_compact_singleAnnotation() {
        let expected = """
        ## Page Feedback: LoginScreen

        1. **Button "Submit"** (ContentView.swift:42): Move this up
        """
        XCTAssertEqual(
            sut.generate(annotations: [sampleAnnotation()], screenKey: screenKey, detailLevel: .compact),
            expected
        )
    }

    func test_compact_withSelectedText_truncatesAtThirty() {
        var a = sampleAnnotation()
        a.selectedText = "Hello world this is a long selected piece of text"
        let expected = """
        ## Page Feedback: LoginScreen

        1. **Button "Submit"** (ContentView.swift:42): Move this up (re: "Hello world this is a long sel...")
        """
        XCTAssertEqual(
            sut.generate(annotations: [a], screenKey: screenKey, detailLevel: .compact),
            expected
        )
    }

    func test_standard_includesLocationSourceComposables() {
        let expected = """
        ## Page Feedback: LoginScreen
        **Viewport:** 390×844

        ### 1. Button "Submit"
        **Location:** LoginScreen > Form > Button
        **Source:** ContentView.swift:42
        **Composables:** MyApp.LoginScreen
        **Feedback:** Move this up
        """
        XCTAssertEqual(
            sut.generate(annotations: [sampleAnnotation()], screenKey: screenKey, detailLevel: .standard),
            expected
        )
    }

    func test_detailed_addsAccessibilityAndPosition() {
        let expected = """
        ## Page Feedback: LoginScreen
        **Viewport:** 390×844

        ### 1. Button "Submit"
        **Location:** LoginScreen > Form > Button
        **Source:** ContentView.swift:42
        **Composables:** MyApp.LoginScreen
        **Accessibility:** role=Button, contentDescription="Submit form"
        **Position:** 40px, 110px (80×36px)
        **Feedback:** Move this up
        """
        XCTAssertEqual(
            sut.generate(annotations: [sampleAnnotation()], screenKey: screenKey, detailLevel: .detailed),
            expected
        )
    }

    func test_forensic_emitsEnvironmentBlockAndFullDetail() {
        let expected = """
        ## Page Feedback: LoginScreen

        **Environment:**
        - Viewport: 390×844
        - Screen: LoginScreen
        - Device: Apple iPhone simulator; iOS 26.0
        - Timestamp: 2026-05-09T00:00:00Z
        - Device Pixel Ratio: 3.0

        ---

        ### 1. Button "Submit"
        **Position:** x:40, y:110 (80×36px)
        **Annotation at:** 42.5% from left, 120px from top
        **Accessibility:** role=Button, contentDescription="Submit form"
        **Source:** ContentView.swift:42
        **Composables:** MyApp.LoginScreen
        **Feedback:** Move this up
        """
        XCTAssertEqual(
            sut.generate(annotations: [sampleAnnotation()], screenKey: screenKey, detailLevel: .forensic),
            expected
        )
    }

    func test_standard_skipsSourceWhenNil() {
        let expected = """
        ## Page Feedback: LoginScreen
        **Viewport:** 390×844

        ### 1. Button "Submit"
        **Location:** LoginScreen > Form > Button
        **Composables:** MyApp.LoginScreen
        **Feedback:** Move this up
        """
        XCTAssertEqual(
            sut.generate(
                annotations: [sampleAnnotation(sourceFile: nil)],
                screenKey: screenKey,
                detailLevel: .standard
            ),
            expected
        )
    }

    func test_compact_skipsSelectedTextEllipsisAtBoundary() {
        var a = sampleAnnotation()
        a.selectedText = String(repeating: "a", count: 30)
        let expected = """
        ## Page Feedback: LoginScreen

        1. **Button "Submit"** (ContentView.swift:42): Move this up (re: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        """
        XCTAssertEqual(
            sut.generate(annotations: [a], screenKey: screenKey, detailLevel: .compact),
            expected
        )
    }
}
