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

    func testDBInit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reset"]
        app.launch()
    }

    func intro(app: XCUIApplication)
    {
        let elementsQuery = app.scrollViews["intro_scroll"].otherElements
        elementsQuery.buttons["Welcome to Monal, Chat for free with your friends, colleagues and family!"].swipeLeft()
        elementsQuery.buttons["Choices Galore, Use your existing account or make a new one on the many servers around the world"].swipeLeft()
        elementsQuery.buttons["Escape The Garden, You are not trapped in a garden. Talk to anyone else without anyone tracking you."].swipeLeft()
        elementsQuery.buttons["Spread The Word, If you like Monal, please let others know and leave a review"].swipeLeft()
    }

    func testIntro() throws
    {
        let app = XCUIApplication()
        app.launchArguments = ["--reset"]
        app.launch()

        intro(app: app)

        let elementsQuery2 = app.scrollViews.otherElements
        elementsQuery2.textFields["Account@something.com"].tap()
        elementsQuery2.secureTextFields["Password"].tap()
    }

    func testIntroSkip() throws
    {
        let app = XCUIApplication()
        app.launchArguments = ["--reset"]
        app.launch()
    }

    func testRegister() throws
    {
        let app = XCUIApplication()
        app.launchArguments = ["--reset"]
        app.launch()

        intro(app: app)

        let elementsQuery = app.scrollViews.otherElements
        let registerStaticText = elementsQuery.buttons["Register"]
        registerStaticText.tap()

        app.scrollViews.otherElements.buttons["Terms of service"].tap()
        app/*@START_MENU_TOKEN@*/.buttons["Done"]/*[[".otherElements[\"BrowserView?WebViewProcessID=41735\"]",".otherElements[\"TopBrowserBar\"].buttons[\"Done\"]",".buttons[\"Done\"]"],[[[-1,2],[-1,1],[-1,0,1]],[[-1,2],[-1,1]]],[0]]@END_MENU_TOKEN@*/.tap()
        elementsQuery.textFields["Username"].tap()
        // create random username
        elementsQuery.textFields["Username"].typeText(String(format: "MonalTestclient-%d", Int.random(in: 1000..<999999)))

        elementsQuery.secureTextFields["Password"].tap()
        elementsQuery.secureTextFields["Password"].typeText(randomPassword())
        registerStaticText.tap()

        let startChattingStaticText = app.buttons["Start Chatting"]
        startChattingStaticText.tap()
        app.navigationBars["Privacy Settings"].buttons["Close"].tap()
        startChattingStaticText.tap()
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
