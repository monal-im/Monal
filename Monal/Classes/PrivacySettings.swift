//
//  PrivacySettings.swift
//  Monal
//
//  Created by Vaidik Dubey on 22/03/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import Combine

//TODO: rewrite this using swiftui
struct ViewControllerWrapper: UIViewControllerRepresentable{
    func makeUIViewController(context: Context) -> UIViewController {
        let storyboard = UIStoryboard(name: "Settings", bundle: Bundle.main)
        let controller = storyboard.instantiateViewController(identifier: "Autodownload")
        return controller
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        
    }
}

enum NotificationPrivacySettingOption: Int , CaseIterable, RawRepresentable{
    case displayNameAndMessage = 1
    case displayOnlyName = 2
    case displayOnlyPlaceholder = 3
}

func getNotificationPrivacyOption(_ option: NotificationPrivacySettingOption) -> String {
    switch option{
        case .displayNameAndMessage:
            return NSLocalizedString("Display Name And Message", comment: "")
         case .displayOnlyName:
            return NSLocalizedString("Display Only Name", comment: "")
         case .displayOnlyPlaceholder:
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
    
    @defaultsDB("WebrtcAllowP2P")
    var webrtcAllowP2P: Bool
    
    @defaultsDB("WebrtcUseFallbackTurn")
    var webrtcUseFallbackTurn: Bool
    
    @defaultsDB("AllowVersionIQ")
    var allowVersionIQ: Bool
    
    @defaultsDB("AllowNonRosterContacts")
    var allowNonRosterContacts: Bool
    
    @defaultsDB("HasSeenPrivacySettings")
    var hasSeenPrivacySettings: Bool
}


struct PrivacySettings: View {
    @ObservedObject var privacyDefaultDB = PrivacyDefaultDB()
    
    var body: some View {
        Form {
            Section(header: Text("Notification Settings")) {
                Picker("Notification Privacy Setting", selection: $privacyDefaultDB.notificationPrivacySetting) {
                    ForEach(NotificationPrivacySettingOption.allCases, id: \.self) { option in
                        Text(getNotificationPrivacyOption(option)).tag(option.rawValue)
                    }
                }
                
                NavigationLink(destination: PrivacyScreen()) {
                    Text("Privacy & Security")
                }
                NavigationLink(destination: InteractionScreen()) {
                    Text("Interactions settings")
                }
                NavigationLink(destination: LocationScreen()) {
                    Text("Location & Sharing")
                }
                NavigationLink(destination: CommunicationScreen()) {
                    Text("Communications")
                }
                
                NavigationLink(destination: ViewControllerWrapper()) {
                    Text("Media Upload & Download")
                }
            }
        }
        .navigationTitle("Privacy Settings")
        .onAppear {
            privacyDefaultDB.hasSeenPrivacySettings = true
        }
    }
}

struct PrivacyScreen: View {
    @ObservedObject var privacyDefaultDB = PrivacyDefaultDB()
    
    var body: some View {
        Form {
            Toggle("Enable encryption by default for new chats", isOn: $privacyDefaultDB.omemoDefaultOn)
            Toggle("Autodelete all messages after 3 days", isOn: $privacyDefaultDB.omemoDefaultOn)
        }
        .navigationBarTitle("Privacy & security", displayMode: .inline)
    }
}

struct InteractionScreen: View {
    @ObservedObject var privacyDefaultDB = PrivacyDefaultDB()
    
    var body: some View {
        Form {
            Toggle("Send Last Interaction Time", isOn: $privacyDefaultDB.sendLastUserInteraction)
            Toggle("Send Typing Notifications", isOn: $privacyDefaultDB.sendLastChatState)
            Toggle("Send message received state", isOn: $privacyDefaultDB.sendReceivedMarkers)
            Toggle("Sync Read-Markers", isOn: $privacyDefaultDB.sendDisplayedMarkers)
        }
        .navigationBarTitle("Interaction Settings", displayMode: .inline)
    }
}

struct LocationScreen: View {
    @ObservedObject var privacyDefaultDB = PrivacyDefaultDB()
    
    var body: some View {
        Form {
            Toggle("Show Inline Geo Location", isOn: $privacyDefaultDB.showGeoLocation)
            Toggle("Show URL previews", isOn: $privacyDefaultDB.showURLPreview)
        }
        .navigationBarTitle("Location & Sharing", displayMode: .inline)
    }
}

struct CommunicationScreen: View {
    @ObservedObject var privacyDefaultDB = PrivacyDefaultDB()
    
    var body: some View {
        Form {
            Toggle("Calls: Allow P2P sessions", isOn: $privacyDefaultDB.webrtcAllowP2P)
            Toggle("Calls: Allow TURN fallback to Monal-Servers", isOn: $privacyDefaultDB.webrtcUseFallbackTurn)
            Toggle("Allow approved contacts to query my Monal and iOS version", isOn: $privacyDefaultDB.allowVersionIQ)
            Toggle("Allow contacts not in my Contact list to contact me", isOn: $privacyDefaultDB.allowNonRosterContacts)
        }
        .navigationBarTitle("Communication", displayMode: .inline)
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        PrivacySettings()
    }
}
