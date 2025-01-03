//
//  WelcomeLogIn.swift
//  Monal
//
//  Created by CC on 22.04.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

struct WelcomeLogIn: View {
    static private let credFaultyPattern = "^.+@.+\\..{2,}$"
    
    var advancedMode: Bool = false
    var delegate: SheetDismisserProtocol

    @State private var isEditingJid: Bool = false
    @State private var jid: String = ""
    @State private var isEditingPassword: Bool = false
    @State private var password: String = ""

    @State private var hardcodedServer: String = ""
    @State private var hardcodedPort: String = "5222"
    @State private var allowPlainAuth: Bool = false
    @State private var forceDirectTLS: Bool = false

    @State private var showAlert = false
    @State private var showQRCodeScanner = false

    // login related
    @State private var currentTimeout : DispatchTime? = nil
    @State private var errorObserverEnabled = false
    @State private var newAccountID: NSNumber? = nil
    @State private var loginComplete = false
    @State private var isLoadingOmemoBundles = false
    
    @State private var alertPrompt = AlertPrompt()
    @StateObject private var overlay = LoadingOverlayState()

#if IS_ALPHA
    let appLogoId = "AlphaAppLogo"
#elseif IS_QUICKSY
    let appLogoId = "QuicksyAppLogo"
#else
    let appLogoId = "AppLogo"
#endif
    
    private var credentialsEnteredAlert: Bool {
        alertPrompt.title = Text("Empty Values!")
        alertPrompt.message = Text("Please make sure you have entered both a username and password.")
        alertPrompt.dismissLabel = Text("Close")
        return credentialsEntered
    }

    private var credentialsFaultyAlert: Bool {
        alertPrompt.title = Text("Invalid Credentials!")
        alertPrompt.message = Text("Your XMPP jid should be in in the format user@domain.tld. For special configurations, use manual setup.")
        alertPrompt.dismissLabel = Text("Close")
        return credentialsFaulty
    }

    private var credentialsExistAlert: Bool {
        alertPrompt.title = Text("Duplicate jid!")
        alertPrompt.message = Text("This account already exists in Monal.")
        alertPrompt.dismissLabel = Text("Close")
        return credentialsExist
    }

    private func showTimeoutAlert() {
        DDLogVerbose("Showing timeout alert...")
        hideLoadingOverlay(overlay)
        alertPrompt.title = Text("Timeout Error")
        alertPrompt.message = Text("We were not able to connect your account. Please check your username and password and make sure you are connected to the internet.")
        alertPrompt.dismissLabel = Text("Close")
        showAlert = true
    }

    private func showSuccessAlert() {
        hideLoadingOverlay(overlay)
        alertPrompt.title = Text("Success!")
        alertPrompt.message = Text("You are set up and connected.")
        alertPrompt.dismissLabel = Text("Close")
        showAlert = true
    }

    private func showLoginErrorAlert(errorMessage: String) {
        hideLoadingOverlay(overlay)
        alertPrompt.title = Text("Error")
        alertPrompt.message = Text(String(format: NSLocalizedString("We were not able to connect your account. Please check your username and password and make sure you are connected to the internet.\n\nTechnical error message: %@", comment: ""), errorMessage))
        alertPrompt.dismissLabel = Text("Close")
        showAlert = true
    }

    private func showPlainAuthWarningAlert() {
        alertPrompt.title = Text("Warning")
        alertPrompt.message = Text("If you turn this on, you will no longer be safe from man-in-the-middle attacks. Such attacks enable the adversary to manipulate your incoming and outgoing messages, add their own OMEMO keys, change your account details and even know or change your password!\n\nYou should rather switch to another server than turning this on.")
        alertPrompt.dismissLabel = Text("Understood")
        showAlert = true
    }

    private var jidDomainPart: String {
        let jidComponents = HelperTools.splitJid(jid)
        return jidComponents["host"] ?? ""
    }

    private var credentialsEntered: Bool {
        return !jid.isEmpty && !password.isEmpty
    }
    
    private var credentialsFaulty: Bool {
        return jid.range(of: WelcomeLogIn.credFaultyPattern, options:.regularExpression) == nil
    }
    
    private var credentialsExist: Bool {
        let components = jid.components(separatedBy: "@")
        return DataLayer.sharedInstance().doesAccountExistUser(components[0], andDomain:components[1])
    }

    private var loginButtonDisabled: Bool {
        return !credentialsEntered || credentialsFaulty
    }
    
    private func startLoginTimeout() {
        let newTimeout = DispatchTime.now() + 30.0;
        self.currentTimeout = newTimeout
        DispatchQueue.main.asyncAfter(deadline: newTimeout) {
            if(newTimeout == self.currentTimeout) {
                DDLogWarn("First login timeout triggered...")
                if(self.newAccountID != nil) {
                    DDLogVerbose("Removing account...")
                    MLXMPPManager.sharedInstance().removeAccount(forAccountID: self.newAccountID!)
                    self.newAccountID = nil
                }
                self.currentTimeout = nil
                showTimeoutAlert()
            }
        }
    }

    var body: some View {
        ZStack {
            /// Ensure the ZStack takes the entire area
            Color.clear
            
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading) {
                        if !advancedMode {
                            VStack {
                                HStack () {
                                    Image(decorative: appLogoId)
                                        .resizable()
                                        .frame(width: CGFloat(120), height: CGFloat(120), alignment: .center)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .padding()

                                    Text("Log in to your existing account or register a new account. If required you will find more advanced options in Monal settings.")
                                        .padding()
                                        .padding(.leading, -16.0)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .background(Color(UIColor.systemBackground))
                        }

                        Form {
                            Text("I already have an account:")
                                .listRowSeparator(.hidden)
                            
                            TextField(NSLocalizedString("user@domain.tld", comment: "placeholder when adding account"), text: Binding(
                                get: { self.jid },
                                set: { string in self.jid = string.lowercased().replacingOccurrences(of: " ", with: "") }), onEditingChanged: { isEditingJid = $0 }
                            )
                            .textInputAutocapitalization(.never)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .addClearButton(isEditing: isEditingJid, text: $jid)
                            .listRowSeparator(.hidden)
                            
                            SecureField(NSLocalizedString("Password", comment: "placeholder when adding account"), text: $password)
                                .addClearButton(isEditing:  password.count > 0, text: $password)
                                .listRowSeparator(.hidden)

                            if advancedMode {
                                TextField(NSLocalizedString("Optional Hardcoded Hostname", comment: "advanced account settings"), text: $hardcodedServer)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                                    .addClearButton(isEditing:  hardcodedServer.count > 0, text: $hardcodedServer)
                                    .listRowSeparator(.hidden)

                                if !hardcodedServer.isEmpty {
                                    HStack {
                                        Text("Port")
                                        Spacer()
                                        TextField(NSLocalizedString("Optional Hardcoded Port", comment: "advanced account settings"), text: $hardcodedPort)
                                            .keyboardType(.numberPad)
                                            .addClearButton(isEditing:  hardcodedPort.count > 0, text: $hardcodedPort)
                                            .onDisappear {
                                                hardcodedPort = "5222"
                                            }
                                    }
                                    .listRowSeparator(.hidden)

                                    Toggle(isOn: $forceDirectTLS) {
                                        Text("Always use direct TLS, not STARTTLS")
                                    }
                                    .onDisappear {
                                        forceDirectTLS = false
                                    }
                                }

                                Toggle(isOn: $allowPlainAuth) {
                                    Text("Allow MITM-prone PLAIN authentication")
                                }
                                // TODO: use the SCRAM preload list instead of hardcoding servers
                                .disabled(["conversations.im"].contains(jidDomainPart.lowercased()))
                                .onChange(of: jid) { _ in
                                    if ["conversations.im"].contains(jidDomainPart.lowercased()) {
                                        allowPlainAuth = false
                                    }
                                }
                                .onChange(of: allowPlainAuth) { _ in
                                    if allowPlainAuth {
                                        showPlainAuthWarningAlert()
                                    }
                                }
                            }

                            HStack() {
                                Button(action: {
                                    showAlert = !credentialsEnteredAlert || credentialsFaultyAlert || credentialsExistAlert

                                    if (!showAlert) {
                                        startLoginTimeout()
                                        showLoadingOverlay(overlay, headline:NSLocalizedString("Logging in", comment: ""))
                                        self.errorObserverEnabled = true
                                        if advancedMode {
                                            self.newAccountID = MLXMPPManager.sharedInstance().login(self.jid, password: self.password, hardcodedServer:self.hardcodedServer, hardcodedPort:self.hardcodedPort, forceDirectTLS: self.forceDirectTLS, allowPlainAuth: self.allowPlainAuth)
                                        } else {
                                            self.newAccountID = MLXMPPManager.sharedInstance().login(self.jid, password: self.password)
                                        }
                                        if(self.newAccountID == nil) {
                                            currentTimeout = nil // <- disable timeout on error
                                            errorObserverEnabled = false
                                            showLoginErrorAlert(errorMessage:NSLocalizedString("Account already configured in Monal!", comment: ""))
                                            self.newAccountID = nil
                                        }
                                    }
                                }){
                                    Text("Login")
                                        .frame(maxWidth: .infinity)
                                        .padding(9.0)
                                        .background(Color(UIColor.tertiarySystemFill))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .disabled(loginButtonDisabled)
                                .alert(isPresented: $showAlert) {
                                    Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton: .default(alertPrompt.dismissLabel, action: {
                                        if(self.loginComplete == true) {
                                            self.delegate.dismiss()
                                        }
                                    }))
                                }

                                if !advancedMode {
                                    // Just sets the credential in jid and password variables and shows them in the input fields
                                    // so user can control what they scanned and if o.k. login via the "Login" button.
                                    Button(action: {
                                        showQRCodeScanner = true
                                    }){
                                        Image(systemName: "qrcode")
                                            .frame(maxHeight: .infinity)
                                            .padding(9.0)
                                            .background(Color(UIColor.tertiarySystemFill))
                                            .foregroundColor(.primary)
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                    .sheet(isPresented: $showQRCodeScanner) {
                                        Text("QR-Code Scanner").font(.largeTitle.weight(.bold))
                                        // Get existing credentials from QR and put values in jid and password
                                        MLQRCodeScanner(
                                            handleLogin: { jid, password in
                                                self.jid = jid
                                                self.password = password
                                            }, handleClose: {
                                                self.showQRCodeScanner = false
                                            }
                                        )
                                    }
                                }

                            }
                            .listRowSeparator(.hidden, edges: .top)
                            // Align the (bottom) list row separator to the very left
                            .alignmentGuide(.listRowSeparatorLeading) { _ in
                                return 0
                            }

                            NavigationLink(destination: LazyClosureView(RegisterAccount(delegate: self.delegate))) {
                                Text("Register a new account")
                                    .foregroundColor(Color.accentColor)
                            }
                            
                            if(DataLayer.sharedInstance().enabledAccountCnts() == 0) {
                                Button(action: {
                                    self.delegate.dismiss()
                                }){
                                    Text("Set up account later")
                                        .frame(maxWidth: .infinity)
                                        .padding(.top, 10.0)
                                        .padding(.bottom, 9.0)
                                        .foregroundColor(Color(UIColor.systemGray))
                                }
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            UITableView.appearance().tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 30))
                        }
                    }
                    /// Sets the minimum frame height to the available height of the scrollview and the maxHeight to infinity
                    .frame(minHeight: proxy.size.height, maxHeight: .infinity)
                }
            }
        }
        .addLoadingOverlay(overlay)
        .navigationTitle(advancedMode ? Text("Add Account (advanced)") : Text("Welcome"))
        .navigationBarTitleDisplayMode(advancedMode ? .inline : .large)
        .onDisappear {UITableView.appearance().tableHeaderView = nil}       //why that??
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kXMPPError")).receive(on: RunLoop.main)) { notification in
            if(self.errorObserverEnabled == false) {
                return
            }
            if let xmppAccount = notification.object as? xmpp, let newAccountID : NSNumber = self.newAccountID, let errorMessage = notification.userInfo?["message"] as? String {
                if(xmppAccount.accountID.intValue == newAccountID.intValue) {
                    DispatchQueue.main.async {
                        currentTimeout = nil // <- disable timeout on error
                        errorObserverEnabled = false
                        showLoginErrorAlert(errorMessage: errorMessage)
                        MLXMPPManager.sharedInstance().removeAccount(forAccountID: newAccountID)
                        self.newAccountID = nil
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMLResourceBoundNotice")).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let newAccountID : NSNumber = self.newAccountID {
                if(xmppAccount.accountID.intValue == newAccountID.intValue) {
                    DispatchQueue.main.async {
                        currentTimeout = nil // <- disable timeout on successful connection
                        self.errorObserverEnabled = false
                        showLoadingOverlay(overlay, headline:NSLocalizedString("Loading contact list", comment: ""))
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalUpdateBundleFetchStatus")).receive(on: RunLoop.main)) { notification in
            if let notificationAccountID = notification.userInfo?["accountID"] as? NSNumber, let completed = notification.userInfo?["completed"] as? NSNumber, let all = notification.userInfo?["all"] as? NSNumber, let newAccountID : NSNumber = self.newAccountID {
                if(notificationAccountID.intValue == newAccountID.intValue) {
                    isLoadingOmemoBundles = true
                    showLoadingOverlay(
                        overlay, 
                        headline:NSLocalizedString("Loading omemo bundles", comment: ""),
                        description:String(format: NSLocalizedString("Loading omemo bundles: %@ / %@", comment: ""), completed, all)
                    )
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalFinishedOmemoBundleFetch")).receive(on: RunLoop.main)) { notification in
            if let notificationAccountID = notification.userInfo?["accountID"] as? NSNumber, let newAccountID : NSNumber = self.newAccountID {
                if(notificationAccountID.intValue == newAccountID.intValue && isLoadingOmemoBundles) {
                    DispatchQueue.main.async {
                        self.loginComplete = true
                        showSuccessAlert()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalFinishedCatchup")).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let newAccountID : NSNumber = self.newAccountID {
                if(xmppAccount.accountID.intValue == newAccountID.intValue && !isLoadingOmemoBundles) {
                    DispatchQueue.main.async {
                        self.loginComplete = true
                        showSuccessAlert()
                    }
                }
            }
        }
    }
}

struct WelcomeLogIn_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        WelcomeLogIn(delegate:delegate)
    }
}
