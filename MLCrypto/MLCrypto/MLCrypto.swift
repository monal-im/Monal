//
//  MLCrypto.swift
//  monalxmpp
//
//  Created by Anurodh Pokharel on 1/7/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

import UIKit
import CryptoKit

@objcMembers
public class MLCrypto: NSObject {
   
    public func encryptGCM (key: Data, decryptedContent:Data) -> EncryptedPayload?
    {
        let gcmKey = SymmetricKey.init(data: key)
        let iv = AES.GCM.Nonce()
        
        do {
            let encrypted = try AES.GCM.seal(decryptedContent, using: gcmKey, nonce: iv)
            let encryptedPayload = EncryptedPayload()
            let combined = encrypted.combined
            let ciphertext = encrypted.ciphertext
            let ivData = combined?.subdata(in: 0..<12)
            let range = 12+ciphertext.count..<28+ciphertext.count
            let tagData = combined?.subdata(in:range)
            encryptedPayload.updateValues(body:ciphertext, iv: ivData!, key:key, tag:tagData!)
            return encryptedPayload
        } catch  {
            return nil
        }
    }
    
    
    public func decryptGCM (key: Data, encryptedContent:Data) -> Data?
    {
        let sealedBoxToOpen = try! AES.GCM.SealedBox(combined: encryptedContent)
        let gcmKey = SymmetricKey.init(data: key)
        do {
            let decryptedData = try AES.GCM.open(sealedBoxToOpen, using: gcmKey)
            return decryptedData
        } catch {
            return nil;
        }
    }
}
