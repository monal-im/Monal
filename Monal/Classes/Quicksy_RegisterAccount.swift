//
//  Quicksy_RegisterAccount.swift
//  Monal
//
//  Created by Thilo Molitor on 13.07.24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

let QUICKSY_BASE_URL = "https://api.quicksy.im";

func sendSMSRequest(to number:String) -> Promise<(data: Data, response: URLResponse)> {
    var rq = URLRequest(url: URL(string: "\(QUICKSY_BASE_URL)/authentication/\(number)")!)
    rq.httpMethod = "GET"
    rq.addValue(Locale.current.language.languageCode?.identifier ?? "en", forHTTPHeaderField: "Accept-Language")
    rq.addValue(UIDevice.current.identifierForVendor?.uuidString.lowercased() ?? UUID().uuidString.lowercased(), forHTTPHeaderField: "Installation-Id")
    rq.addValue("Quicksy/2.10.0", forHTTPHeaderField: "User-Agent")
    DDLogDebug("Request: \(String(describing:rq))")
    if let headers = rq.allHTTPHeaderFields {
        for (key, value) in headers {
            DDLogDebug("Header: \(key): \(value)")
        }
    }
    return firstly {
        URLSession.shared.dataTask(.promise, with: rq).validate()
    }
}

func sendRegisterRequest(number:String, pin:String, password:String) -> Promise<(data: Data, response: URLResponse)> {
    var rq = URLRequest(url: URL(string: "\(QUICKSY_BASE_URL)/password")!)
    rq.httpMethod = "POST"
    rq.addValue(HelperTools.encodeBase64(with:"\(number)\0\(pin)"), forHTTPHeaderField: "Authorization")
    rq.addValue("Quicksy/2.10.0", forHTTPHeaderField: "User-Agent")
    rq.httpBody = password.data(using:.utf8)
    DDLogDebug("Request: \(String(describing:rq))")
    if let headers = rq.allHTTPHeaderFields {
        for (key, value) in headers {
            DDLogDebug("Header: \(key): \(value)")
        }
    }
    return firstly {
        URLSession.shared.dataTask(.promise, with: rq).validate()
    }
}

class Quicksy_State: ObservableObject {
    @defaultsDB("Quicksy_phoneNumber")
    var phoneNumber: String?
    
    @defaultsDB("Quicksy_countryCode")
    var countryCode: String?
}

struct Quicksy_RegisterAccount: View {
    var delegate: SheetDismisserProtocol
    let countries: [Quicksy_Country] = COUNTRY_CODES
    @StateObject private var overlay = LoadingOverlayState()
    @ObservedObject var state = Quicksy_State()
    @State private var currentIndex = 0
    @State var selectedCountry: Quicksy_Country?
    @State var phoneNumber: String = ""
    //ios>=15
    //@FocusState var phoneNumberFocused: Bool = false
    @State var showPhoneNumberCheckAlert: String?
    @State var pin: String = ""
    //ios>=15
    //@FocusState var pinFocused: Bool = false
    @State var showErrorAlert: PMKHTTPError?
    @State var showBackAlert: Bool?
    
    //login state
    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))
    @State private var showAlert = false
    @State var currentTimeout : DispatchTime? = nil
    @State var errorObserverEnabled = false
    @State var newAccountNo: NSNumber? = nil
    @State var loginComplete = false
    @State var isLoadingOmemoBundles = false
    
    init(delegate: SheetDismisserProtocol) {
        self.delegate = delegate
        self.state.phoneNumber = nil
    }
    
    private func requestSMS(for number:String) {
        showPhoneNumberCheckAlert = nil
        showPromisingLoadingOverlay(overlay, headline:NSLocalizedString("Requesting validation SMS...", comment: ""), description: "") {
            sendSMSRequest(to:number)
        }.done { data, response in
            DDLogDebug("Got sendSMSRequest success: \(String(describing:response))\n\(String(describing:data))")
            state.phoneNumber = number
        }.catch { error in
            DDLogError("Catched sendSMSRequest error: \(String(describing:error))")
            if let response = error as? PMKHTTPError {
                showErrorAlert = response
            }
        }
    }
    
    private func createAccount() {
        state.countryCode = selectedCountry!.code       //used to add a country code to phonebook entries not having any
        let password = HelperTools.generateRandomPassword()
        if let number = state.phoneNumber {
            showPromisingLoadingOverlay(overlay, headline:NSLocalizedString("Registering account...", comment: ""), description: "") {
                sendRegisterRequest(number:number, pin:pin, password:password)
            }.done { result in
                DDLogDebug("Got sendRegisterRequest success: \(String(describing:result))")
                startLoginTimeout()
                showLoadingOverlay(overlay, headline:NSLocalizedString("Logging in", comment: ""))
                self.errorObserverEnabled = true
                self.newAccountNo = MLXMPPManager.sharedInstance().login("\(number)@quicksy.im", password: password)
                if(self.newAccountNo == nil) {
                    currentTimeout = nil // <- disable timeout on error
                    errorObserverEnabled = false
                    showLoginErrorAlert(errorMessage:NSLocalizedString("Account already configured!", comment: ""))
                    self.newAccountNo = nil
                }
            }.catch { error in
                DDLogError("Catched sendRegisterRequest error: \(String(describing:error))")
                if let response = error as? PMKHTTPError {
                    showErrorAlert = response
                }
            }
        }
    }
    
    private var isValidNumber: Bool {
        guard let selectedCountry = selectedCountry else {
            return false
        }
        let phonePredicate = NSPredicate(format: "SELF MATCHES %@", selectedCountry.pattern)
        return phoneNumber.allSatisfy { $0.isNumber } && phoneNumber.count > 0 && phonePredicate.evaluate(with: phoneNumber)
    }
    
    private func showTimeoutAlert() {
        DDLogVerbose("Showing timeout alert...")
        hideLoadingOverlay(overlay)
        alertPrompt.title = Text("Timeout Error")
        alertPrompt.message = Text("We were not able to connect your account. Please check your username and password and make sure you are connected to the internet.")
        showAlert = true
    }

    private func showSuccessAlert() {
        hideLoadingOverlay(overlay)
        alertPrompt.title = Text("Success!")
        alertPrompt.message = Text("Quicksy is now set up and connected.")
        showAlert = true
    }

    private func showLoginErrorAlert(errorMessage: String) {
        hideLoadingOverlay(overlay)
        alertPrompt.title = Text("Error")
        alertPrompt.message = Text(String(format: NSLocalizedString("We were not able to connect your account. Please check your username and password and make sure you are connected to the internet.\n\nTechnical error message: %@", comment: ""), errorMessage))
        showAlert = true
    }
    
    private func startLoginTimeout() {
        let newTimeout = DispatchTime.now() + 30.0;
        self.currentTimeout = newTimeout
        DispatchQueue.main.asyncAfter(deadline: newTimeout) {
            if(newTimeout == self.currentTimeout) {
                DDLogWarn("First login timeout triggered...")
                if(self.newAccountNo != nil) {
                    DDLogVerbose("Removing account...")
                    MLXMPPManager.sharedInstance().removeAccount(forAccountNo: self.newAccountNo!)
                    self.newAccountNo = nil
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
            
            if state.phoneNumber == nil {
                VStack(alignment: .leading) {
                    Text("Verify your phone number")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .padding(.bottom, 8)
                    
                    Text("Quicksy will send an SMS message (carrier charges may apply) to verify your phone number. Enter your country code and phone number:")
                    
                    HStack {
                        Text("Country:")
                        Picker(selection: $selectedCountry, label: EmptyView()) {
                            ForEach(countries) { country in
                                Text("\(country.name) (\(country.code))").tag(country as Quicksy_Country?)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }

                    HStack {
                        if let selectedCountry = selectedCountry {
                            Text(selectedCountry.code)
                        }
                        TextField("Phone Number", text: $phoneNumber)
                            //ios>=15
                            //.focused($phoneNumberFocused)
                            .keyboardType(.numberPad)
                            .onChange(of: phoneNumber) { newValue in
                                let filtered = newValue.filter { "0123456789".contains($0) }
                                if filtered != newValue {
                                    phoneNumber = filtered
                                }
                            }
                    }
                    .padding()
                    .border(phoneNumber.count==0 ? Color.gray : (isValidNumber ? Color.green : Color.red), width: phoneNumber.count==0 ? 1 : 2)

                    Spacer()
                    
                    if let selectedCountry = selectedCountry {
                        HStack {
                            Spacer()
                            
                            Button(action: {
                                showPhoneNumberCheckAlert = selectedCountry.code + phoneNumber
                            }) {
                                Text("Next")
                                    .fontWeight(.bold)
                                    .padding(10)
                                    .background(!isValidNumber ? Color(UIColor.lightGray) : Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .disabled(!isValidNumber)
                        }
                    }
                }
                .richAlert(isPresented:$showPhoneNumberCheckAlert, title:Text("Check this number?"), body:{ number in
                    VStack(alignment: .leading) {
                        Text("We will check the number **\(number)**. Is this okay or do you want to change the number?")
                    }
                }, buttons: { number in 
                    HStack {
                        Button(action: {
                            showPhoneNumberCheckAlert = nil
                        }) {
                            Text("Change it")
                                .fontWeight(.bold)
                                .padding(10)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            requestSMS(for:number)
                        }) {
                            Text("OK")
                                .fontWeight(.bold)
                                .padding(10)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                })
                .onAppear {
                    selectedCountry = countries[0]
                    print("######## \(String(describing:Locale.current.regionCode))")
                    print("######## \(String(describing:Locale(identifier: "en_US").localizedString(forRegionCode:Locale.current.regionCode ?? "en")))")
                    for country in countries {
                        if country.name == Locale.current.localizedString(forRegionCode:Locale.current.regionCode ?? "en") || country.name == Locale(identifier: "en_US").localizedString(forRegionCode:Locale.current.regionCode ?? "en") {
                            selectedCountry = country
                        }
                    }
                    //ios>=15
                    //phoneNumberFocused = true
                }
            } else if let number = state.phoneNumber {
                VStack(alignment: .leading) {
                    Text("Verify your phone number")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .padding(.bottom, 8)
                        
                    Text("We sent you an SMS to \(number)")
                    Text("Please enter the six-digit pin below")
                    HStack {
                        TextField("Pin", text: $pin)
                            //ios>=15
                            //.focused($phoneNumberFocused)
                            .keyboardType(.numberPad)
                            .onChange(of: pin) { newValue in
                                let filtered = newValue.filter { "0123456789".contains($0) }
                                if filtered != newValue {
                                    pin = filtered
                                }
                            }
                    }
                    .padding()
                    .border(pin.count==0 ? Color.gray : (pin.count==6 ? Color.green : Color.red), width: pin.count==0 ? 1 : 2)
                    
                    Spacer().frame(height:16)
                    
                    Button(action: {
                        requestSMS(for:number)
                    }) {
                        Text("Send SMS again")
                    }
                    .frame(maxWidth: .infinity, alignment: .center).padding()
                    
                    Spacer()
                    
                    HStack {
                        Button(action: {
                            showBackAlert = true
                        }) {
                            Text("Previous")
                                .fontWeight(.bold)
                                .padding(10)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                            
                        Spacer()
                            
                        Button(action: {
                            createAccount()
                        }) {
                            Text("Next")
                                .fontWeight(.bold)
                                .padding(10)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
                .richAlert(isPresented:$showBackAlert, title:Text("Cancel?")) { error in
                    VStack(alignment: .leading) {
                        Text("Are you sure to cancel the registration process?")
                    }
                } buttons: { error in 
                    HStack {
                        Button(action: {
                            showBackAlert = nil
                        }) {
                            Text("No")
                                .fontWeight(.bold)
                                .padding(10)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            showBackAlert = nil
                            state.phoneNumber = nil
                        }) {
                            Text("Yes")
                                .fontWeight(.bold)
                                .padding(10)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
                .onAppear {
                    //ios>=15
                    //pinFocused = true
                }
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton: .default(alertPrompt.dismissLabel, action: {
                if(self.loginComplete == true) {
                    self.delegate.dismissWithoutAnimation()
                }
            }))
        }
        .richAlert(isPresented:$showErrorAlert, title:Text("Error requesting SMS!"), body:{ error in
            VStack(alignment: .leading) {
                Text("An error happened when trying to request the SMS:")
                    .bold()
                Spacer().frame(height:16)
                switch error {
                    case .badStatusCode(let code, _, let response):
                        switch code {
                            case 400:
                                Text("Invalid user input.")
                            case 401:
                                Text("The pin you have entered is incorrect.")
                            case 403:
                                Text("You are using an out of date version of this app.")
                            case 404:
                                Text("The pin we have sent you has expired.")
                            case 409:
                                Text("This phone number is currently logged in with another device.")
                            case 429:
                                Text("Too many attempts, please try again in \(HelperTools.string(fromTimeInterval:UInt(response.value(forHTTPHeaderField:"Retry-After") ?? "0") ?? 0)).")
                            case 500:
                                Text("Something went wrong processing your request.")
                            case 501:
                                Text("Temporarily unavailable. Try again later.")
                            case 502:
                                Text("Temporarily unavailable. Try again later.")
                            case 503:
                                Text("Temporarily unavailable. Try again later.")
                            default:
                                Text("Unexpected error processing your request.")
                        }
                }
            }
        }, buttons: { error in 
            HStack {
                Spacer()
                
                Button(action: {
                    showErrorAlert = nil
                }) {
                    Text("OK")
                        .fontWeight(.bold)
                        .padding(10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        })
        .padding()
        .addLoadingOverlay(overlay)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kXMPPError")).receive(on: RunLoop.main)) { notification in
            if(self.errorObserverEnabled == false) {
                return
            }
            if let xmppAccount = notification.object as? xmpp, let newAccountNo : NSNumber = self.newAccountNo, let errorMessage = notification.userInfo?["message"] as? String {
                if(xmppAccount.accountNo.intValue == newAccountNo.intValue) {
                    DispatchQueue.main.async {
                        currentTimeout = nil // <- disable timeout on error
                        errorObserverEnabled = false
                        showLoginErrorAlert(errorMessage: errorMessage)
                        MLXMPPManager.sharedInstance().removeAccount(forAccountNo: newAccountNo)
                        self.newAccountNo = nil
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMLResourceBoundNotice")).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let newAccountNo : NSNumber = self.newAccountNo {
                if(xmppAccount.accountNo.intValue == newAccountNo.intValue) {
                    DispatchQueue.main.async {
                        currentTimeout = nil // <- disable timeout on successful connection
                        self.errorObserverEnabled = false
                        showLoadingOverlay(overlay, headline:NSLocalizedString("Loading contact list", comment: ""))
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalUpdateBundleFetchStatus")).receive(on: RunLoop.main)) { notification in
            if let notificationAccountNo = notification.userInfo?["accountNo"] as? NSNumber, let completed = notification.userInfo?["completed"] as? NSNumber, let all = notification.userInfo?["all"] as? NSNumber, let newAccountNo : NSNumber = self.newAccountNo {
                if(notificationAccountNo.intValue == newAccountNo.intValue) {
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
            if let notificationAccountNo = notification.userInfo?["accountNo"] as? NSNumber, let newAccountNo : NSNumber = self.newAccountNo {
                if(notificationAccountNo.intValue == newAccountNo.intValue && isLoadingOmemoBundles) {
                    DispatchQueue.main.async {
                        self.loginComplete = true
                        showSuccessAlert()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalFinishedCatchup")).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let newAccountNo : NSNumber = self.newAccountNo {
                if(xmppAccount.accountNo.intValue == newAccountNo.intValue && !isLoadingOmemoBundles) {
                    DispatchQueue.main.async {
                        self.loginComplete = true
                        showSuccessAlert()
                    }
                }
            }
        }
    }
}
