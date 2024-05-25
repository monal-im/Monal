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
    
    let autodeleteOptions = [
        0:"Off", 30:"30 seconds", 300:"5 minutes", 3600:"1 hour",
        28800:"8 hours", 86400:"1 day", 604800:"1 week", 2419200:"4 weeks", -1:"Custom"
    ]
    
    @State private var showingCustomTimeSheet = false
    @State private var selectedOptionIndex: Int = 0
    @State private var customTimeString = ""
    var body: some View {
        Form {
            Picker("Notification privacy", selection: $privacyDefaultDB.notificationPrivacySetting) {
                ForEach(NotificationPrivacySettingOption.allCases, id: \.self) { option in
                    Text(getNotificationPrivacyOption(option)).tag(option.rawValue)
                }
            }
            Toggle("Enable encryption by default for new chats", isOn: $privacyDefaultDB.omemoDefaultOn)
            Picker("Autodelete all messages after", selection: $privacyDefaultDB.AutodeleteInterval) {
                ForEach(autodeleteOptions.keys.sorted(), id: \.self) { key in
                    Text(autodeleteOptions[key, default: "Custom"]).tag(key)
                }
            }
            .onChange(of: privacyDefaultDB.AutodeleteInterval) { newValue in
                if newValue == -1  {
                    showingCustomTimeSheet = true
                }
            }
        }
        .onAppear(perform: {
            print(privacyDefaultDB.AutodeleteInterval,"LOGN")
        })
        .sheet(isPresented: $showingCustomTimeSheet) {
            NavigationView {
                Form {
                    TextField("Enter time in minutes", text: $customTimeString)
                        .keyboardType(.numberPad)
                    Button("Set") {
                        if let minutes = Int(customTimeString), minutes>0 {
                            privacyDefaultDB.AutodeleteInterval = minutes * 60
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
        .navigationBarTitle("Privacy & security", displayMode: .inline)
    }
}

struct PublishingScreen: View {
    @ObservedObject var privacyDefaultDB = PrivacyDefaultDB()
    
    var body: some View {
        Form {
            Toggle("Send last interaction time", isOn: $privacyDefaultDB.sendLastUserInteraction)
            Toggle("Send typing notifications", isOn: $privacyDefaultDB.sendLastChatState)
            Toggle("Send message received state", isOn: $privacyDefaultDB.sendReceivedMarkers)
            Toggle("Send message displayed state", isOn: $privacyDefaultDB.sendDisplayedMarkers)
        }
        .navigationBarTitle("Publishing", displayMode: .inline)
    }
}

struct PreviewsScreen: View {
    @ObservedObject var privacyDefaultDB = PrivacyDefaultDB()
    
    var body: some View {
        Form {
            Toggle("Show inline geo location", isOn: $privacyDefaultDB.showGeoLocation)
            Toggle("Show URL previews", isOn: $privacyDefaultDB.showURLPreview)
        }
        .navigationBarTitle("Previews", displayMode: .inline)
    }
}

struct CommunicationScreen: View {
    @ObservedObject var privacyDefaultDB = PrivacyDefaultDB()
    
    var body: some View {
        Form {
            Toggle("Allow contacts not in my contact list to contact me", isOn: $privacyDefaultDB.allowNonRosterContacts)
            Toggle("Allow approved contacts to query my Monal and iOS version", isOn: $privacyDefaultDB.allowVersionIQ)
            Toggle("Calls: Allow contacts not in my contact list to call me", isOn: $privacyDefaultDB.allowCallsFromNonRosterContacts)
            Toggle("Calls: Allow P2P sessions", isOn: $privacyDefaultDB.webrtcAllowP2P)
            Toggle("Calls: Allow TURN fallback to Monal-Servers", isOn: $privacyDefaultDB.webrtcUseFallbackTurn)
        }
        .navigationBarTitle("Communication", displayMode: .inline)
    }
}

struct MLAutoDownloadFiletransferSettingView: View {
    @ObservedObject var privacyDefaultDB = PrivacyDefaultDB()
    
    var body: some View {
        Form {
            Section(header: Text("General File Transfer Settings")) {
                Toggle("Auto-Download Media", isOn: $privacyDefaultDB.autodownloadFiletransfers)
            }
            
            Section(header: Text("Download Settings")) {
                
                Text("Adjust the maximum file size for auto-downloads over WiFi")
                    .foregroundColor(.secondary)
                    .font(.footnote)
                Slider(value: $privacyDefaultDB.autodownloadFiletransfersWifiMaxSize.bytecount(mappedTo: 1024*1024),
                       in: 1.0...100.0,
                       step: 1.0,
                       minimumValueLabel: Text("1 MiB"),
                       maximumValueLabel: Text("100 MiB"),
                       label: {Text("Load over wifi")}
                )
                Text("Load over WiFi upto : \(UInt(privacyDefaultDB.autodownloadFiletransfersWifiMaxSize/(1024*1024))) MiB")
            }
            
            Text("Adjust the maximum file size for auto-downloads over cellular network")
                .foregroundColor(.secondary)
                .font(.footnote)
            Slider(value: $privacyDefaultDB.autodownloadFiletransfersMobileMaxSize.bytecount(mappedTo: 1024*1024),
                   in: 0.0...100.0,
                   step: 1.0,
                   minimumValueLabel: Text("1 MiB"),
                   maximumValueLabel: Text("100 MiB"),
                   label: {Text("Load over Cellular")}
            )
            Text("Load over cellular upto : \(Int(privacyDefaultDB.autodownloadFiletransfersMobileMaxSize/(1024*1024))) MiB")
            
            Section(header: Text("Upload Settings")) {
                Text("Adjust the quality of images uploaded")
                    .foregroundColor(.secondary)
                    .font(.footnote)
                Slider(value: $privacyDefaultDB.imageUploadQuality,
                       in: 0.33...1.0,
                       step: 0.01,
                       minimumValueLabel: Text("33%"),
                       maximumValueLabel: Text("100%"),
                       label: {Text("Upload Settings")
                })
                Text("Image Upload Quality : \(String(format: "%.0f%%", privacyDefaultDB.imageUploadQuality*100))")
            }
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        PrivacySettings()
    }
}
