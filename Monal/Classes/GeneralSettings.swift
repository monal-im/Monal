//
//  GeneralSettings.swift
//  Monal
//
//  Created by Vaidik Dubey on 22/03/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import ViewExtractor
struct SettingsToggle<T>: View where T: View {
    let value: Binding<Bool>
    let contents: T
    
    init(isOn value: Binding<Bool>, @ViewBuilder contents: @escaping () -> T) {
        self.value = value
        self.contents = contents()
    }
    
    var body:some View {
        VStack(alignment: .leading, spacing: 0) {
            Extract(contents) { views in
                if views.count == 0 {
                    Text("")
                } else {
                    Toggle(isOn: value) {
                        views[0]
                            .font(.body)
                    }
                    if views.count > 1 {
                        Group {
                            ForEach(views[1...]) { view in
                                view
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                                    .font(.footnote)
                            }
                        }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

func getNotificationPrivacyOption(_ option: NotificationPrivacySettingOption) -> String {
    switch option{
        case .DisplayNameAndMessage:
            return NSLocalizedString("Display Name And Message", comment: "")
         case .DisplayOnlyName:
            return NSLocalizedString("Display Only Name", comment: "")
         case .DisplayOnlyPlaceholder:
            return NSLocalizedString("Display Only Placeholder", comment: "")
    }
}

class GeneralSettingsDefaultsDB: ObservableObject {
    @defaultsDB("NotificationPrivacySetting")
    var notificationPrivacySetting: Int
    
    @defaultsDB("OMEMODefaultOn") 
    var omemoDefaultOn:Bool
    
    @defaultsDB("AutodeleteInterval")
    var AutodeleteInterval: Int
    
    @defaultsDB("SendLastUserInteraction")
    var sendLastUserInteraction: Bool
    
    @defaultsDB("SendLastChatState")
    var sendLastChatState: Bool
    
    @defaultsDB("SendReceivedMarkers")
    var sendReceivedMarkers: Bool
    
    @defaultsDB("SendDisplayedMarkers")
    var sendDisplayedMarkers: Bool
    
    @defaultsDB("ShowGeoLocation")
    var showGeoLocation: Bool
    
    @defaultsDB("ShowURLPreview")
    var showURLPreview: Bool
    
    @defaultsDB("useInlineSafari")
    var useInlineSafari: Bool
    
    @defaultsDB("webrtcAllowP2P")
    var webrtcAllowP2P: Bool
    
    @defaultsDB("webrtcUseFallbackTurn")
    var webrtcUseFallbackTurn: Bool
    
    @defaultsDB("allowVersionIQ")
    var allowVersionIQ: Bool
    
    @defaultsDB("allowNonRosterContacts")
    var allowNonRosterContacts: Bool
    
    @defaultsDB("allowCallsFromNonRosterContacts")
    var allowCallsFromNonRosterContacts: Bool
    
    @defaultsDB("AutodownloadFiletransfers")
    var autodownloadFiletransfers : Bool
    
    @defaultsDB("AutodownloadFiletransfersWifiMaxSize")
    var autodownloadFiletransfersWifiMaxSize : UInt
    
    @defaultsDB("AutodownloadFiletransfersMobileMaxSize")
    var autodownloadFiletransfersMobileMaxSize : UInt
    
    @defaultsDB("ImageUploadQuality")
    var imageUploadQuality : Float
    
    @defaultsDB("showKeyboardOnChatOpen")
    var showKeyboardOnChatOpen: Bool
    
    @defaultsDB("useDnssecForAllConnections")
    var useDnssecForAllConnections: Bool
    
    @defaultsDB("uploadImagesOriginal")
    var uploadImagesOriginal: Bool
}


struct GeneralSettings: View {
    @ObservedObject var generalSettingsDefaultsDB = GeneralSettingsDefaultsDB()
    
    var body: some View {
        Form {
            Section(header:Text("General Settings")) {
                NavigationLink(destination: LazyClosureView(UserInterfaceSettings())) {
                    HStack{
                        Image(systemName: "hand.tap.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                        Text("User Interface")
                    }
                }
                NavigationLink(destination: LazyClosureView(SecuritySettings())) {
                    HStack{
                        Image(systemName: "shield.checkerboard")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                        Text("Security")
                    }
                }
                NavigationLink(destination: LazyClosureView(PrivacySettings())) {
                    HStack{
                        Image(systemName: "eye")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                        Text("Privacy")
                    }
                }
                NavigationLink(destination: LazyClosureView(NotificationSettings())) {
                    HStack{
                        Image(systemName: "text.bubble")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                        Text("Notifications")
                    }
                }
                NavigationLink(destination: LazyClosureView(AttachmentSettings())) {
                    HStack {
                        Image(systemName: "paperclip")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                        Text("Attachments")
                    }
                }
                
                Button(action: {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                }, label: {
                    HStack {
                        Image(systemName: "gear")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                        #if targetEnvironment(macCatalyst)
                            Text("Open macOS settings")
                        #else
                            Text("Open iOS settings")
                        #endif
                    }.foregroundColor(Color(UIColor.label))
                })
                .buttonStyle(.borderless) 
            }
        }
        .navigationBarTitle(Text("General Settings"))
    }
}

struct UserInterfaceSettings: View {
    @ObservedObject var generalSettingsDefaultsDB = GeneralSettingsDefaultsDB()
    
    var body: some View {
        Form {
            Section(header: Text("Previews")) {
                SettingsToggle(isOn: $generalSettingsDefaultsDB.showGeoLocation) {
                    Text("Show inline geo location")
                    Text("Received geo locations are shared with Apple's Maps App.")
                }
                SettingsToggle(isOn: $generalSettingsDefaultsDB.showURLPreview) {
                    Text("Show URL previews")
                    Text("The operator of the webserver providing that URL may see your IP address.")
                }
                SettingsToggle(isOn: $generalSettingsDefaultsDB.useInlineSafari) {
                    Text("Open URLs inline in Safari")
                    Text("When disabled, URLs will opened in your default browser (that might not be Safari).")
                }
            }
            
            Section(header: Text("Input")) {
                SettingsToggle(isOn: $generalSettingsDefaultsDB.showKeyboardOnChatOpen) {
                    Text("Autofocus text input on chat open")
                    Text("Will focus the textfield on macOS or iOS with hardware keyboard attached, will open the software keyboard otherwise.")
                }
            }
            
            Section(header: Text("Appearance")) {
                VStack(alignment: .leading, spacing: 0) {
                    NavigationLink(destination: LazyClosureView(BackgroundSettings(contact:nil))) {
                        Text("Chat background image").font(.body)
                    }
                    Text("Configure the background image displayed in open chats.")
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationBarTitle(Text("User Interface"), displayMode: .inline)
    }
}

struct SecuritySettings: View {
    @ObservedObject var generalSettingsDefaultsDB = GeneralSettingsDefaultsDB()
    @State var autodeleteInterval: Int = 0
    @State var autodeleteIntervalSelection: Int = 0
    var autodeleteOptions = [
              0: NSLocalizedString("Off", comment:"Message autdelete time"),
             30: NSLocalizedString("30 seconds", comment:"Message autdelete time"),
             60: NSLocalizedString("1 minute", comment:"Message autdelete time"),
            300: NSLocalizedString("5 minutes", comment:"Message autdelete time"),
            900: NSLocalizedString("15 minutes", comment:"Message autdelete time"),
           1800: NSLocalizedString("30 minutes", comment:"Message autdelete time"),
           3600: NSLocalizedString("1 hour", comment:"Message autdelete time"),
          43200: NSLocalizedString("12 hours", comment:"Message autdelete time"),
          86400: NSLocalizedString("1 day", comment:"Message autdelete time"),
         259200: NSLocalizedString("3 days", comment:"Message autdelete time"),
         604800: NSLocalizedString("1 week", comment:"Message autdelete time"),
        2419200: NSLocalizedString("4 weeks", comment:"Message autdelete time"),
        5184000: NSLocalizedString("2 month", comment:"Message autdelete time"),        //based on 30 days per month
        7776000: NSLocalizedString("3 month", comment:"Message autdelete time"),        //based on 30 days per month
    ]
    
    init() {
        _autodeleteInterval = State(wrappedValue:generalSettingsDefaultsDB.AutodeleteInterval)
        _autodeleteIntervalSelection = State(wrappedValue:generalSettingsDefaultsDB.AutodeleteInterval)
        if #available(iOS 15, *) {
            //only activate custom values on ios >= 15
            autodeleteOptions[-1] = NSLocalizedString("Custom", comment:"Message autdelete time")
            //check if we have a custom value and change picker value accordingly
            if autodeleteOptions[autodeleteInterval] == nil {
                _autodeleteIntervalSelection = State(wrappedValue:-1)
            }
        } else {
            //check if we have a custom value, this should never happen because custom values should only be settable in ios >= 15
            if autodeleteOptions[autodeleteInterval] == nil {
                //turn autodelete off int his case (sane value)
                _autodeleteIntervalSelection = State(wrappedValue:0)
                _autodeleteInterval = State(wrappedValue:0)
            }
        }
    }
    
    var body: some View {
        Form {
            Section(header: Text("Encryption")) {
                SettingsToggle(isOn: $generalSettingsDefaultsDB.omemoDefaultOn) {
                    Text("Enable encryption by default for new chats")
                    Text("Every new contact will have encryption enabled, but already known contacts will preserve their encryption settings.")
                }
                
                if #available(iOS 16.0, macCatalyst 16.0, *) {
                    SettingsToggle(isOn: $generalSettingsDefaultsDB.useDnssecForAllConnections) {
                        Text("Use DNSSEC validation for all connections")
                        Text(
"""
Use DNSSEC to validate all DNS query responses before connecting to the IP address designated \
in the DNS response.\n\
While being more secure, this can lead to connection problems in certain networks \
like hotel wifi, ugly mobile carriers etc.
"""
                        )
                    }
                }
                
                SettingsToggle(isOn: $generalSettingsDefaultsDB.webrtcAllowP2P) {
                    Text("Calls: Allow P2P sessions")
                    Text("Allow your device to establish a direct network connection to the remote party. This might leak your IP address to the caller/callee.")
                }
            }
            
            Section(header: Text("On this device")) {
                VStack(alignment: .leading, spacing: 0) {
                    Picker("Autodelete all messages older than", selection: $autodeleteIntervalSelection) {
                        ForEach(autodeleteOptions.keys.sorted(), id: \.self) { key in
                            Text(autodeleteOptions[key]!).tag(key)
                        }
                    }
                    if #available(iOS 15, *) {
                        //custom interval requested explicitly
                        if autodeleteIntervalSelection == -1 {
                            HStack {
                                Text("Custom Time: ")
                                Stepper(String(format:NSLocalizedString("%@ hours", comment:""), String(describing:(max(1, autodeleteInterval / 3600)).formatted())), value: Binding<Int>(
                                    get: { max(1, autodeleteInterval / 3600) /*clamp to 1 ... .max*/ },
                                    set: { autodeleteInterval = $0 * 3600 }
                                ), in: 1 ... .max)
                            }
                        }
                    }
                    Text("Be warned: Message will only be deleted on incoming pushes or if you open the app! This is especially true for shorter time intervals!").foregroundColor(Color(UIColor.secondaryLabel)).font(.footnote)
                    Text("Also beware: You won't be able to load older history from your server, Monal will immediately delete it after fetching it!").foregroundColor(Color(UIColor.secondaryLabel)).font(.footnote)
                }
            }
        }
        .navigationBarTitle(Text("Security"), displayMode: .inline)
        //save only when closing view to not delete messages while the user is selecting a (custom) value
        .onDisappear {
            if autodeleteIntervalSelection == -1 {
                //make sure our custom value is stored clamped, too
                autodeleteInterval = max(1, autodeleteInterval / 3600)
            } else {
                //copy over picker value if not set to custom
                autodeleteInterval = autodeleteIntervalSelection
            }
            generalSettingsDefaultsDB.AutodeleteInterval = autodeleteInterval
        }
    }
}

struct PrivacySettings: View {
    @ObservedObject var generalSettingsDefaultsDB = GeneralSettingsDefaultsDB()
    
    var body: some View {
        Form {
            PrivacySettingsSubview(onboardingPart:-1)
        }
        .navigationBarTitle(Text("Privacy"), displayMode: .inline)
    }
}
struct PrivacySettingsSubview: View {
    @ObservedObject var generalSettingsDefaultsDB = GeneralSettingsDefaultsDB()
    var onboardingPart: Int
    
    var body: some View {
        if onboardingPart == -1 || onboardingPart == 0 {
            Section(header: Text("Activity indications")) {
                SettingsToggle(isOn: $generalSettingsDefaultsDB.sendReceivedMarkers) {
                    Text("Send message receipts")
                    Text("Let your contacts know if you received a message.")
                }
                SettingsToggle(isOn: $generalSettingsDefaultsDB.sendDisplayedMarkers) {
                    Text("Send read receipts")
                    Text("Let your contacts know if you read a message.")
                }
                SettingsToggle(isOn: $generalSettingsDefaultsDB.sendLastChatState) {
                    Text("Send typing notifications")
                    Text("Let your contacts know if you are typing a message.")
                }
                SettingsToggle(isOn: $generalSettingsDefaultsDB.sendLastUserInteraction) {
                    Text("Send last interaction time")
                    Text("Let your contacts know when you last opened the app.")
                }
            }
        }
        if onboardingPart == -1 || onboardingPart == 1 {
            Section(header: Text("Interactions")) {
                SettingsToggle(isOn: $generalSettingsDefaultsDB.allowNonRosterContacts) {
                    Text("Accept incoming messages from strangers")
                    Text("Allow contacts not in your contact list to contact you.")
                }
                SettingsToggle(isOn: Binding<Bool>(
                    get: { generalSettingsDefaultsDB.allowCallsFromNonRosterContacts && generalSettingsDefaultsDB.allowNonRosterContacts },
                    set: { generalSettingsDefaultsDB.allowCallsFromNonRosterContacts = $0 }
                )) {
                    Text("Accept incoming calls from strangers")
                    Text("Allow contacts not in your contact list to call you.")
                }.disabled(!generalSettingsDefaultsDB.allowNonRosterContacts)
            }
        }
        if onboardingPart == -1 || onboardingPart == 2 {
            Section(header: Text("Misc")) {
                SettingsToggle(isOn: $generalSettingsDefaultsDB.allowVersionIQ) {
                    Text("Publish version")
                    Text("Allow contacts in your contact list to query your Monal and iOS versions.")
                }
                SettingsToggle(isOn: $generalSettingsDefaultsDB.webrtcUseFallbackTurn) {
                    Text("Calls: Allow TURN fallback to Monal-Servers")
                    Text("This will make calls possible even if your XMPP server does not provide a TURN server.")
                }
            }
        }
    }
}

struct NotificationSettings: View {
    @ObservedObject var generalSettingsDefaultsDB = GeneralSettingsDefaultsDB()
    @State private var pushPermissionEnabled = false
    
    private var pushNotEnabled: Bool {
        let xmppAccountInfo = MLXMPPManager.sharedInstance().connectedXMPP as! [xmpp]
        var pushNotEnabled = false
        for account in xmppAccountInfo {
            pushNotEnabled = pushNotEnabled || !account.connectionProperties.pushEnabled
        }
        return pushNotEnabled
    }
    
    var body: some View {
        Form {
            Section(header: Text("Settings")) {
                Picker(selection: $generalSettingsDefaultsDB.notificationPrivacySetting, label: Text("Privacy")) {
                    ForEach(NotificationPrivacySettingOption.allCases, id: \.self) { option in
                        Text(getNotificationPrivacyOption(option)).tag(option.rawValue)
                    }
                }
                .frame(height: 56, alignment: .trailing)
            }
            
            Section(header: Text("Debugging")) {
                NavigationLink(destination: LazyClosureView(NotificationDebugging())) {
                    buildNotificationStateLabel(Text("Debug Notification Problems"), isWorking: !self.pushNotEnabled && self.pushPermissionEnabled)
                }
            }
        }
        .onAppear {
            UNUserNotificationCenter.current().getNotificationSettings { (settings) -> Void in
                self.pushPermissionEnabled = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional);
            }
        }
        .navigationBarTitle(Text("Notifications"), displayMode: .inline)
    }
}

struct AttachmentSettings: View {
    @ObservedObject var generalSettingsDefaultsDB = GeneralSettingsDefaultsDB()
    
    var body: some View {
        Form {
            Section(header: Text("General File Transfer Settings")) {
                SettingsToggle(isOn: $generalSettingsDefaultsDB.autodownloadFiletransfers) {
                    Text("Auto-Download Media")
                }
            }
            
            Section(header: Text("Download Settings")) {
                Text("Adjust the maximum file size for auto-downloads over WiFi")
                    .foregroundColor(.secondary)
                    .font(.footnote)
                Slider(
                    value: $generalSettingsDefaultsDB.autodownloadFiletransfersWifiMaxSize.bytecount(mappedTo: 1024*1024),
                    in: 1.0...100.0,
                    step: 1.0,
                    minimumValueLabel: Text("1 MiB"),
                    maximumValueLabel: Text("100 MiB"),
                    label: {
                        Text("Load over wifi")
                    }
                )
                Text("Load over WiFi up to: \(String(describing:UInt(generalSettingsDefaultsDB.autodownloadFiletransfersWifiMaxSize/(1024*1024)))) MiB")
            }
            
            Section {
                Text("Adjust the maximum file size for auto-downloads over cellular network")
                    .foregroundColor(.secondary)
                    .font(.footnote)
                Slider(
                    value: $generalSettingsDefaultsDB.autodownloadFiletransfersMobileMaxSize.bytecount(mappedTo: 1024*1024),
                    in: 0.0...100.0,
                    step: 1.0,
                    minimumValueLabel: Text("1 MiB"),
                    maximumValueLabel: Text("100 MiB"),
                    label: {
                        Text("Load over Cellular")
                    }
                )
                Text("Load over cellular up to: \(String(describing:UInt(generalSettingsDefaultsDB.autodownloadFiletransfersMobileMaxSize/(1024*1024)))) MiB")
            }
            
            Section(header: Text("Upload Settings")) {
                SettingsToggle(isOn: $generalSettingsDefaultsDB.uploadImagesOriginal) {
                    Text("Upload Original Images")
                }
                if !generalSettingsDefaultsDB.uploadImagesOriginal {
                    Text("Adjust the quality of images uploaded")
                        .foregroundColor(.secondary)
                        .font(.footnote)
                    Slider(
                        value: $generalSettingsDefaultsDB.imageUploadQuality,
                        in: 0.33...1.0,
                        step: 0.01,
                        minimumValueLabel: Text("33%"),
                        maximumValueLabel: Text("100%"),
                        label: {
                            Text("Upload Settings")
                        }
                    )
                    Text("Image Upload JPEG-Quality: \(String(format: "%.0f%%", generalSettingsDefaultsDB.imageUploadQuality*100))")
                }
            }
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralSettings()
    }
}
