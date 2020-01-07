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
    var data: Data?
    var iv : Data?
    var key: Data?
    
    public func setValues(data:Data, iv: Data, key: Data)
    {
        self.data=data
        self.iv=iv
        self.key=key
    }
}
