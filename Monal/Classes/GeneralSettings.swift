//
//  GeneralSettings.swift
//  Monal
//
//  Created by Vaidik Dubey on 22/03/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//


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
    
    @defaultsDB("AutodeleteAllMessagesAfter3Days")
    var autodeleteAllMessagesAfter3Days: Bool
    
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
                    HStack{
                        Image(systemName: "paperclip")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                        Text("Attachments")
                    }
                }
            }
        }
        .navigationBarTitle("General Settings")
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
                Toggle(isOn: $generalSettingsDefaultsDB.showGeoLocation) {
                    Text("Show inline geo location").font(.body)
                    Text("Received geo locations are shared with Apple's Maps App.").font(.footnote)
                }
                Toggle(isOn: $generalSettingsDefaultsDB.showURLPreview) {
                    Text("Show URL previews").font(.body)
                    Text("The operator of the webserver providing that URL may see your IP address.").font(.footnote)
                }
            }
            
            Section(header: Text("Input")) {
                Toggle(isOn: $generalSettingsDefaultsDB.showKeyboardOnChatOpen) {
                    Text("Autofocus text input on chat open").font(.body)
                    Text("Will focus the textfield on macOS or iOS with hardware keyboard attached, will open the software keyboard otherwise.").font(.footnote)
                }
            }
            
            Section(header: Text("Appearance")) {
                NavigationLink(destination: LazyClosureView(BackgroundSettings(contact:nil))) {
                    Text("Chat background image").font(.body)
                    Text("Configure the background image displayed in open chats.").font(.footnote)
                }
            }
        }
        .navigationBarTitle("User Interface", displayMode: .inline)
    }
}

struct SecuritySettings: View {
    @ObservedObject var generalSettingsDefaultsDB = GeneralSettingsDefaultsDB()
    
    var body: some View {
        Form {
            Section(header: Text("Encryption")) {
                Toggle(isOn: $generalSettingsDefaultsDB.omemoDefaultOn) {
                    Text("Enable encryption by default for new chats").font(.body)
                    Text("Every new contact will have encryption enabled, but already known contacts will preserve their encryption settings.").font(.footnote)
                }
                
                if #available(iOS 16.0, macCatalyst 16.0, *) {
                    Toggle(isOn: $generalSettingsDefaultsDB.useDnssecForAllConnections) {
                        Text("Use DNSSEC validation for all connections").font(.body)
                        Text(
"""
Use DNSSEC to validate all DNS query responses before connecting to the IP address designated \
in the DNS response.\n\
While being more secure, this can lead to connection problems in certain networks \
like hotel wifi, ugly mobile carriers etc.
"""
                        ).font(.footnote)
                    }
                }
                
                Toggle(isOn: $generalSettingsDefaultsDB.webrtcAllowP2P) {
                    Text("Calls: Allow P2P sessions").font(.body)
                    Text("Allow your phone to establish a direct network connection to the remote party. This might leak your IP address to the caller/callee.").font(.footnote)
                }
            }
            
            Section(header: Text("On this device")) {
                Toggle(isOn: $generalSettingsDefaultsDB.autodeleteAllMessagesAfter3Days) {
                    Text("Autodelete all messages after 3 days")
                }
            }
        }
        .navigationBarTitle("Security", displayMode: .inline)
    }
}

struct PrivacySettings: View {
    @ObservedObject var generalSettingsDefaultsDB = GeneralSettingsDefaultsDB()
    
    var body: some View {
        Form {
            Section(header: Text("Activity indications")) {
                Toggle(isOn: $generalSettingsDefaultsDB.sendReceivedMarkers) {
                    Text("Send message received").font(.body)
                    Text("Let your contacts know if you received a message.").font(.footnote)
                }
                Toggle(isOn: $generalSettingsDefaultsDB.sendDisplayedMarkers) {
                    Text("Send message displayed state").font(.body)
                    Text("Let your contacts know if you read a message.").font(.footnote)
                }
                Toggle(isOn: $generalSettingsDefaultsDB.sendLastChatState) {
                    Text("Send typing notifications").font(.body)
                    Text("Let your contacts know if you are typing a message.").font(.footnote)
                }
                Toggle(isOn: $generalSettingsDefaultsDB.sendLastUserInteraction) {
                    Text("Send last interaction time").font(.body)
                    Text("Let your contacts know when you last opened the app.").font(.footnote)
                }
            }
            
            Section(header: Text("Interactions")) {
                Toggle(isOn: $generalSettingsDefaultsDB.allowNonRosterContacts) {
                    Text("Accept incoming messages from strangers").font(.body)
                    Text("Allow contacts not in your contact list to contact you.").font(.footnote)
                }
                Toggle(isOn: $generalSettingsDefaultsDB.allowCallsFromNonRosterContacts) {
                    Text("Accept incoming calls from strangers").font(.body)
                    Text("Allow contacts not in your contact list to call you.").font(.footnote)
                }.disabled(!generalSettingsDefaultsDB.allowNonRosterContacts)
            }
            
            Section(header: Text("Misc")) {
                Toggle(isOn: $generalSettingsDefaultsDB.allowVersionIQ) {
                    Text("Publish version").font(.body)
                    Text("Allow contacts in your contact list to query your Monal and iOS versions.").font(.footnote)
                }
                Toggle(isOn: $generalSettingsDefaultsDB.webrtcUseFallbackTurn) {
                    Text("Calls: Allow TURN fallback to Monal-Servers").font(.body)
                    Text("This will make calls possible even if your XMPP server does not provide a TURN server.").font(.footnote)
                }
            }
        }
        .navigationBarTitle("Privacy", displayMode: .inline)
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
                Picker(selection: $generalSettingsDefaultsDB.notificationPrivacySetting, label: Text("Notification privacy")) {
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
        .navigationBarTitle("Notifications", displayMode: .inline)
    }
}

struct AttachmentSettings: View {
    @ObservedObject var generalSettingsDefaultsDB = GeneralSettingsDefaultsDB()
    
    var body: some View {
        Form {
            Section(header: Text("General File Transfer Settings")) {
                Toggle(isOn: $generalSettingsDefaultsDB.autodownloadFiletransfers) {
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
