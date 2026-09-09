//
//  Acorn3DSampleUITests.swift
//  Acorn3DSampleUITests
//
//  Created by Teemu Harju on 27.6.2026.
//

import XCTest

final class Acorn3DSampleUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }
    
    @MainActor
    func testMapPanAndRefocusButton() throws {
        let app = XCUIApplication()
        app.launch()
        
        let focusedButton = app.buttons["📍 Focused"]
        XCTAssertTrue(focusedButton.waitForExistence(timeout: 5.0))
        
        let initialAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        initialAttachment.name = "map_focused"
        initialAttachment.lifetime = .keepAlways
        add(initialAttachment)
        
        // Pan the map across screen
        let startCoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.4))
        let endCoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.4))
        startCoordinate.press(forDuration: 0.1, thenDragTo: endCoordinate)
        
        // Button changes to "📍 Focus Player"
        let focusPlayerButton = app.buttons["📍 Focus Player"]
        XCTAssertTrue(focusPlayerButton.waitForExistence(timeout: 3.0))
        
        let pannedAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        pannedAttachment.name = "map_panned"
        pannedAttachment.lifetime = .keepAlways
        add(pannedAttachment)
        
        // Tap "📍 Focus Player" to refocus
        focusPlayerButton.tap()
        
        // Button returns to "📍 Focused"
        XCTAssertTrue(focusedButton.waitForExistence(timeout: 4.0))
        
        let refocusedAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        refocusedAttachment.name = "map_refocused"
        refocusedAttachment.lifetime = .keepAlways
        add(refocusedAttachment)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
