//
//  AccountSettings.swift
//  Monal
//
//  Created by lissine on 2/11/2024.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

class AccountSettingsModel: ObservableObject {
    let jid: String
    @Published var rosterName: String
    @Published var statusMessage: String
    @Published var avatar: UIImage?
    @Published var account: xmpp?
    @Published var accountEnabled: Bool

    init(accountID: NSNumber?) {
        guard accountID != nil,
              let settings = DataLayer.sharedInstance().details(forAccount: accountID!)
        else {
            self.jid = ""
            self.rosterName = ""
            self.statusMessage = ""
            self.account = nil
            self.avatar = nil
            self.accountEnabled = false
            return
        }
        self.jid = "\(settings["username"]!)@\(settings["domain"]!)"
        self.rosterName = settings["rosterName"] as? String ?? ""
        self.statusMessage = settings["statusMessage"] as? String ?? ""
        self.avatar = MLImageManager.sharedInstance().getIconFor(MLContact.createContact(fromJid: self.jid, andAccountID: accountID!))
        self.account = MLXMPPManager.sharedInstance().getEnabledAccount(forID: accountID!)
        self.accountEnabled = settings["enabled"] as? Bool ?? false
    }
}
struct AccountSettings: View {
    let accountID: NSNumber?
    var delegate: SheetDismisserProtocol

    @ObservedObject var model: AccountSettingsModel

    @State private var showingClearHistoryConfirmation = false
    @State private var showingRemoveAccountConfirmation = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var showingRemoveAvatarConfirmation = false

    @State private var inputImage: UIImage?
    @State private var showingImagePicker = false

    @State private var showAlert = false
    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))

    @StateObject private var overlay = LoadingOverlayState()

    init(accountID: NSNumber?, delegate: SheetDismisserProtocol) {
        self.accountID = accountID
        self.delegate = delegate
        self.model = AccountSettingsModel(accountID: accountID)
    }

    private var ownContact: MLContact {
        return MLContact.createContact(fromJid: self.model.jid, andAccountID: self.accountID!)
    }

    // This function is called after removing / deleting an account
    private func handlePostAccountRemoval(executionStartTime: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + executionStartTime) {
            delegate.dismiss()

            // We want to start fresh instead of doing a "password migration" - restore directly triggering an SMS
            HelperTools.defaultsDB().removeObject(forKey: "Quicksy_phoneNumber")
            HelperTools.defaultsDB().removeObject(forKey: "Quicksy_country")

            // Make sure we show account creation view etc. after removing the last account
            guard let appDelegate = UIApplication.shared.delegate as? MonalAppDelegate,
                  let activeChats = appDelegate.activeChats else {
                return
            }
            activeChats.segueToIntroScreensIfNeeded()
        }
    }

    // TODO: move to a separate file AvatarPicker.swift along with the rest of the AvatarPicking
    private func showImagePicker() {
#if targetEnvironment(macCatalyst)
        let picker = DocumentPickerViewController(
            supportedTypes: [UTType.image],
            onPick: { url in
                if let imageData = try? Data(contentsOf: url) {
                    if let loadedImage = UIImage(data: imageData) {
                        self.inputImage = loadedImage
                    }
                }
            },
            onDismiss: {
                // do nothing on dismiss
            }
        )
        UIApplication.shared.windows.first?.rootViewController?.present(picker, animated: true)
#else
        showingImagePicker = true
#endif
    }

    var body: some View {
        Form {
            Section(header: Text("")) {
                VStack {
                    Image(uiImage: model.avatar ?? UIImage(named: "noicon")!)
                        .resizable()
                        .scaledToFit()
                    // .clipShape(Circle())
                        .onTapGesture {
                            showImagePicker()
                        }

                        .addTopRight {
                            Button(action: {
                                showImagePicker()
                            }, label: {
                                Image(systemName: "pencil.circle.fill")
                                    .resizable()
                                    .frame(width: 24.0, height: 24.0)
                                    .accessibilityLabel(Text("Change Avatar"))
                            })
                            .buttonStyle(.borderless)
                            .offset(x: 8, y: -8)
                        }
                        .addTopLeft {
                            if MLImageManager.sharedInstance().hasIcon(for: self.ownContact) {
                                Button(action: {
                                    showingRemoveAvatarConfirmation = true
                                }, label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .resizable()
                                        .frame(width: 24.0, height: 24.0)
                                        .accessibilityLabel(Text("Remove Avatar"))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .red)
                                })
                                .buttonStyle(.borderless)
                                .offset(x: -8, y: -8)
                            }
                        }
                        .frame(width: 100, height: 100)

                        .shadow(radius: 7)
                        .confirmationDialog(
                            "Really remove avatar?",
                            isPresented: $showingRemoveAvatarConfirmation,
                            actions: {
                                Button("Yes", role: .destructive) {
                                    showLoadingOverlay(overlay, headlineView: Text("Removing avatar..."), descriptionView: Text(""))
                                    model.account?.publishAvatar(nil)
                                }
                            },
                            message: {
                                Text("This will remove the current avatar image and revert this account to the default one.")
                            }
                        )

                        .sheet(isPresented: $showingImagePicker) {
                            ImagePicker(image: $inputImage)
                        }
                        .sheet(isPresented: $inputImage.optionalMappedToBool()) {
                            ImageCropView(originalImage: inputImage!, configureBlock: { cropViewController in
                                cropViewController.aspectRatioPreset = .presetSquare
                                cropViewController.aspectRatioLockEnabled = true
                                cropViewController.aspectRatioPickerButtonHidden = true
                                cropViewController.resetAspectRatioEnabled = false
                            }, onCanceled: {
                                inputImage = nil
                            }) { (image, cropRect, angle) in
                                showLoadingOverlay(overlay, headlineView: Text("Publishing avatar..."), descriptionView: Text(""))
                                model.account?.publishAvatar(image)
                            }
                        }

                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color(UIColor.systemGroupedBackground))
            }

            Section(header: Text("Account (\(self.model.jid))")) {
                Toggle(isOn: $model.accountEnabled) {
                    Text("Enabled")
                }
                .onChange(of: model.accountEnabled) { _ in
                    guard self.accountID != nil else { return }
                    if model.accountEnabled {
                        // Update the enabled status in the DB
                        DDLogVerbose("Enabling and connecting to account \(model.jid)...")
                        DataLayer.sharedInstance().enableAccount(forAccountID: self.accountID!)
                        // Connect:
                        MLXMPPManager.sharedInstance().connectAccount(self.accountID!)
                    } else {
                        // Disconnect account before disabling it in db, to avoid assertions when trying to create MLContact instances
                        // for the disabled account (for notifications etc.)

                        DDLogVerbose("Disconnecting and disabling account \(model.jid)...")
                        // Disconnect
                        MLXMPPManager.sharedInstance().disconnectAccount(self.accountID!, withExplicitLogout: true)

                        // Delete all SiriKit interactions
                        HelperTools.removeAllShareInteractions(forAccountID: self.accountID!)

                        // Update the enabled status in the DB
                        DataLayer.sharedInstance().disableAccount(forAccountID: self.accountID!)
                    }

                    // Update model.account to ensure we have a consistent state. Otherwise there would be problems with the General Section.
                    // NOTE: this makes an account disable / enable trigger two view refreshes, due to the two changes in the ObservableObject not happening at the exact same time
                    // maybe this entire .onChange can be handled inside the ObservableObject itself
                    model.account = MLXMPPManager.sharedInstance().getEnabledAccount(forID: accountID!)

                    // trigger view updates to make sure enabled/disabled account state propagates to all ui elements
                    //TODO: replace with MLNotificationQueue.currentQueue.post, and consider moving it to inside DataLayer.disableAccount and DataLayer.enableAccount. Though note that the DataLayer doesn't currently handle any notifications.
                    NotificationCenter.default.post(name: NSNotification.Name("kMonalRefresh"), object: nil)
                }

                HStack {
                    Text("Display Name")
                    Spacer()
                    TextField("", text: $model.rosterName)
                        .onSubmit {
                            showLoadingOverlay(overlay, headlineView: Text("Updating display name..."), descriptionView: Text(""))
                            model.account?.publishRosterName(model.rosterName)
                        }
                }
                HStack {
                    Text("Status Message")
                    Spacer()
                    TextField("Your status", text: $model.statusMessage)
                        .onSubmit {
                            showLoadingOverlay(overlay, headlineView: Text("Updating status message..."), descriptionView: Text(""))
                            model.account?.publishStatusMessage(model.statusMessage)
                        }
                }

                NavigationLink(destination: LazyClosureView(LoginCredentials(accountID: self.accountID))) {
                    Text("Login Credentials")
                }

            }
            .multilineTextAlignment(.trailing)


            Section(header: Text("General")) {
                NavigationLink {
                    if model.account != nil {
                        LazyClosureView(ServerDetails(xmppAccount: model.account!))
                    } else {
                        ContentUnavailableShimView("Account Disabled", systemImage: "iphone.homebutton.slash", description: Text("Cannot display server information as the account is disabled."))
                    }
                } label: {
                    HStack {
                        Text("Server Information")
                        Spacer()
                        Image(systemName: "info.circle")
                            .foregroundStyle(Color.accentColor)
                    }
                }

                NavigationLink {
                    if model.account != nil {
                        LazyClosureView(EmptyView())
                    } else {
                        ContentUnavailableShimView("Account Disabled", systemImage: "iphone.homebutton.slash", description: Text("Cannot change the password as the account is disabled."))
                    }
                } label: {
                    Text("Change Password")
                }

                NavigationLink {
                    if accountID != nil {
                        LazyClosureView(
                            OmemoKeysView(omemoKeys: OmemoKeysForChat(viewContact: ObservableKVOWrapper<MLContact>(self.ownContact)))
                        )
                    } else {
                        ContentUnavailableShimView("Non-existing Account", systemImage: "iphone.homebutton.slash", description: Text("Cannot display keys as the account doesn't exist."))
                    }
                } label: {
                    Text("Encryption Keys (OMEMO)")
                }

                NavigationLink {
                    if model.account != nil {
                        LazyClosureView(BlockedUsers(xmppAccount: model.account!))
                    } else {
                        ContentUnavailableShimView("Account Disabled", systemImage: "iphone.homebutton.slash", description: Text("Cannot display blocked addresses as the account is disabled."))
                    }
                } label: {
                    Text("Blocked Users")
                }
            }

            Section {
                Button(role: .destructive, action: {showingClearHistoryConfirmation = true}) {
                    Text("Clear Chat History")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .confirmationDialog(
                    "Clear Chat History",
                    isPresented: $showingClearHistoryConfirmation,
                    actions: {
                        Button("Confirm", role: .destructive) {
                            // Handle the clearing of chat history
                            guard accountID != nil else { return }
                            DataLayer.sharedInstance().clearMessages(self.accountID!)

                            // TODO: replace with MLNotificationQueue.currentQueue.post, and consider moving it inside DataLayer.clearMessages. Though note that the DataLayer doesn't currently handle any notifications.
                            NotificationCenter.default.post(name: NSNotification.Name("kMonalRefresh"), object: nil)

                            // TODO: show an indicator of success.
                        }
                    },
                    message: {
                        Text("This will clear the whole chat history of this account from this device.")
                    }
                )

                Button(role: .destructive, action: {showingRemoveAccountConfirmation = true}) {
                    Text("Remove account from this device")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .confirmationDialog(
                    "Remove Account",
                    isPresented: $showingRemoveAccountConfirmation,
                    actions: {
                        Button("Confirm", role: .destructive) {
                            // Handle the removal of the account
                            guard accountID != nil else { return }
                            DDLogVerbose("Removing accountID \(self.accountID)")
                            MLXMPPManager.sharedInstance().removeAccount(forAccountID: self.accountID!)
                            // TODO: add something to show success to the user

                            handlePostAccountRemoval(executionStartTime: 0.3)
                        }
                    },
                    message: {
                        Text("This will remove this account and the associated data from this device.")
                    }
                )

                Button(
                    role: .destructive,
                    action: {
                        guard let accountState = model.account?.accountState.rawValue,
                              accountState >= xmppState.stateBound.rawValue else {
                            alertPrompt.title = Text("Error Deleting Account")
                            alertPrompt.message = Text("Your account must be enabled and connected, to be deleted from the server!")
                            showAlert = true
                            return
                        }
                        showingDeleteAccountConfirmation = true
                    },
                    label: {
                        Text("Delete Account on server")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                )
                .confirmationDialog(
                    "Delete Account",
                    isPresented: $showingDeleteAccountConfirmation,
                    actions: {
                        Button("Confirm", role: .destructive) {
                            // Handle the deletion of the account
                            DDLogVerbose("Deleting account on server: \(model.account)")
                            model.account?.removeFromServer { error in
                                DispatchQueue.main.async {
                                    if (error != nil) {
                                        alertPrompt.title = Text("Error Deleting Account")
                                        alertPrompt.message = Text(error!)
                                        showAlert = true
                                    } else {
                                        // TODO: something to indicate success

                                        handlePostAccountRemoval(executionStartTime: 0.3)
                                    }
                                }
                            }
                        }
                    },
                    message: {
                        Text("This will delete this account and the associated data from the server and this device. Data might still be retained on other devices, though.")
                    }
                )

            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in
                return 0
            }

        }
        .alert(
            alertPrompt.title,
            isPresented: $showAlert,
            actions: { Button("Close"){} },
            message: { alertPrompt.message }
        )
        .navigationTitle("Account Settings")
        .navigationBarTitleDisplayMode(.inline)
        .addLoadingOverlay(overlay)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalAccountSettingsRefresh")).receive(on: RunLoop.main)) { notification in
            guard let notificationAccountID = notification.userInfo?["accountID"] as? NSNumber,
                  notificationAccountID.intValue == model.account?.accountID.intValue else {
                return
            }

            DispatchQueue.main.async {
                // Reload roster name, status message and avatar from the DB
                if let settings = DataLayer.sharedInstance().details(forAccount: self.accountID!) {
                    model.rosterName = settings["rosterName"] as? String ?? ""
                    model.statusMessage = settings["statusMessage"] as? String ?? ""
                    model.avatar = MLImageManager.sharedInstance().getIconFor(self.ownContact)
                }

                DDLogVerbose("Got server-side account-settings (display name, status message and avatar) update from account \(model.account!)...")
                hideLoadingOverlay(overlay)
            }
        }

    }
}
