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
    
    @defaultsDB("HasSeenPrivacySettings")
    var hasSeenPrivacySettings: Bool
    
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
        .onAppear {
            generalSettingsDefaultsDB.hasSeenPrivacySettings = true
        }
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
    let autodeleteOptions = [
        0:"Off", 30:"30 seconds", 300:"5 minutes", 3600:"1 hour",
        28800:"8 hours", 86400:"1 day", 604800:"1 week", 2419200:"4 weeks", -1:"Custom"
    ]
    
    @State private var showingCustomTimeSheet = false
    @State private var selectedOptionIndex: Int = 0
    @State private var customTimeString = ""
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
                Picker("Autodelete all messages after", selection: $generalSettingsDefaultsDB.AutodeleteInterval) {
                    ForEach(autodeleteOptions.keys.sorted(), id: \.self) { key in
                        Text(autodeleteOptions[key, default: "Custom"]).tag(key)
                    }
                }
            }
        }
        .navigationBarTitle(Text("Security"), displayMode: .inline)
        .onChange(of: generalSettingsDefaultsDB.AutodeleteInterval) { newValue in
            if newValue == -1  {
                showingCustomTimeSheet = true
            }
        }
        .sheet(isPresented: $showingCustomTimeSheet) {
            NavigationView {
                Form {
                    TextField("Enter time in minutes", text: $customTimeString)
                        .keyboardType(.numberPad)
                    Button("Set") {
                        if let minutes = Int(customTimeString), minutes>0 {
                            generalSettingsDefaultsDB.AutodeleteInterval = minutes * 60
                        }
                        showingCustomTimeSheet = false
                    }
                }
                .navigationBarTitle("Enter Custom Time", displayMode: .inline)
                .navigationBarItems(trailing: Button("Cancel") {
                    showingCustomTimeSheet = false
                })
            }
        }

    }
}

struct PrivacySettings: View {
    @ObservedObject var generalSettingsDefaultsDB = GeneralSettingsDefaultsDB()
    
    var body: some View {
        Form {
            Section(header: Text("Activity indications")) {
                SettingsToggle(isOn: $generalSettingsDefaultsDB.sendReceivedMarkers) {
                    Text("Send message received")
                    Text("Let your contacts know if you received a message.")
                }
                SettingsToggle(isOn: $generalSettingsDefaultsDB.sendDisplayedMarkers) {
                    Text("Send message displayed state")
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
            
            Section(header: Text("Interactions")) {
                SettingsToggle(isOn: $generalSettingsDefaultsDB.allowNonRosterContacts) {
                    Text("Accept incoming messages from strangers")
                    Text("Allow contacts not in your contact list to contact you.")
                }
                SettingsToggle(isOn: $generalSettingsDefaultsDB.allowCallsFromNonRosterContacts) {
                    Text("Accept incoming calls from strangers")
                    Text("Allow contacts not in your contact list to call you.")
                }.disabled(!generalSettingsDefaultsDB.allowNonRosterContacts)
            }
            
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
        .navigationBarTitle(Text("Privacy"), displayMode: .inline)
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
                Text("Load over WiFi up to: \(UInt(generalSettingsDefaultsDB.autodownloadFiletransfersWifiMaxSize/(1024*1024))) MiB")
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
                Text("Load over cellular up to: \(Int(generalSettingsDefaultsDB.autodownloadFiletransfersMobileMaxSize/(1024*1024))) MiB")
            }
            
            Section(header: Text("Upload Settings")) {
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
                Text("Image Upload Quality: \(String(format: "%.0f%%", generalSettingsDefaultsDB.imageUploadQuality*100))")
            }
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        PrivacySettings()
    }
}
