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
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["USE_REAL_SERVER"] == "YES" else {
            throw XCTSkip("""
                Set USE_REAL_SERVER to YES to run these tests.
                The UI tests run against a real remote server; to avoid exposing your IP without your consent, they are disabled by default.
                For XCode, go to Monal -> Edit Scheme -> Test -> Arguments -> Environment Variables and set USE_REAL_SERVER to YES.
                For xcodebuild, pass USE_REAL_SERVER=YES as an option in the command.
                """)
        }
    }

    let server = "ephemeral-xmpp-server.org"

    func testCanRegister() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset"]
        app.launch()

        app.transitionThroughOnboardingCards()
        app.openRegisterAccount()
        app.registerNewAccount(server: server, username: "monal-ui-tests-\(UUID().uuidString)".lowercased())
    }

}

private extension XCUIApplication {

    private static let timeout = 20.0

    private var isOnActiveChatsView: Bool {
        navigationBars["Chats"].wait(for: \.isHittable, toEqual: true, timeout: Self.timeout)
    }

    func transitionThroughOnboardingCards() {
        XCTContext.runActivity(named: "Transition through onboarding cards") { _ in
            for _ in 1...4 { buttons["Next"].tap() }
            buttons["Close"].tap()
            XCTAssert(staticTexts["I already have an account:"].exists)
        }
    }

    func openRegisterAccount() {
        XCTContext.runActivity(named: "Open register account screen") { _ in
            buttons["Register a new account"].tap()
            XCTAssert(staticTexts["I need an account:"].exists)
        }
    }

    func registerNewAccount(server: String, username: String) {
        XCTContext.runActivity(named: "Register new account") { _ in
            buttons["SelectServerToRegisterWith"].tap()
            buttons["Manual input"].tap()
            textFields["XMPP Server"].tap()
            textFields["XMPP Server"].typeText(server)
            keyboards.buttons["continue"].tap()
            textFields["Username"].typeText(username)
            keyboards.buttons["continue"].tap()
            buttons["GenerateStrongPasswordButton"].tap()
            buttons["SubmitRegistration"].tap()
            XCTAssert(alerts["Success!"].waitForExistence(timeout: Self.timeout))
            alerts["Success!"].buttons["Close"].tap()
            XCTAssert(isOnActiveChatsView)
        }
    }

}
