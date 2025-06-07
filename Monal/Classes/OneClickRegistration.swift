//
//  OneClickRegistration.swift
//  Monal
//
//  Created by tmolitor on 04.06.25.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import FrameUp

struct OneClickRegistration: View {
    static private let xmppFaultyPattern = ".+\\..{2,}$"
    static private let credFaultyPattern = ".*@.*"
    static private let XMPPServer: [Dictionary<String, String>] = [
        ["XMPPServer": "conversations.im", "TermsSite_default": "https://account.conversations.im/privacy/"],
        ["XMPPServer": "yax.im", "TermsSite_default": "https://yaxim.org/yax.im/"]
    ]
    
#if IS_ALPHA
    let appLogoId = "AlphaAppLogo"
#elseif IS_QUICKSY
    let appLogoId = "QuicksyAppLogo"
#else
    let appLogoId = "AppLogo"
#endif

    @State private var selectedServerIndex = Int.random(in: 0 ..< XMPPServer.count)
    private var actualServer: String {
        return OneClickRegistration.XMPPServer[$selectedServerIndex.wrappedValue]["XMPPServer"]!
    }
    
    @State private var username: String = ""
    @State private var password: String = ""

    @State private var showAlert = false
    @State private var registerComplete = false
    @State private var registeredAccountID = -1

    @State private var xmppAccount: xmpp?
    @State private var captchaImg: Image?
    @State private var hiddenFields: Dictionary<AnyHashable, Any>?
    @State private var captchaText: String = ""

    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))
    @StateObject private var overlay = LoadingOverlayState()
    @State private var currentTimeout : DispatchTime? = nil

    @State private var showWebView = false
    @State private var errorObserverEnabled = false

    var delegate: SheetDismisserProtocol

    init(delegate: SheetDismisserProtocol) {
        self.delegate = delegate
        
        //for State stuff see https://forums.swift.org/t/assignment-to-state-var-in-init-doesnt-do-anything-but-the-compiler-gened-one-works/35235
        self._username = State(wrappedValue:("ML-"+HelperTools.generateRandomPassword()).lowercased())
        self._password = State(wrappedValue:HelperTools.generateRandomPassword())
        
        self.xmppAccount = createXMPPInstance()
    }
    
    private func showRegistrationAlert(alertMessage: String?) {
        alertPrompt.title = Text("Registration Error")
        alertPrompt.message = Text(alertMessage ?? NSLocalizedString("Could not register you. Please check the captcha and try again.", comment: ""))
        hideLoadingOverlay(overlay)
        showAlert = true
    }
    
    private func showSuccessAlert() {
        alertPrompt.title = Text("Success!")
        alertPrompt.message = Text("You are set up and connected. People can message you at: \(self.username)@\(self.actualServer)")
        hideLoadingOverlay(overlay)
        showAlert = true
    }

    private func createXMPPInstance() -> xmpp {
        let identity = MLXMPPIdentity.init(jid: String.init(format: "nothing@%@", self.actualServer), password: "nothing", andResource: "MonalReg");
        let server = MLXMPPServer.init(host: "", andPort: 5222, andDirectTLS: false)
        return xmpp.init(server: server, andIdentity: identity, andAccountID: -1)
    }

    private func cleanupXMPPInstance() {
        if(self.xmppAccount != nil) {
            DDLogDebug("Disconnecting registering xmpp account...")
            self.xmppAccount!.disconnect(true)
        }
        self.xmppAccount = nil;
    }
    
    private func register() {
        showLoadingOverlay(overlay, headline:NSLocalizedString("Registering account...", comment: ""))
        if(self.xmppAccount == nil) {
            self.xmppAccount = createXMPPInstance()
        }
        self.xmppAccount!.registerUser(self.username, withPassword: self.password, captcha: self.captchaText.isEmpty == true ? nil : self.captchaText, andHiddenFields: self.hiddenFields) {success, errorMsg in
            DispatchQueue.main.async {
                if(success == true) {
                    let dic = [
                        kDomain: self.actualServer,
                        kUsername: self.username,
                        kResource: HelperTools.encodeRandomResource(),
                        kEnabled: true,
                        kDirectTLS: false,
                        //creating an account involves transfering the password in cleartext only secured by TLS
                        //--> logging in directly afterwards using PLAIN doesn't make the situation any worse ==> allow it
                        //conversations.im already supports sasl2 and scram ## TODO: use SCRAM preload list
                        //using the preload list in this case won't solve the situation, but increase the attack cost because
                        //stripping off SASL2 won't suffice anymore (the attacker will have to use the password sniffed during account creation
                        //to fake the SCRAM HMAC sent to both client and server)
                        kPlainActivated: self.actualServer == "conversations.im" ? false : true,
                    ] as [String : Any]

                    let accountID = DataLayer.sharedInstance().addAccount(with: dic);
                    if(accountID != nil) {
                        self.registeredAccountID = accountID!.intValue
                        MLXMPPManager.sharedInstance().addNewAccountToKeychainAndConnect(withPassword:self.password, andAccountID:accountID!)
                        cleanupXMPPInstance()
                    } else {
                        cleanupXMPPInstance()
                        showRegistrationAlert(alertMessage:NSLocalizedString("Account already configured in Monal!", comment: ""))
                        self.captchaText = ""
                        if(self.captchaImg != nil) {
                            fetchRequestForm() // < force reload the form to update the captcha
                        }
                    }
                } else {
                    cleanupXMPPInstance()
                    showRegistrationAlert(alertMessage:errorMsg)
                    self.captchaText = ""
                    if(self.captchaImg != nil) {
                        fetchRequestForm() // < force reload the form to update the captcha
                    }
                }
            }
        }
    }

    private func fetchRequestForm() {
        //dispatch after 50ms because otherwise we get an "Modifying state during view update, this will cause undefined behaviour" error 
        //undefined in our case seems to mean: we get only the blurring effect but the loading overlay will only be shown after an ui update
        //update: we still get this error even when using this timeout, but at least the ui is rendered properly
        let newTimeout = DispatchTime.now() + 0.05
        self.currentTimeout = newTimeout
        DispatchQueue.main.asyncAfter(deadline: newTimeout) {
            if(newTimeout == self.currentTimeout) {
                showLoadingOverlay(overlay, headline:NSLocalizedString("Fetching registration form...", comment: ""))
                if(self.xmppAccount != nil) {
                    self.xmppAccount!.disconnect(true)
                }
                self.xmppAccount = createXMPPInstance()
                self.xmppAccount!.requestRegForm(withToken:nil, andCompletion: {captchaData, hiddenFieldsDict in
                    DispatchQueue.main.async {
                        self.hiddenFields = hiddenFieldsDict
                        if(captchaData.isEmpty == true) {
                            register()
                        } else {
                            //only disconnect if waiting for captcha input (to make sure we don't get any spurious timeout errors from the server)
                            if(self.xmppAccount != nil) {
                                self.xmppAccount!.disconnect(true)
                                self.xmppAccount = nil
                            }
                            hideLoadingOverlay(overlay)
                            let captchaUIImg = UIImage.init(data: captchaData)
                            if(captchaUIImg != nil) {
                                self.captchaImg = Image(uiImage: captchaUIImg!)
                            } else {
                                cleanupXMPPInstance()
                                showRegistrationAlert(alertMessage: NSLocalizedString("Could not read captcha!", comment: ""))
                            }
                        }
                    }
                }, andErrorCompletion: {_, errorMsg in
                    DispatchQueue.main.async {
                        cleanupXMPPInstance()
                        showRegistrationAlert(alertMessage: errorMsg)
                    }
                })
            }
        }
    }

    private func termsSiteForCurrentLanguage() -> URL {
        let languageCode = Locale.current.language.languageCode?.identifier
        let chosenServer = OneClickRegistration.XMPPServer[$selectedServerIndex.wrappedValue]
        return URL(string: (chosenServer["TermsSite_\(languageCode ?? "default")"] ?? chosenServer["TermsSite_default"])!)!
    }

    var body: some View {
        ZStack {
            /// Ensure the ZStack takes the entire area
            Color.clear
            
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading) {
                        HStack () {
                            Image(decorative: appLogoId)
                                .resizable()
                                .frame(width: CGFloat(120), height: CGFloat(120), alignment: .center)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .padding()

                            VStack(alignment: .leading) {
                                Text("This is 1-Click registration. We automatically choose a username, password and public server for you. You can view or change your password in the settings.")
                                    .padding()
                                    .padding(.leading, -16.0)
                            }
                        }
                        
                        Form {
                            if(self.captchaImg != nil) {
                                HStack {
                                    self.captchaImg
                                    Spacer()
                                    Button(action: {
                                        fetchRequestForm()
                                    }, label: {
                                        Image(systemName: "arrow.clockwise")
                                    })
                                    .buttonStyle(.borderless)
                                }
                                .listRowSeparator(.hidden)
                                
                                TextField(NSLocalizedString("Captcha", comment: "placeholder when creating account"), text: $captchaText)
                                    .textInputAutocapitalization(.never)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .listRowSeparator(.hidden)
                            }

                            Button(action: {
                                self.errorObserverEnabled = true
                                if(self.captchaImg == nil) {
                                    fetchRequestForm()
                                } else {
                                    register()
                                }
                            }){
                                Text("Create account on \(actualServer)")
                                    .frame(maxWidth: .infinity)
                                    .padding(9.0)
                                    .background(Color(UIColor.tertiarySystemFill))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            
                            Text("The selected XMPP server is public and not affiliated to Monal. This registration page is provided for convenience only.")
                            .font(.system(size: 10))
                            .padding(.vertical, 8)

                            Button (action: {
                                showWebView.toggle()
                            }){
                                Text("Terms of use for \(OneClickRegistration.XMPPServer[$selectedServerIndex.wrappedValue]["XMPPServer"]!)")
                                    .font(.system(size: 10))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .textFieldStyle(.roundedBorder)
                        
                        Spacer()
                    }
                    /// Sets the minimum frame height to the available height of the scrollview and the maxHeight to infinity
                    .frame(minHeight: proxy.size.height, maxHeight: .infinity)
                    .background(Color(UIColor.systemBackground))
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton: .default(alertPrompt.dismissLabel, action: {
                    if(self.registerComplete == true) {
                        self.delegate.dismiss()
                    }
                }))
            }
            .sheet(isPresented: $showWebView) {
                NavigationStack {
                    WebView(url: termsSiteForCurrentLanguage())
                        .navigationBarTitle(Text("Terms of \(OneClickRegistration.XMPPServer[$selectedServerIndex.wrappedValue]["XMPPServer"]!)"), displayMode: .inline)
                        .toolbar(content: {
                            ToolbarItem(placement: .bottomBar) {
                                Button (action: {
                                    showWebView.toggle()
                                }){
                                    Text("Close")
                                }
                            }
                        })
                }
            }
        }
        .addLoadingOverlay(overlay)
        .navigationBarTitle(Text("Register"), displayMode:.large)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kXMPPError")).receive(on: RunLoop.main)) { notification in
            DDLogDebug("Got xmpp error")
            if(self.errorObserverEnabled == false) {
                return
            }
            if let xmppAccount = notification.object as? xmpp, let errorMessage = notification.userInfo?["message"] as? String {
                if(xmppAccount.accountID.intValue == self.registeredAccountID || xmppAccount.accountID.intValue == -1) {
                    DispatchQueue.main.async {
                        DDLogDebug("XMPP account matches registering one")
                        self.errorObserverEnabled = false
                        xmppAccount.disconnect(true)        //disconnect account (even if not listed in enabledAccounts and having id -1)
                        MLXMPPManager.sharedInstance().removeAccount(forAccountID:xmppAccount.accountID)     //remove from enabledAccounts and db, if listed, do nothing otherwise (e.g. in the -1 case)
                        //reset local state var if the account had id -1 (e.g. is dummy for registering recorded in self.xmppAccount)
                        if(xmppAccount == self.xmppAccount) {
                            self.xmppAccount = nil
                        }
                        showRegistrationAlert(alertMessage: errorMessage)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMLResourceBoundNotice")).receive(on: RunLoop.main)) { notification in
            if(self.registerComplete == true) {
                return
            }
            if let xmppAccount = notification.object as? xmpp {
                if(xmppAccount.accountID.intValue == self.registeredAccountID) {
                    DispatchQueue.main.async {
                        hideLoadingOverlay(overlay)
                        self.errorObserverEnabled = false
                        self.registerComplete = true
                        showSuccessAlert()
                    }
                }
            }
        }
    }
}

struct OneClickRegistration_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        OneClickRegistration(delegate:delegate)
    }
}
