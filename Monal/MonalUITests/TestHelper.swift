//
//  TestHelper.swift
//  MonalUITests
//
//  Created by Friedrich Altheide on 06.03.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

import Foundation

func randomPassword() -> String
{
    let passwordLen = Int.random(in: 20..<100)
    return randomString(length: passwordLen)
}

func randomString(length: Int = 100) -> String
{
    let alphabet: NSString = "qwertzuiopasdfghjklyxcvbnmQWERTZUIOPASDFGHJKLYXCVBNM1234567890!§$%&/()=?,.-;:_*'^"
    var password: String = ""
    for _ in 0 ..< length
    {
        var charElement = alphabet.character(at: Int(arc4random_uniform(UInt32(alphabet.length))))
        password += NSString(characters: &charElement, length: 1) as String
    }

    return password
}
