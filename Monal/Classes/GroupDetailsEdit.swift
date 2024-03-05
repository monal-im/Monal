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
    @StateObject var contact: ObservableKVOWrapper<MLContact>
    @State private var showingSheetEditName = false
    @State private var showingSheetEditSubject = false
    @State private var inputImage: UIImage?
    @State private var showingImagePicker = false
    @StateObject private var overlay = LoadingOverlayState()
    private let account: xmpp
    private let ownAffiliation: String?

    init(contact: ObservableKVOWrapper<MLContact>, ownAffiliation: String?) {
        MLAssert(contact.isGroup)
        
        _contact = StateObject(wrappedValue: contact)
        _inputImage = State(initialValue: contact.avatar)
        self.account = MLXMPPManager.sharedInstance().getConnectedAccount(forID: contact.accountId)! as xmpp
        self.ownAffiliation = ownAffiliation
    }

    var body: some View {
        Form {
            if ownAffiliation == "owner" {
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
            }
            
            Section {
                if ownAffiliation == "owner" {
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
                }
                
                Button(action: {
                    showingSheetEditSubject.toggle()
                }) {
                    HStack {
                        Image(systemName: "pencil")
                        if contact.obj.mucType == "group" {
                            Text("Group description")
                        } else {
                            Text("Channel description")
                        }
                        Spacer()
                    }
                }
                .sheet(isPresented: $showingSheetEditSubject) {
                    LazyClosureView(EditGroupSubject(contact: contact))
                }
            }
        }
        .addLoadingOverlay(overlay)
        .navigationTitle((contact.obj.mucType == "group") ? "Edit group" : "Edit channel")
        .onChange(of:inputImage) { _ in
            showLoadingOverlay(overlay, headline: NSLocalizedString("Uploading image...", comment: ""))
            self.account.mucProcessor.publishAvatar(inputImage, forMuc: contact.contactJid)
        }
        .onChange(of:contact.avatar as UIImage) { _ in
            hideLoadingOverlay(overlay)
        }
    }
}

struct GroupDetailsEdit_Previews: PreviewProvider {
    static var previews: some View {
        GroupDetailsEdit(contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(0)), ownAffiliation:"owner")
    }
}
