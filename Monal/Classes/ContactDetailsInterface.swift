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

class SheetDismisserProtocol: ObservableObject {
    weak var host: UIHostingController<AnyView>? = nil
    func dismiss() {
        host?.dismiss(animated: true)
    }
}

@objc
class ContactDetailsInterface: NSObject {
    @objc func makeContactDetails(_ contact: MLContact) -> UIViewController {
        let details = ContactDetails(contact:contact)
        let host = UIHostingController(rootView: AnyView(details))
        details.delegate.host = host
        return host;
    }
}
