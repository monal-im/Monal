//
//  GroupDetailsEdit.swift
//  Monal
//
//  Created by Friedrich Altheide on 23.02.24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import _PhotosUI_SwiftUI

struct GroupDetailsEdit: View {
    @StateObject var contact: ObservableKVOWrapper<MLContact>
    @State private var showingSheetEditName = false
    @State private var showingSheetEditSubject = false
    @State private var inputImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingDestroyConfirmation = false
    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))
    @State private var showAlert = false
    @State private var success = false
    @StateObject private var overlay = LoadingOverlayState()
    @State private var successCallback: monal_void_block_t?
    private let account: xmpp
    private let ownAffiliation: String?

    private func errorAlert(title: Text, message: Text = Text("")) {
        alertPrompt.title = title
        alertPrompt.message = message
        showAlert = true
    }
    
    private func successAlert(title: Text, message: Text = Text("")) {
        alertPrompt.title = title
        alertPrompt.message = message
        showAlert = true
        self.success = true // < dismiss entire view on close
    }
    
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
                            .accessibilityLabel((contact.mucType == "group") ? "Group Avatar" : "Channel Avatar")
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
                        if contact.mucType == "group" {
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
            
            if ownAffiliation == "owner" {
                Section {
                    Button(action: {
                        showingDestroyConfirmation = true
                    }) {
                        if contact.mucType == "group" {
                            Text("Destroy Group").foregroundColor(.red)
                        } else {
                            Text("Destroy Channel").foregroundColor(.red)
                        }
                    }
                    .actionSheet(isPresented: $showingDestroyConfirmation) {
                        ActionSheet(
                            title: contact.mucType == "group" ? Text("Destroy Group") : Text("Destroy Channel"),
                            message: contact.mucType == "group" ? Text("Do you really want to destroy this group? Every member will be kicked out and it will be destroyed afterwards.") : Text("Do you really want to destroy this channel? Every member will be kicked out and it will be destroyed afterwards."),
                            buttons: [
                                .cancel(),
                                .destructive(
                                    Text("Yes"),
                                    action: {
                                        showLoadingOverlay(overlay, headline: contact.mucType == "group" ? NSLocalizedString("Destroying group...", comment: "") : NSLocalizedString("Destroying channel...", comment: ""))
                                        self.account.mucProcessor.destroyRoom(contact.contactJid as String)
                                        self.account.mucProcessor.addUIHandler({_data in let data = _data as! NSDictionary
                                            hideLoadingOverlay(overlay)
                                            let success : Bool = data["success"] as! Bool;
                                            if success {
                                                if let callback = data["callback"] {
                                                    self.successCallback = objcCast(callback) as monal_void_block_t
                                                }
                                                DDLogError("callback: \(String(describing:self.successCallback))")
                                                successAlert(title: Text("Success"), message: contact.mucType == "group" ? Text("Successfully destroyed group.") : Text("Successfully destroyed channel."))
                                            } else {
                                                errorAlert(title: Text("Error destroying group!"), message: Text(data["errorMessage"] as! String))
                                            }
                                        }, forMuc:contact.contactJid)
                                    }
                                )
                            ]
                        )
                    }
                }
            }
        }
        .addLoadingOverlay(overlay)
        .navigationTitle((contact.mucType == "group") ? NSLocalizedString("Edit group", comment: "") : NSLocalizedString("Edit channel", comment: ""))
        .alert(isPresented: $showAlert) {
            Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton:.default(Text("Close"), action: {
                showAlert = false
                if self.success == true {
                    //close muc ui and leave chat ui of this muc
                    if let callback = self.successCallback {
                        callback()
                    }
                    if let activeChats = (UIApplication.shared.delegate as! MonalAppDelegate).activeChats {
                        activeChats.presentChat(with:nil)
                    }
                }
            }))
        }
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
