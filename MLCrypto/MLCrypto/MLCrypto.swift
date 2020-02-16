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
        if #available(iOS 13.0, *) {
            let gcmKey = SymmetricKey.init(data: key)
            
            let iv = AES.GCM.Nonce()
            
            do {
                let encrypted = try AES.GCM.seal(decryptedContent, using: gcmKey, nonce: iv)
                let encryptedPayload = EncryptedPayload()
                let combined = encrypted.combined
                let ciphertext = encrypted.ciphertext
                let ivData = combined?.subdata(in: 0..<12)
                let range = 12+ciphertext.count..<12+16+ciphertext.count //16 is tag size apple uses
                let tagData = combined?.subdata(in:range)
                
                encryptedPayload.updateValues(body:ciphertext, iv: ivData!, key:key, tag:tagData!)
                encryptedPayload.combined = combined
                return encryptedPayload
            } catch  {
                return nil
            }
        } else {
            return nil;
        }
    }
    
    
    public func decryptGCM (key: Data, encryptedContent:Data) -> Data?
    {
        if #available(iOS 13.0, *) {
            let sealedBoxToOpen = try! AES.GCM.SealedBox(combined: encryptedContent)
            let gcmKey = SymmetricKey.init(data: key)
            do {
                let decryptedData = try AES.GCM.open(sealedBoxToOpen, using: gcmKey)
                return decryptedData
            } catch {
                return nil;
            }
        } else {
            return nil 
        }
    }
}
