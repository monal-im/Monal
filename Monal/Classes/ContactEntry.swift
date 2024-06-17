//
//  ContactEntry.swift
//  Monal
//
//  Created by Friedrich Altheide on 28.11.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

struct ContactEntry<AdditionalContent: View>: View {
    let contact: ObservableKVOWrapper<MLContact>
    let selfnotesPrefix: Bool
    @ViewBuilder let additionalContent: () -> AdditionalContent
    
    init(contact:ObservableKVOWrapper<MLContact>, selfnotesPrefix: Bool = true) where AdditionalContent == EmptyView {
        self.init(contact:contact, selfnotesPrefix:selfnotesPrefix, additionalContent:{ EmptyView() })
    }
    
    init(contact:ObservableKVOWrapper<MLContact>, @ViewBuilder additionalContent: @escaping () -> AdditionalContent) {
        self.init(contact:contact, selfnotesPrefix:true, additionalContent:additionalContent)
    }
    
    init(contact:ObservableKVOWrapper<MLContact>, selfnotesPrefix: Bool, @ViewBuilder additionalContent: @escaping () -> AdditionalContent) {
        self.contact = contact
        self.selfnotesPrefix = selfnotesPrefix
        self.additionalContent = additionalContent
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
                    additionalContent()
                    Text(contact.contactJid as String)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .font(.footnote)
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
