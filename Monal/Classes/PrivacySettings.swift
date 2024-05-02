//
//  PrivacySettings.swift
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

class PrivacyDefaultDB: ObservableObject {
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
}


struct PrivacySettings: View {
    @ObservedObject var privacyDefaultDB = PrivacyDefaultDB()
    
    var body: some View {
        Form {
            Section(header:Text("Privacy and security settings")) {
                NavigationLink(destination: PrivacyScreen()) {
                    HStack{
                        Image(systemName: "lock.shield")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                        Text("Privacy & Security")
                    }
                }
                NavigationLink(destination: PublishingScreen()) {
                    HStack{
                        Image(systemName: "eye")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                        Text("Publishing")
                    }
                }
                NavigationLink(destination: PreviewsScreen()) {
                    HStack{
                        Image(systemName: "doc.text.magnifyingglass")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                        Text("Previews")
                    }
                }
                NavigationLink(destination: CommunicationScreen()) {
                    HStack{
                        Image(systemName: "bubble.left.and.bubble.right")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                        Text("Communication")
                    }
                }
                
                NavigationLink(destination: MLAutoDownloadFiletransferSettingView()) {
                    HStack{
                        Image(systemName: "square.and.arrow.down")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                        Text("Media Upload & Download")
                    }
                }
            }
        }
        .navigationBarTitle("Privacy Settings")
        .onAppear {
            privacyDefaultDB.hasSeenPrivacySettings = true
        }
    }
}

struct PrivacyScreen: View {
    @ObservedObject var privacyDefaultDB = PrivacyDefaultDB()
    
    var body: some View {
        Form {
            Picker("Notification privacy", selection: $privacyDefaultDB.notificationPrivacySetting) {
                ForEach(NotificationPrivacySettingOption.allCases, id: \.self) { option in
                    Text(getNotificationPrivacyOption(option)).tag(option.rawValue)
                }
            }
            .frame(width: .infinity, height: 56, alignment: .trailing)
            Toggle(isOn: $privacyDefaultDB.omemoDefaultOn) {
                Text("Enable encryption by default for new chats")
            }
            Toggle(isOn: $privacyDefaultDB.autodeleteAllMessagesAfter3Days) {
                Text("Autodelete all messages after 3 days")
            }
        }
        .navigationBarTitle("Privacy & security", displayMode: .inline)
    }
}

struct PublishingScreen: View {
    @ObservedObject var privacyDefaultDB = PrivacyDefaultDB()
    
    var body: some View {
        Form {
            Section(header: Text("Publishing")) {
                Toggle(isOn: $privacyDefaultDB.sendLastUserInteraction) {
                    Text("Send last interaction time")
                }
                Toggle(isOn: $privacyDefaultDB.sendLastChatState) {
                    Text("Send typing notifications")
                }
                Toggle(isOn: $privacyDefaultDB.sendReceivedMarkers) {
                    Text("Send message received state")
                }
                Toggle(isOn: $privacyDefaultDB.sendDisplayedMarkers) {
                    Text("Send message displayed state")
                }
            }
            Section(header: Text("Appearance")) {
                Toggle(isOn: $privacyDefaultDB.showKeyboardOnChatOpen) {
                    Text("Autofocus text input on chat open")
                }
            }
        }
        .navigationBarTitle("Publishing & appearance", displayMode: .inline)
    }
}

struct PreviewsScreen: View {
    @ObservedObject var privacyDefaultDB = PrivacyDefaultDB()
    
    var body: some View {
        Form {
            Toggle(isOn: $privacyDefaultDB.showGeoLocation) {
                Text("Show inline geo location")
            }
            Toggle(isOn: $privacyDefaultDB.showURLPreview) {
                Text("Show URL previews")
            }
        }
        .navigationBarTitle("Previews", displayMode: .inline)
    }
}

struct CommunicationScreen: View {
    @ObservedObject var privacyDefaultDB = PrivacyDefaultDB()
    
    var body: some View {
        Form {
            Toggle(isOn: $privacyDefaultDB.allowNonRosterContacts) {
                Text("Allow contacts not in my contact list to contact me")
            }
            Toggle(isOn: $privacyDefaultDB.allowVersionIQ) {
                Text("Allow approved contacts to query my Monal and iOS version")
            }
            Toggle(isOn: $privacyDefaultDB.allowCallsFromNonRosterContacts) {
                Text("Calls: Allow contacts not in my contact list to call me")
            }
            Toggle(isOn: $privacyDefaultDB.webrtcAllowP2P) {
                Text("Calls: Allow P2P sessions")
            }
            Toggle(isOn: $privacyDefaultDB.webrtcUseFallbackTurn) {
                Text("Calls: Allow TURN fallback to Monal-Servers")
            }
        }
        .navigationBarTitle("Communication", displayMode: .inline)
    }
}

struct MLAutoDownloadFiletransferSettingView: View {
    @ObservedObject var privacyDefaultDB = PrivacyDefaultDB()
    
    var body: some View {
        Form {
            Section(header: Text("General File Transfer Settings")) {
                Toggle(isOn: $privacyDefaultDB.autodownloadFiletransfers) {
                    Text("Auto-Download Media")
                }
            }
            
            Section(header: Text("Download Settings")) {
                
                Text("Adjust the maximum file size for auto-downloads over WiFi")
                    .foregroundColor(.secondary)
                    .font(.footnote)
                Slider(
                    value: $privacyDefaultDB.autodownloadFiletransfersWifiMaxSize.bytecount(mappedTo: 1024*1024),
                    in: 1.0...100.0,
                    step: 1.0,
                    minimumValueLabel: Text("1 MiB"),
                    maximumValueLabel: Text("100 MiB"),
                    label: {
                        Text("Load over wifi")
                    }
                )
                Text("Load over WiFi up to: \(UInt(privacyDefaultDB.autodownloadFiletransfersWifiMaxSize/(1024*1024))) MiB")
            }
            
            Text("Adjust the maximum file size for auto-downloads over cellular network")
                .foregroundColor(.secondary)
                .font(.footnote)
            Slider(
                value: $privacyDefaultDB.autodownloadFiletransfersMobileMaxSize.bytecount(mappedTo: 1024*1024),
                in: 0.0...100.0,
                step: 1.0,
                minimumValueLabel: Text("1 MiB"),
                maximumValueLabel: Text("100 MiB"),
                label: {
                    Text("Load over Cellular")
                }
            )
            Text("Load over cellular up to: \(Int(privacyDefaultDB.autodownloadFiletransfersMobileMaxSize/(1024*1024))) MiB")
            
            Section(header: Text("Upload Settings")) {
                Text("Adjust the quality of images uploaded")
                    .foregroundColor(.secondary)
                    .font(.footnote)
                Slider(
                    value: $privacyDefaultDB.imageUploadQuality,
                    in: 0.33...1.0,
                    step: 0.01,
                    minimumValueLabel: Text("33%"),
                    maximumValueLabel: Text("100%"),
                    label: {
                        Text("Upload Settings")
                    }
                )
                Text("Image Upload Quality: \(String(format: "%.0f%%", privacyDefaultDB.imageUploadQuality*100))")
            }
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        PrivacySettings()
    }
}
