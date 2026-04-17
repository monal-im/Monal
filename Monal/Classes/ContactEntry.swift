//
//  ContactEntry.swift
//  Monal
//
//  Created by Friedrich Altheide on 28.11.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

struct ContactEntry<AdditionalContent: View>: View {
    let selfnotesPrefix: Bool
    let fallback: String?
    let avatar: UIImage?
    @ViewBuilder let additionalContent: () -> AdditionalContent
    @ScaledMetric(relativeTo:.body) private var size40px: CGFloat = 40
    
    @StateObject var contact: ObservableKVOWrapper<MLContact>
    
    init(contact: MLContact, selfnotesPrefix: Bool = true, fallback: String? = nil, withAvatar avatar: UIImage? = nil) where AdditionalContent == EmptyView {
        self.init(contact: contact, selfnotesPrefix: selfnotesPrefix, fallback: fallback, withAvatar: avatar, additionalContent: { EmptyView() })
    }

    init(contact: MLContact, selfnotesPrefix: Bool = true, fallback: String? = nil, withAvatar avatar: UIImage? = nil, @ViewBuilder additionalContent: @escaping () -> AdditionalContent) {
        //create our own observable object to not trigger rendering for changes, not observed by us, but by an outer view
        _contact = StateObject(wrappedValue: ObservableKVOWrapper<MLContact>(contact))
        self.selfnotesPrefix = selfnotesPrefix
        self.fallback = fallback
        self.avatar = avatar
        self.additionalContent = additionalContent
    }
    
    var body:some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .center) {
                Image(uiImage: self.avatar ?? self.contact.avatar)
                    .resizable()
                    .frame(width: size40px, height: size40px, alignment: .center)
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
    ContactEntry(contact:MLContact.makeDummyContact(0))
}

#Preview {
    ContactEntry(contact:MLContact.makeDummyContact(1))
}

#Preview {
    ContactEntry(contact:MLContact.makeDummyContact(2))
}

#Preview {
    ContactEntry(contact:MLContact.makeDummyContact(3))
}
