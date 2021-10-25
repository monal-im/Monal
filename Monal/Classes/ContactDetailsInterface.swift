//
//  ContactDetailsInterface.swift
//  Monal
//
//  Created by Jan on 22.10.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

import Foundation
import SwiftUI
import monalxmpp

@objc
class ContactDetailsInterface: NSObject {
    @objc func makeContactDetails(_ contact: MLContact) -> UIViewController {
        let details = ContactDetails(withContact: contact)
        return UIHostingController(rootView: details)
    }
}
