//
//  ContactEntry.swift
//  Monal
//
//  Created by Friedrich Altheide on 28.11.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

struct ContactEntry: View {
    let contact: ObservableKVOWrapper<MLContact>
    let selfnotesPrefix: Bool
    
    init(contact:ObservableKVOWrapper<MLContact>, selfnotesPrefix: Bool = true) {
        self.contact = contact
        self.selfnotesPrefix = selfnotesPrefix
    }
    
    var body:some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .center) {
                Image(uiImage: contact.avatar)
                    .resizable()
                    .frame(width: 40, height: 40, alignment: .center)
                VStack(alignment: .leading) {
                    if selfnotesPrefix {
                        Text(contact.contactDisplayName as String)
                    } else {
                        Text(contact.contactDisplayNameWithoutSelfnotesPrefix as String)
                    }
                    Text(contact.contactJid as String).font(.footnote).opacity(0.6)
                }
            }
        }
    }
}

#Preview {
    ContactEntry(contact:ObservableKVOWrapper(MLContact.makeDummyContact(0)))
}

#Preview {
    ContactEntry(contact:ObservableKVOWrapper(MLContact.makeDummyContact(1)))
}

#Preview {
    ContactEntry(contact:ObservableKVOWrapper(MLContact.makeDummyContact(2)))
}

#Preview {
    ContactEntry(contact:ObservableKVOWrapper(MLContact.makeDummyContact(3)))
}
