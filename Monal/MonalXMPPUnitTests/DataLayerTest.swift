//
//  DataLayerTest.swift
//  MonalXMPPUnitTests
//
//  Created by Matthew Fennell on 09/08/2026.
//  Copyright © 2026 monal-im.org. All rights reserved.
//

import Testing
import monalxmpp

struct DataLayerTest {

    // All dates passed to DataLayer.dateString are NSDates created relative to UTC.
    // That's because, they either come from:
    // * An XEP-0203 delayed delivery component, which is treated as UTC by HelperTools.parseDateTime, or
    // * NSDate.now, which stores the current time as an offset from a given date in UTC
    @Test func testDateStringTreatsSourceDateAsUTC() {
        let dateString = DataLayer.dateString(withMessageDate: try! Date.ISO8601FormatStyle.iso8601.parse("2026-08-09T18:36:57Z"))
        #expect(dateString == "2026-08-09 18:36:57")
    }

}
