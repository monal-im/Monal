//
//  EncryptedPayload.swift
//  MLCrypto
//
//  Created by Anurodh Pokharel on 1/7/20.
//  Copyright © 2020 Anurodh Pokharel. All rights reserved.
//

import UIKit

@objcMembers
public class EncryptedPayload: NSObject {
    public var body: Data?
    public var iv : Data?
    public var key: Data?
    public var tag: Data?
    public var combined: Data?
    
    @objc
    public func updateValues(body:Data, iv: Data, key: Data, tag: Data)
    {
        self.body=body
        self.iv=iv
        self.key=key
        self.tag=tag
    }
}
