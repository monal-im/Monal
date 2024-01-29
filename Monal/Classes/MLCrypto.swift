//
//  MLCrypto.swift
//  monalxmpp
//
//  Created by Anurodh Pokharel on 1/7/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

import UIKit
import CryptoKit
import ASN1Decoder

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
            
            if let combined = combined {
            let ivData = combined.subdata(in: 0..<12)
            //combined is in the format
            //iv+body+auth
            let range = 12+ciphertext.count..<combined.count //16 is gnereally tag size apple uses
            let tagData = combined.subdata(in:range)
            
            encryptedPayload.updateValues(body:ciphertext, iv: ivData, key:key, tag:tagData)
            encryptedPayload.combined = combined
            return encryptedPayload
            } else  {
                return nil;
            }
        } catch  {
            return nil
        }
    }
    
    // generate 12 byte nonce
    public func genIV() -> Data?
    {
        return Data(AES.GCM.Nonce())
    }
    
    public func decryptGCM (key: Data, encryptedContent:Data) -> Data?
    {
        do {
            let sealedBoxToOpen = try AES.GCM.SealedBox(combined: encryptedContent)
            let gcmKey = SymmetricKey.init(data: key)
            let decryptedData = try AES.GCM.open(sealedBoxToOpen, using: gcmKey)
            return decryptedData
        } catch {
            DDLogWarn("Could not decrypt GCM. Returning nil instead: \(String(describing:error))")
            return nil;
        }
    }
    
    public func getSignatureAlgo(ofCert certData:Data) -> String?
    {
        do {
            let x509 = try X509Certificate(data:certData)
            DDLogVerbose("ASN1 decoded cert: \(x509.description)")
            return x509.sigAlgOID
        } catch {
            DDLogError("ASN1 error: \(error)")
            return nil
        }
    }
}
