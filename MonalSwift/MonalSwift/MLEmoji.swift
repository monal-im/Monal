//
//  MLEmoji.swift
//  monalxmpp
//
//  Created by Anurodh Pokharel on 3/29/21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

import Foundation

@objcMembers
public class MLEmoji: NSObject {
    public static func containsEmoji(text:String) -> Bool {
        for scalar in text.unicodeScalars {
            let isEmoji = scalar.properties.isEmoji

            if(isEmoji) {
                return true
        }
    }
    return false
    }
}
