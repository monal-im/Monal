//
//  RegisterAccount.swift
//  Monal
//
//  Created by CC on 22.04.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SafariServices
import WebKit
import FrameUp

struct WebView: UIViewRepresentable {
    var url: URL
 
    func makeUIView(context: Context) -> WKWebView {
        return WKWebView()
    }
 
    func updateUIView(_ webView: WKWebView, context: Context) {
        var request = URLRequest(url: url)
        if HelperTools.defaultsDB().bool(forKey:"useDnssecForAllConnections") {
            request.requiresDNSSECValidation = true;
        }
        webView.load(request)
    }
}

struct RegisterAccount: View {
    static private let xmppFaultyPattern = ".+\\..{2,}$"
    static private let credFaultyPattern = ".*@.*"
    static private let XMPPServer: [Dictionary<String, String>] = [
        ["XMPPServer": "Input", "TermsSite_default": ""],
        ["XMPPServer": "conversations.im", "TermsSite_default": "https://account.conversations.im/privacy/"],
        ["XMPPServer": "yax.im", "TermsSite_default": "https://yaxim.org/yax.im/"]
    ]

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var repeatedPassword: String = ""
    @State private var registerToken: String?
    @State private var completionHandler:((AnyObject?)->Void)?

    @State private var providedServer: String = ""
    @State private var selectedServerIndex = Int.random(in: 1 ..< XMPPServer.count)

    @State private var showAlert = false
    @State private var registerComplete = false
    @State private var registeredAccountNo = -1

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

    init(delegate: SheetDismisserProtocol, registerData:[String:AnyObject]? = nil) {
        self.delegate = delegate
        if let registerData = registerData {
            DDLogDebug("RegisterAccount created with data: \(registerData)");
            //for State stuff see https://forums.swift.org/t/assignment-to-state-var-in-init-doesnt-do-anything-but-the-compiler-gened-one-works/35235
            self._selectedServerIndex = State(wrappedValue:0)
            self._providedServer = State(wrappedValue:(registerData["host"] as? String) ?? "")
            self._username = State(wrappedValue:(registerData["username"] as? String) ?? "")
            self._registerToken = State(wrappedValue:registerData["token"] as? String)
            if let completion = registerData["completion"] {
                self._completionHandler = State(wrappedValue:objcCast(completion) as monal_id_block_t)
            }
            DDLogVerbose("registerToken is now: \(String(describing:self.registerToken))")
            DDLogVerbose("Completion handler is now: \(String(describing:self.completionHandler))")
        }
    }
    
    private var serverSelectedAlert: Bool {
        alertPrompt.title = Text("No XMPP server!")
        alertPrompt.message = Text("Please select a XMPP server or provide one.")
        return serverSelected
    }

    private var serverProvidedAlert: Bool {
        alertPrompt.title = Text("No XMPP server!")
        alertPrompt.message = Text("Please select a XMPP server or provide one.")
        return serverProvided
    }

    private var xmppServerFaultyAlert: Bool {
        alertPrompt.title = Text("XMPP server domain not valid!")
        alertPrompt.message = Text("Please provide a valid XMPP server domain or select one.")
        return xmppServerFaulty
    }

    private var credentialsEnteredAlert: Bool {
        alertPrompt.title = Text("No Empty Values!")
        alertPrompt.message = Text("Please make sure you have entered a username, password.")
        return credentialsEntered
    }
    
    private var passwordsMatchAlert: Bool {
        alertPrompt.title = Text("Passwords don't match!")
        alertPrompt.message = Text("Please make sure you have entered the same password in both password fields.")
        return passwordsMatch
    }

    private var credentialsFaultyAlert: Bool {
        alertPrompt.title = Text("Invalid Username!")
        alertPrompt.message = Text("The username does not need to have an @ symbol. Please try again.")
        return credentialsFaulty
    }

    private var credentialsExistAlert: Bool {
        alertPrompt.title = Text("Duplicate Account!")
        alertPrompt.message = Text("This account already exists on this instance.")
        return credentialsExist
    }
    
    private func showRegistrationAlert(alertMessage: String?) {
        alertPrompt.title = Text("Registration Error")
        alertPrompt.message = Text(alertMessage ?? NSLocalizedString("Could not register your username. Please check your code or change the username and try again.", comment: ""))
        hideLoadingOverlay(overlay)
        showAlert = true
    }
    
    private func showSuccessAlert() {
        alertPrompt.title = Text("Success!")
        alertPrompt.message = Text("You are set up and connected. People can message you at: \(self.username)@\(self.actualServer)")
        hideLoadingOverlay(overlay)
        showAlert = true
    }

    private var actualServer: String {
        let tmp = RegisterAccount.XMPPServer[$selectedServerIndex.wrappedValue]["XMPPServer"]
        return (tmp != nil && tmp != "Input") ? tmp! : serverProvided && !xmppServerFaulty ? providedServer : "?"
    }

    private var serverSelected: Bool {
        return selectedServerIndex != 0
    }

    private var serverProvided: Bool {
        return providedServer != ""
    }

    private var xmppServerFaulty: Bool {
        return providedServer.range(of: RegisterAccount.xmppFaultyPattern, options:.regularExpression) == nil
    }

    private var credentialsEntered: Bool {
        return !username.isEmpty && !password.isEmpty
    }
    
    private var passwordsMatch: Bool {
        return password == repeatedPassword
    }

    private var credentialsFaulty: Bool {
        return username.range(of: RegisterAccount.credFaultyPattern, options: .regularExpression) != nil
    }

    private var credentialsExist: Bool {
        return DataLayer.sharedInstance().doesAccountExistUser(username, andDomain:actualServer)
    }

    private var registerButtonDisabled: Bool {
	return (!serverSelected && (!serverProvided || xmppServerFaulty)) || (!credentialsEntered || !passwordsMatch || credentialsFaulty || credentialsExist)
    }

    private func createXMPPInstance() -> xmpp {
        let identity = MLXMPPIdentity.init(jid: String.init(format: "nothing@%@", self.actualServer), password: "nothing", andResource: "MonalReg");
        let server = MLXMPPServer.init(host: "", andPort: 5222, andDirectTLS: false)
        return xmpp.init(server: server, andIdentity: identity, andAccountNo: -1)
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

                    let accountNo = DataLayer.sharedInstance().addAccount(with: dic);
                    if(accountNo != nil) {
                        self.registeredAccountNo = accountNo!.intValue
                        MLXMPPManager.sharedInstance().addNewAccountToKeychainAndConnect(withPassword:self.password, andAccountNo:accountNo!)
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
                self.xmppAccount!.requestRegForm(withToken: self.registerToken, andCompletion: {captchaData, hiddenFieldsDict in
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
        let chosenServer = RegisterAccount.XMPPServer[$selectedServerIndex.wrappedValue]
        return URL(string: (chosenServer["TermsSite_\(languageCode ?? "default")"] ?? chosenServer["TermsSite_default"])!)!
    }

    var body: some View {
        ZStack {
            /// Ensure the ZStack takes the entire area
            Color.clear
            
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading) {
                        VStack(alignment: .leading) {
                            Text("Like email, you can register your account on many sites and talk to anyone. You can use this page to register an account with a selected or provided XMPP server. You also have to choose a username and a password.")
                                .padding()
                        }
                        .background(Color(UIColor.systemBackground))

                        Form {
                            Text("I need an account:")
                                .listRowSeparator(.hidden)
                            
                            Menu {
                                Picker("", selection: $selectedServerIndex) {
                                    ForEach (RegisterAccount.XMPPServer.indices, id: \.self) {
                                        if($0 == 0) {
                                            Text("Manual input").tag(0)
                                        }
                                        else {
                                            Text(RegisterAccount.XMPPServer[$0]["XMPPServer"] ?? "").tag($0)
                                        }
                                    }
                                }
                                .onChange(of: selectedServerIndex, perform: { (_) in
                                    self.captchaImg = nil
                                    self.captchaText = ""
                                    self.xmppAccount = nil
                                    self.registerToken = nil
                                })
                                .labelsHidden()
                                .pickerStyle(.inline)
                            }
                            label: {
                                HStack {
                                    if(selectedServerIndex != 0) {
                                        Text(RegisterAccount.XMPPServer[selectedServerIndex]["XMPPServer"]!).font(.system(size: 17)).frame(maxWidth: .infinity)
                                        Image(systemName: "checkmark")
                                    }
                                    else {
                                        Text("Manual input")
                                            .font(.system(size: 17))
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .padding(9.0)
                                .background(Color(UIColor.tertiarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .disabled(self.registerToken != nil)
                            .listRowSeparator(.hidden)

                            Group {
                                if(selectedServerIndex == 0) {
                                    TextField(NSLocalizedString("Provide XMPP-Server", comment: "placeholder when creating account"), text: Binding(
                                        get: { self.providedServer },
                                        set: { string in self.providedServer = string.lowercased().replacingOccurrences(of: " ", with: "") }
                                    ))
                                    .textInputAutocapitalization(.never)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .foregroundColor(self.registerToken != nil ? .secondary : .primary)
                                    .disabled(self.registerToken != nil)
                                    .listRowSeparator(.hidden)
                                }

                                TextField(NSLocalizedString("Username", comment: "placeholder when creating account"), text: Binding(
                                    get: { self.username },
                                    set: { string in self.username = string.lowercased().replacingOccurrences(of: " ", with: "") }
                                ))
                                .textInputAutocapitalization(.never)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .listRowSeparator(.hidden)
                            
                                SecureField(NSLocalizedString("Password", comment: "placeholder when creating account"), text: $password)
                                    .listRowSeparator(.hidden)
                                SecureField(NSLocalizedString("Password (repeated)", comment: "placeholder when creating account"), text: $repeatedPassword)
                                    .listRowSeparator(.hidden)
                            }
                            
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
                                showAlert = (!serverSelectedAlert && (!serverProvidedAlert || xmppServerFaultyAlert)) || (!credentialsEnteredAlert || !passwordsMatchAlert || credentialsFaultyAlert || credentialsExistAlert)

                                if(!showAlert) {
                                    self.errorObserverEnabled = true
                                    if(self.captchaImg == nil) {
                                        fetchRequestForm()
                                    } else {
                                        register()
                                    }
                                }
                            }){
                                Text("Register with \(actualServer)")
                                    .frame(maxWidth: .infinity)
                                    .padding(9.0)
                                    .background(Color(UIColor.tertiarySystemFill))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .disabled(registerButtonDisabled)
                            .listRowSeparator(.hidden)
                            .alert(isPresented: $showAlert) {
                                Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton: .default(alertPrompt.dismissLabel, action: {
                                    if(self.registerComplete == true) {
                                        self.delegate.dismiss()
                                        
                                        if let completion = self.completionHandler {
                                            DDLogVerbose("Calling reg completion handler...")
                                            completion(self.registeredAccountNo as NSNumber)
                                        }
                                    }
                                }))
                            }
                            Text("The selectable XMPP servers are public servers which are not affiliated to Monal. This registration page is provided for convenience only.")
                            .font(.system(size: 10))
                            .padding(.vertical, 8)

                            if(selectedServerIndex != 0) {
                                Button (action: {
                                    showWebView.toggle()
                                }){
                                    Text("Terms of use for \(RegisterAccount.XMPPServer[$selectedServerIndex.wrappedValue]["XMPPServer"]!)")
                                        .font(.system(size: 10))
                                }
                                .frame(maxWidth: .infinity)
                                .sheet(isPresented: $showWebView) {
                                    NavigationStack {
                                        WebView(url: termsSiteForCurrentLanguage())
                                            .navigationBarTitle(Text("Terms of \(RegisterAccount.XMPPServer[$selectedServerIndex.wrappedValue]["XMPPServer"]!)"), displayMode: .inline)
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
                        }
                        .textFieldStyle(.roundedBorder)
                    }
                    /// Sets the minimum frame height to the available height of the scrollview and the maxHeight to infinity
                    .frame(minHeight: proxy.size.height, maxHeight: .infinity)
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
                if(xmppAccount.accountNo.intValue == self.registeredAccountNo || xmppAccount.accountNo.intValue == -1) {
                    DispatchQueue.main.async {
                        DDLogDebug("XMPP account matches registering one")
                        self.errorObserverEnabled = false
                        xmppAccount.disconnect(true)        //disconnect account (even if not listed in connectedAccounts and having id -1)
                        MLXMPPManager.sharedInstance().removeAccount(forAccountNo:xmppAccount.accountNo)     //remove from connectedAccounts and db, if listed, do nothing otherwise (e.g. in the -1 case)
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
                if(xmppAccount.accountNo.intValue == self.registeredAccountNo) {
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

struct RegisterAccount_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        RegisterAccount(delegate:delegate)
    }
}
