//
//  GroupDetailsEdit.swift
//  Monal
//
//  Created by Friedrich Altheide on 23.02.24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import SwiftUI
import _PhotosUI_SwiftUI

struct GroupDetailsEdit: View {
    @ObservedObject var contact: ObservableKVOWrapper<MLContact>
    private let account: xmpp?

    @State private var showingSheetEditName = false
    @State private var showingSheetEditSubject = false
    @State private var inputImage: UIImage?
    @State private var showingImagePicker = false

    init(contact: ObservableKVOWrapper<MLContact>) {
        MLAssert(contact.isGroup)

        self.contact = contact
        self.account = MLXMPPManager.sharedInstance().getConnectedAccount(forID: contact.accountId)! as xmpp
        _inputImage = State(initialValue: contact.avatar)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    Image(uiImage: contact.avatar)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel((contact.obj.mucType == "group") ? "Group Avatar" : "Channel Avatar")
                        .frame(width: 150, height: 150, alignment: .center)
                        .shadow(radius: 7)
                        .onTapGesture {
                            showingImagePicker = true
                        }
                    Spacer()
                }
                .sheet(isPresented:$showingImagePicker) {
                    ImagePicker(image:$inputImage)
                }
            }
            Section {
                if #available(iOS 15.0, *) {
                    Button(action: {
                        showingSheetEditName.toggle()
                    }) {
                        HStack {
                            Image(systemName: "person.2")
                            Text(contact.contactDisplayName as String)
                            Spacer()
                        }
                    }
                    .sheet(isPresented: $showingSheetEditName) {
                        LazyClosureView(EditGroupName(contact: contact))
                    }
                    Button(action: {
                        showingSheetEditSubject.toggle()
                    }) {
                        HStack {
                            Image(systemName: "pencil")
                            Text((contact.obj.mucType == "group") ? "Group description" : "Channel description")
                            Spacer()
                        }
                    }
                    .sheet(isPresented: $showingSheetEditSubject) {
                        LazyClosureView(EditGroupSubject(contact: contact))
                    }
                }
            }
        }
        .navigationTitle((contact.obj.mucType == "group") ? "Edit group" : "Edit channel")
        .onChange(of:inputImage) { _ in
            self.account!.mucProcessor.publishAvatar(inputImage, forMuc: contact.contactJid)
        }
    }
}

#Preview {
    GroupDetailsEdit(contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(0)))
}
