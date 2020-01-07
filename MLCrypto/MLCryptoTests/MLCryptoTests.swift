//
//  MLCryptoTests.swift
//  MLCryptoTests
//
//  Created by Anurodh Pokharel on 1/7/20.
//  Copyright © 2020 Anurodh Pokharel. All rights reserved.
//

import XCTest
@testable import MLCrypto

class MLCryptoTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testEncrypt() {
        let crypto = MLCrypto();
        let input = "Monal"
        
        let encrypted = crypto.encryptGCM(decryptedContent: input.data(using: .utf8)!)
        
        XCTAssert(encrypted != nil)
        
    }

    func testDeCrypt() {
        let crypto = MLCrypto();
        let original = "Monal"
        let key = ""
        let encrypted = ""
        
        let decrypted = crypto.decryptGCM(key: key.data(using: .utf8)!, encryptedContent: encrypted.data(using: .utf8)!)
        
        let decryptedString = String(data:decrypted!, encoding: .utf8)!
        XCTAssert(original == decryptedString)
        
    }
    

}
