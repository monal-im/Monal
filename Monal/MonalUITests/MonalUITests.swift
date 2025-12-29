//
//  MonalUITests.swift
//  MonalUITests
//
//  Created by Friedrich Altheide on 06.03.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

import XCTest

class MonalUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    private func createStartArgs() -> [String]
    {
        return createStartArgs(extraArgs: [])
    }

    private func createStartArgs(extraArgs: [String]) -> [String]
    {
        var startArgs : [String] = ["--disableAnimations"]
        // append extraArgs
        startArgs.append(contentsOf: extraArgs)

        return startArgs
    }

    private func sendMsg(txt: String)
    {
        let app = XCUIApplication()
        sleep(5)
        XCTAssertTrue(app.buttons["microphone"].exists)
        XCTAssertFalse(app.buttons["Send"].exists)

        app.textViews["NewChatMessageTextField"].tap()
        app.textViews["NewChatMessageTextField"].typeText(txt)
        // send button should appeared
        XCTAssertTrue(app.buttons["send"].exists)
        XCTAssertFalse(app.buttons["microphone"].exists)

        app.buttons["send"].tap()
        // wait for sending on slow systems
        sleep(5)
        // send button should be hidden
        XCTAssertFalse(app.buttons["send"].exists)
        XCTAssertTrue(app.buttons["microphone"].exists)
    }

    func test_0008_AddContact() throws {
        try XCTSkipIf(true, "This test is left as an example of UI tests. At some point in the future we should consider rewriting these.")
        let app = XCUIApplication()
        app.launchArguments = createStartArgs()
        app.launch()

        app.navigationBars["Chats"].buttons["Add"].tap()

        let tablesQuery = app.tables
        tablesQuery.staticTexts["Add a New Contact"].tap()
        tablesQuery.textFields["Contact Jid"].tap()
        tablesQuery.textFields["Contact Jid"].typeText("echo@jabber.fu-berlin.de")

        tablesQuery.staticTexts["Add Contact"].tap()
        app.alerts["Permission Requested"].scrollViews.otherElements.buttons["Close"].tap()
        // wait for segue to chatView
        sleep(10)
        XCTAssertFalse(app.buttons["send"].exists)
        app.textViews["NewChatMessageTextField"].tap()

        sendMsg(txt: "ping")
        sendMsg(txt: randomString(length: 100))
        sendMsg(txt: randomString(length: 1000))
        sendMsg(txt: randomString(length: 2000))
    }
}
