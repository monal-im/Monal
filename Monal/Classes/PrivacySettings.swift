//
//  PrivacySettings.swift
//  Monal
//
//  Created by Vaidik Dubey on 22/03/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//


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
    
    @defaultsDB("webrtcAllowP2P")
    var webrtcAllowP2P: Bool
    
    @defaultsDB("webrtcUseFallbackTurn")
    var webrtcUseFallbackTurn: Bool
    
    @defaultsDB("allowVersionIQ")
    var allowVersionIQ: Bool
    
    @defaultsDB("allowNonRosterContacts")
    var allowNonRosterContacts: Bool
    
    @defaultsDB("HasSeenPrivacySettings")
    var hasSeenPrivacySettings: Bool
}


struct PrivacySettings: View {
    @ObservedObject var privacyDefaultDB = PrivacyDefaultDB()
    
    var body: some View {
        Form {
            Section(header:Text("Privacy and security settings")) {
                NavigationLink(destination: PrivacyScreen()) {
                    Text("Privacy & Security")
                }
                NavigationLink(destination: PublishingScreen()) {
                    Text("Publishing")
                }
                NavigationLink(destination: PreviewsScreen()) {
                    Text("Previews")
                }
                NavigationLink(destination: CommunicationScreen()) {
                    Text("Communication")
                }
                
                NavigationLink(destination: ViewControllerWrapper()) {
                    Text("Media Upload & Download")
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
            
            Toggle("Enable encryption by default for new chats", isOn: $privacyDefaultDB.omemoDefaultOn)
            Toggle("Autodelete all messages after 3 days", isOn: $privacyDefaultDB.autodeleteAllMessagesAfter3Days)
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
            Toggle("Allow contacts not in my Contact list to contact me", isOn: $privacyDefaultDB.allowNonRosterContacts)
            Toggle("Allow approved contacts to query my Monal and iOS version", isOn: $privacyDefaultDB.allowVersionIQ)
            Toggle("Calls: Allow P2P sessions", isOn: $privacyDefaultDB.webrtcAllowP2P)
            Toggle("Calls: Allow TURN fallback to Monal-Servers", isOn: $privacyDefaultDB.webrtcUseFallbackTurn)
        }
        .navigationBarTitle("Communication", displayMode: .inline)
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        PrivacySettings()
    }
}
