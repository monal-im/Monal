//
//  RegisterAccount.swift
//  Monal
//
//  Created by CC on 22.04.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI
import SafariServices
import WebKit
import monalxmpp

struct WebView: UIViewRepresentable {
    var url: URL
 
    func makeUIView(context: Context) -> WKWebView {
        return WKWebView()
    }
 
    func updateUIView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }
}

struct RegisterAccount: View {
    var delegate: SheetDismisserProtocol

    static let XMPPServer: [Dictionary<String, String>] = [
        ["XMPPServer": "Input", "TermsSite_default": ""],
        ["XMPPServer": "conversations.im", "TermsSite_default": "https://account.conversations.im/privacy/"],
        ["XMPPServer": "yax.im", "TermsSite_default": "https://yaxim.org/yax.im/"],
        ["XMPPServer": "trashserver.net", "TermsSite_default": "https://trashserver.net/en/privacy/", "TermsSite_de": "https://trashserver.net/datenschutz/"]
    ]

    private let xmppServerInputSelectLabel = Text("Manual input")
    
    static private let xmppFaultyPattern = ".+\\..{2,}$"
    static private let credFaultyPattern = ".*@.*"

    @State public var username: String = "aaa"
    @State public var password: String = ""
    @State public var registerToken: String?
    @State public var completionHandler:(()->Void)? = {}

    @State public var providedServer: String = ""
    @State public var selectedServerIndex = Int.random(in: 1 ..< XMPPServer.count)

    @State private var showAlert = false
    @State private var registerComplete = false

    @State private var xmppAccount: xmpp?
    @State private var captchaImg: Image?
    @State private var hiddenFields: Dictionary<AnyHashable, Any> = [:]
    @State private var captchaText: String = ""

    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))
    @StateObject private var overlay = LoadingOverlayState()
    @State private var currentTimeout : DispatchTime? = nil

    @State private var showWebView = false
    @State private var errorObserverEnabled = false

    init(delegate:SheetDismisserProtocol, registerData:[String:Any]? = nil) {
        self.delegate = delegate
        if let registerData = registerData {
            DDLogDebug("Feeding RegisterAccount with data: \(registerData)");
            //for State stuff see https://forums.swift.org/t/assignment-to-state-var-in-init-doesnt-do-anything-but-the-compiler-gened-one-works/35235
            self._selectedServerIndex = State(wrappedValue:0)
            self._providedServer = State(wrappedValue:(registerData["host"] as? String) ?? "")
            self._username = State(wrappedValue:(registerData["username"] as? String) ?? "")
            self._registerToken = State(wrappedValue:registerData["token"] as? String)
            self._completionHandler = State(wrappedValue:(registerData["completion"] as? (()->Void)?) ?? {})
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
        if(self.xmppAccount != nil) {
            DDLogDebug("Disconnecting registering xmpp account...")
            self.xmppAccount!.disconnect(true)
        }
        self.xmppAccount = nil;
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

    private var credentialsFaulty: Bool {
        return username.range(of: RegisterAccount.credFaultyPattern, options: .regularExpression) != nil
    }

    private var credentialsExist: Bool {
        return DataLayer.sharedInstance().doesAccountExistUser(username, andDomain:actualServer)
    }

    private var buttonColor: Color {
        return (!serverSelected && (!serverProvided || xmppServerFaulty)) || (!credentialsEntered || credentialsFaulty || credentialsExist) ? Color(UIColor.systemGray) : Color(UIColor.systemBlue)
    }

    private func createXMPPInstance() -> xmpp {
        let identity = MLXMPPIdentity.init(jid: String.init(format: "nothing@%@", self.actualServer), password: "nothing", andResource: "MonalReg");
        let server = MLXMPPServer.init(host: "", andPort: 5222, andDirectTLS: false)
        return xmpp.init(server: server, andIdentity: identity, andAccountNo: -1)
    }

    private func register() {
        showLoadingOverlay(overlay, headline:NSLocalizedString("Registering account...", comment: ""))
        if(self.xmppAccount != nil) {
            self.xmppAccount!.disconnect(true)
        }
        self.xmppAccount = createXMPPInstance()
        self.xmppAccount!.registerUser(self.username, withPassword: self.password, captcha: self.captchaText.isEmpty == true ? nil : self.captchaText, andHiddenFields: self.hiddenFields) {success, errorMsg in
            DispatchQueue.main.async {
                hideLoadingOverlay(overlay)
                if(success == true) {
                    let dic = [
                        kDomain: self.actualServer,
                        kUsername: self.username,
                        kResource: HelperTools.encodeRandomResource(),
                        kEnabled: true,
                        kDirectTLS: false
                    ] as [String : Any]

                    let accountNo = DataLayer.sharedInstance().addAccount(with: dic);
                    if(accountNo != nil) {
                        MLXMPPManager.sharedInstance().addNewAccount(toKeychain: accountNo!, withPassword: self.password)
                    }
                    self.registerComplete = true
                    showSuccessAlert()
                } else {
                    showRegistrationAlert(alertMessage: errorMsg)
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
        let newTimeout = DispatchTime.now() + 0.05;
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
                                showRegistrationAlert(alertMessage: NSLocalizedString("Could not read captcha!", comment: ""))
                            }
                        }
                    }
                }, andErrorCompletion: {_, errorMsg in
                    DispatchQueue.main.async {
                        showRegistrationAlert(alertMessage: errorMsg)
                    }
                })
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                VStack(alignment: .leading) {
                    Text("Like email, you can register your account on many sites and talk to anyone. You can use this page to register an account with a selected or provided XMPP server. You also have to choose a username and a password.")
                        .padding()
                }
                .background(Color(UIColor.systemBackground))

                Form {
                    Menu {
                        Picker("", selection: $selectedServerIndex) {
                            ForEach (RegisterAccount.XMPPServer.indices, id: \.self) {
                                if($0 == 0) {
                                    xmppServerInputSelectLabel.tag(0)
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
                                xmppServerInputSelectLabel.font(.system(size: 17)).frame(maxWidth: .infinity)
                            }
                        }
                        .padding(9.0)
                        .background(Color(UIColor.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    if(selectedServerIndex == 0) {
                        TextField("Provide XMPP-Server", text: Binding(get: { self.providedServer }, set: { string in self.providedServer = string.lowercased() }))
                            .disableAutocorrection(true)
                    }

                    TextField("Username", text: Binding(get: { self.username }, set: { string in self.username = string.lowercased() }))
                        .disableAutocorrection(true)
                    SecureField("Password", text: $password)
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
                        TextField("Captcha", text: $captchaText)
                    }

                    Button(action: {
                        showAlert = (!serverSelectedAlert && (!serverProvidedAlert || xmppServerFaultyAlert)) || (!credentialsEnteredAlert || credentialsFaultyAlert || credentialsExistAlert)

                        if(!showAlert) {
                            self.errorObserverEnabled = true
                            if(self.xmppAccount == nil) {
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
                            .foregroundColor(buttonColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .alert(isPresented: $showAlert) {
                        Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton: .default(alertPrompt.dismissLabel, action: {
                            if(self.registerComplete == true) {
                                if let completion = self.completionHandler {
                                    DDLogVerbose("Calling reg completion handler...")
                                    completion()
                                }
                                self.delegate.dismiss()
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
                            NavigationView {
                                WebView(url: URL(string: (RegisterAccount.XMPPServer[$selectedServerIndex.wrappedValue]["TermsSite_\(Locale.current.languageCode ?? "default")"] ?? RegisterAccount.XMPPServer[$selectedServerIndex.wrappedValue]["TermsSite_default"])!)!)
                                    .navigationBarTitle("Terms of \(RegisterAccount.XMPPServer[$selectedServerIndex.wrappedValue]["XMPPServer"]!)", displayMode: .inline)
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
                .frame(height: 370)
                .textFieldStyle(.roundedBorder)
            }
        }
        .addLoadingOverlay(overlay)
        .navigationTitle("Register")
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kXMPPError")).receive(on: RunLoop.main)) { notification in
            DDLogDebug("Got xmpp error")
            if(self.errorObserverEnabled == false) {
                return
            }
            if let xmppAccount = notification.object as? xmpp, let errorMessage = notification.userInfo?["message"] as? String {
                if(xmppAccount == self.xmppAccount) {
                    DispatchQueue.main.async {
                        DDLogDebug("XMPP account matches registering one")
                        errorObserverEnabled = false
                        showRegistrationAlert(alertMessage: errorMessage)
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
