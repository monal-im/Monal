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

    private func intro(app: XCUIApplication)
    {
        // wait for launch
        sleep(1)

        let elementsQuery = app.scrollViews["intro_scroll"].otherElements
        elementsQuery.buttons["Welcome to Monal, Chat for free with your friends, colleagues and family!"].swipeLeft()
        sleep(1)
        elementsQuery.buttons["Choices Galore, Use your existing account or make a new one on the many servers around the world"].swipeLeft()
        sleep(1)
        elementsQuery.buttons["Escape The Garden, You are not trapped in a garden. Talk to anyone else without anyone tracking you."].swipeLeft()
        sleep(1)
        elementsQuery.buttons["Spread The Word, If you like Monal, please let others know and leave a review"].swipeLeft()
        sleep(1)
    }

    private func introSkip(app: XCUIApplication)
    {
        // wait for launch
        sleep(1)
        app.buttons["Skip"].tap()
        sleep(1)
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

        XCTAssertTrue(app.buttons["microphone"].exists)
        XCTAssertFalse(app.buttons["Send"].exists)

        app.textViews["NewChatMessageTextField"].tap()
        app.textViews["NewChatMessageTextField"].typeText(txt)
        // send button should appeared
        XCTAssertTrue(app.buttons["Send"].exists)
        XCTAssertFalse(app.buttons["microphone"].exists)

        app.buttons["Send"].tap()
        // wait for sending on slow systems
        sleep(5)
        // send button should be hidden
        XCTAssertFalse(app.buttons["Send"].exists)
        XCTAssertTrue(app.buttons["microphone"].exists)
    }

    func test_0001_DBInit() throws {
        let app = XCUIApplication()
        app.launchArguments = createStartArgs(extraArgs: ["--reset"])
        app.launch()
    }

    func test_0002_Intro() throws
    {
        let app = XCUIApplication()
        app.launchArguments = createStartArgs(extraArgs: ["--reset"])
        app.launch()

        intro(app: app)

        let elementsQuery2 = app.scrollViews.otherElements
        elementsQuery2.textFields["Account@something.com"].tap()
        elementsQuery2.secureTextFields["Password"].tap()
    }

    func test_0003_IntroSkip() throws
    {
        let app = XCUIApplication()
        app.launchArguments = createStartArgs(extraArgs: ["--reset"])
        app.launch()

        introSkip(app: app)
        app.scrollViews.otherElements.buttons["Set up an account later"].tap()

        let chatsNavigationBar = app.navigationBars["Chats"]
        chatsNavigationBar.buttons["Add"].tap()

        let closeButton = app.alerts["No enabled account found"].scrollViews.otherElements.buttons["Close"]
        closeButton.tap()
        chatsNavigationBar.buttons["Compose"].tap()
        closeButton.tap()
    }

    /*func test_0004_ResetTime() throws {
        let app = XCUIApplication()
        app.launchArguments = createStartArgs(extraArgs: ["--reset"])
        if #available(iOS 13.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                app.launch()
            }
        }
    }*/

    func test_0005_Register() throws
    {
        let app = XCUIApplication()
        app.launchArguments =  createStartArgs(extraArgs: ["--reset"])
        app.launch()

        introSkip(app: app)

        let elementsQuery = app.scrollViews.otherElements
        let registerStaticText = elementsQuery.buttons["Register"]
        registerStaticText.tap()

        app.scrollViews.otherElements.buttons["Terms of service"].tap()
        // wait for safari window to open
        sleep(5)
        app.buttons["Done"].tap()
        elementsQuery.textFields["Username"].tap()
        // create random username
        elementsQuery.textFields["Username"].typeText(String(format: "MonalTestclient-%d", Int.random(in: 1000..<999999)))

        elementsQuery.secureTextFields["Password"].tap()
        elementsQuery.secureTextFields["Password"].typeText(randomPassword())
        registerStaticText.tap()
        // wait for register hud
        sleep(10)
        let startChattingStaticText = app.buttons["Start Chatting"]
        startChattingStaticText.tap()
        sleep(1)
        app.navigationBars["Privacy Settings"].buttons["Close"].tap()
        startChattingStaticText.tap()
    }

    /*func test_0006_LaunchPerformance() throws {
        if #available(iOS 13.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }*/

    func test_0007_PlusAndContactsButtons() throws {
        let app = XCUIApplication()
        app.launchArguments = createStartArgs()
        app.launch()

        let chatsNavigationBar = app.navigationBars["Chats"]
        sleep(1)
        chatsNavigationBar.buttons["Add"].tap()

        let tablesQuery = app.tables
        tablesQuery.staticTexts["Add a New Contact"].tap()
        app.navigationBars["Add Contact"].buttons["New"].tap()
        tablesQuery.staticTexts["Join a Group Chat"].tap()
        app.navigationBars["Join Group Chat"].buttons["New"].tap()
        tablesQuery.staticTexts["View Contact Requests"].tap()
        app.navigationBars["Contact Requests"].buttons["New"].tap()
        app.navigationBars["New"].buttons["Close"].tap()
        chatsNavigationBar.buttons["Compose"].tap()

        let contactsNavigationBar = app.navigationBars["Contacts"]
        contactsNavigationBar.buttons["Close"].tap()
    }

    func test_0008_AddContact() throws {
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
        sleep(2)
        XCTAssertFalse(app.buttons["Send"].exists)
        app.textViews["NewChatMessageTextField"].tap()

        sendMsg(txt: "ping")
        sendMsg(txt: randomString(length: 100))
        sendMsg(txt: randomString(length: 1000))
        sendMsg(txt: randomString(length: 2000))
    }
}
