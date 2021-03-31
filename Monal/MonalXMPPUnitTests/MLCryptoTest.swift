//
//  MLCryptoTests.swift
//  MLCryptoTests
//
//  Created by Anurodh Pokharel on 1/7/20.
//  Copyright © 2020 Anurodh Pokharel. All rights reserved.
//

import XCTest
@testable import monalxmpp

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
        let key = dataWithHexString(hex:"b1eccf9b3afc566e763ba0968e6b5b58");
        let encrypted = crypto.encryptGCM(key: key,decryptedContent: input.data(using: .utf8)!)

        XCTAssert(encrypted != nil)

        let decrypted = crypto.decryptGCM(key:key, encryptedContent:encrypted!.combined!)
        let result = String(data: decrypted!, encoding: .utf8)
        
        XCTAssert(result == input);
    }

    func dataWithHexString(hex: String) -> Data {
        var hex = hex
        var data = Data()
        while(hex.count > 0) {
            let subIndex = hex.index(hex.startIndex, offsetBy: 2)
            let c = String(hex[..<subIndex])
            hex = String(hex[subIndex...])
            var ch: UInt32 = 0
            Scanner(string: c).scanHexInt32(&ch)
            var char = UInt8(ch)
            data.append(&char, count: 1)
        }
        return data
    }
    
    // TODO: fix tests
    /*func testDecrypt() {
        let crypto = MLCrypto();
        let original = "Hi"
        let key = dataWithHexString(hex:"b1eccf9b3afc566e763ba0968e6b5b58");
        let auth =  dataWithHexString(hex:"cd234619e719389df9e7c26dcda4c8b7");
        let iv =  dataWithHexString(hex:"bd17b36a5321fd8d81ac5a0b82719b5d");
        let encrypted =  dataWithHexString(hex:"666d");
        
        let decrypted = crypto.decryptGCM(key:key, encryptedContent:iv+encrypted+auth)
        XCTAssertNotNil(decrypted, "decrpyted data should not be nil")
        let decryptedString = String(data:(decrypted!), encoding: .utf8)!
        XCTAssert(original == decryptedString)
    }*/
}
