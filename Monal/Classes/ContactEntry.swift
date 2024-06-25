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
    let fallback: String?
    @ViewBuilder let additionalContent: () -> AdditionalContent
    
    init(contact:ObservableKVOWrapper<MLContact>, selfnotesPrefix: Bool = true, fallback: String? = nil) where AdditionalContent == EmptyView {
        self.init(contact:contact, selfnotesPrefix:selfnotesPrefix, fallback:fallback, additionalContent:{ EmptyView() })
    }
    
    init(contact:ObservableKVOWrapper<MLContact>, fallback: String?) where AdditionalContent == EmptyView {
        self.init(contact:contact, selfnotesPrefix:true, fallback:fallback, additionalContent:{ EmptyView() })
    }
    
    init(contact:ObservableKVOWrapper<MLContact>, @ViewBuilder additionalContent: @escaping () -> AdditionalContent) {
        self.init(contact:contact, selfnotesPrefix:true, additionalContent:additionalContent)
    }
    
    init(contact:ObservableKVOWrapper<MLContact>, fallback: String?, @ViewBuilder additionalContent: @escaping () -> AdditionalContent) {
        self.init(contact:contact, selfnotesPrefix:true, fallback:fallback, additionalContent:additionalContent)
    }
    
    init(contact:ObservableKVOWrapper<MLContact>, selfnotesPrefix: Bool, @ViewBuilder additionalContent: @escaping () -> AdditionalContent) {
        self.init(contact:contact, selfnotesPrefix:selfnotesPrefix, fallback:nil, additionalContent:additionalContent)
    }
    
    init(contact:ObservableKVOWrapper<MLContact>, selfnotesPrefix: Bool, fallback: String?, @ViewBuilder additionalContent: @escaping () -> AdditionalContent) {
        self.contact = contact
        self.selfnotesPrefix = selfnotesPrefix
        self.fallback = fallback
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
                        // use the if to make sure this view gets updated if the contact display name changes
                        // (the condition is never false, because contactDisplayName can not be nil)
                        if (contact.contactDisplayName as String?) != nil {
                            Text(contact.obj.contactDisplayName(withFallback:fallback))
                        }
                    } else {
                        // use the if to make sure this view gets updated if the contact display name changes
                        // (the condition is never false, because contactDisplayNameWithoutSelfnotesPrefix can not be nil)
                        if (contact.contactDisplayNameWithoutSelfnotesPrefix as String?) != nil {
                            Text(contact.obj.contactDisplayName(withFallback:fallback, andSelfnotesPrefix:false))
                        }
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
