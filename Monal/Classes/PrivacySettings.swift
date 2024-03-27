//
//  PrivacySettings.swift
//  Monal
//
//  Created by Vaidik Dubey on 22/03/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//




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



struct PrivacySettings: View{
    
    @ObservedObject var privacyDefaultDB: PrivacyDefaultDB
    
    init() {
        self.privacyDefaultDB = PrivacyDefaultDB()
    }
    
    var body: some View {
            
            Form {
                Section(header: Text("Notification Settings"))
                {
                    
                    Picker("Notification Privacy Setting", selection: Binding(
                        get: { self.privacyDefaultDB.notificationPrivacySetting! },
                        set: { self.privacyDefaultDB.notificationPrivacySetting = $0 }
                    )){
                        ForEach(NotificationPrivacySettingOption.allCases, id: \.self) { option in
                            Text(getNotificationPrivacyOption(option))
                                .tag(option.rawValue)
                        }
                        
                    }
                    
                    NavigationLink(destination: PrivacyScreen(privacyDefaultDB: PrivacyDefaultDB())){
                        
                        Text("Privacy & Security")
                        
                    }
                    NavigationLink(destination: InteractionScreen(privacyDefaultDB: PrivacyDefaultDB())){
                        
                        Text("Interactions settings")
                        
                    }
                    NavigationLink(destination: LocationScreen(privacyDefaultDB: PrivacyDefaultDB())){
                        
                        Text("Location & Sharing")
                        
                    }
                    NavigationLink(destination: CommunicationScreen(privacyDefaultDB: PrivacyDefaultDB())){
                        
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
    
    



func getNotificationPrivacyOption(_ option: NotificationPrivacySettingOption) -> String{
    
    switch option{
        case .displayNameAndMessage:
            return NSLocalizedString("Display name And Message", comment: "")
         case .displayOnlyName:
            return NSLocalizedString("Display Only Name", comment: "")
         case .displayOnlyPlaceholder:
            return NSLocalizedString("Display Only Placeholder", comment: "")
    }
}

struct PrivacyScreen: View {
    @ObservedObject var privacyDefaultDB: PrivacyDefaultDB
    var body: some View {
        Form {
            Section(header: Text("Privacy & security"))
            {
                
                Toggle("Enable encryption by default for new chats", isOn: Binding(
                    get: { self.privacyDefaultDB.omemoDefaultOn!},
                    set: { self.privacyDefaultDB.omemoDefaultOn = $0 }
                ))
                Toggle("Autodelete all messages after 3 days", isOn: Binding(
                    get: { self.privacyDefaultDB.autodeleteAllMessagesAfter3Days!},
                    set: {self.privacyDefaultDB.omemoDefaultOn = $0 }
                ))
                
            }
        }
    }
}



struct InteractionScreen: View {
    @ObservedObject var privacyDefaultDB: PrivacyDefaultDB
    
    var body: some View {
        Form {
            
            Section(header: Text("Interaction Settings")){
                
                Toggle("Send Last Interaction Time", isOn: Binding(
                    get: { self.privacyDefaultDB.sendLastUserInteraction! },
                    set: { self.privacyDefaultDB.sendLastUserInteraction = $0 }
                ))
                Toggle("Send Typing Notifications", isOn: Binding(
                    get: { self.privacyDefaultDB.sendLastChatState!},
                    set: { self.privacyDefaultDB.sendLastChatState = $0 }
                ))
                Toggle("Send message received state", isOn: Binding(
                    get: { self.privacyDefaultDB.sendReceivedMarkers! },
                    set: { self.privacyDefaultDB.sendReceivedMarkers = $0 }
                ))
                Toggle("Sync Read-Markers", isOn: Binding(
                    get: { self.privacyDefaultDB.sendDisplayedMarkers! },
                    set: { self.privacyDefaultDB.sendDisplayedMarkers = $0 }
                ))
                
            }
            
        }
    }
}

struct LocationScreen: View {
    
    @ObservedObject var privacyDefaultDB: PrivacyDefaultDB
    
    var body: some View {
        Form {
            
            Section(header: Text("Location & Sharing"))
            {
                Toggle("Show Inline Geo Location", isOn: Binding(
                    get: { self.privacyDefaultDB.showGeoLocation!},
                    set: { self.privacyDefaultDB.showGeoLocation = $0 }
                ))
                Toggle("Show URL previews", isOn: Binding(
                    get: { self.privacyDefaultDB.showURLPreview! },
                    set: { self.privacyDefaultDB.showURLPreview = $0 }
                ))
                
            }
            
        }
    }
}


struct CommunicationScreen: View {
    @ObservedObject var privacyDefaultDB: PrivacyDefaultDB
    
    var body: some View {
        Form {
            Section(header: Text("Communication"))
            {
                Toggle("Calls: Allow P2P sessions", isOn: Binding(
                    get: { self.privacyDefaultDB.webrtcAllowP2P ?? true },
                    set: { self.privacyDefaultDB.webrtcAllowP2P = $0 }
                ))
                Toggle("Calls: Allow TURN fallback to Monal-Servers", isOn: Binding(
                    get: { self.privacyDefaultDB.webrtcUseFallbackTurn!},
                    set: { self.privacyDefaultDB.webrtcUseFallbackTurn = $0 }
                ))
                Toggle("Allow approved contacts to query my Monal and iOS version", isOn: Binding(
                    get: { self.privacyDefaultDB.allowVersionIQ! },
                    set: { self.privacyDefaultDB.allowVersionIQ = $0 }
                ))
                Toggle("Allow contacts not in my Contact list to contact me", isOn: Binding(
                    get: { self.privacyDefaultDB.allowNonRosterContacts ?? true },
                    set: { self.privacyDefaultDB.allowNonRosterContacts = $0 }
                ))
                //
                
            }
            
        }
    }
}
struct ContentView_Previews: PreviewProvider
{
    static var previews: some View
    {
        PrivacySettings()
    }
}



