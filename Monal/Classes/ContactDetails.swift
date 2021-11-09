//
//  ContactDetails.swift
//  Monal
//
//  Created by Jan on 22.10.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

import SwiftUI
import monalxmpp

struct ContactDetails: View {
    var delegate: SheetDismisserProtocol = SheetDismisserProtocol()
    var contact : MLContact = MLContact()

    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                    .frame(height: 20)
                ContactDetailsHeader(withContact: contact)
                Spacer()
                    .frame(height: 20)
                Spacer()
            }
            .navigationBarBackButtonHidden(false)                   //will not be shown because swiftui does not know we navigated here from UIKit
            .navigationBarItems(leading: Button(action : {
                self.delegate.dismiss()
            }){
                Image(systemName: "arrow.left")
            })
            .navigationTitle(contact.contactDisplayName())
        }
    }
}

struct ContactDetails_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        ContactDetails(delegate:delegate, contact:MLContact.makeDummyContact(0))
        ContactDetails(delegate:delegate, contact:MLContact.makeDummyContact(1))
        ContactDetails(delegate:delegate, contact:MLContact.makeDummyContact(2))
        ContactDetails(delegate:delegate, contact:MLContact.makeDummyContact(3))
        ContactDetails(delegate:delegate, contact:MLContact.makeDummyContact(4))
    }
}

