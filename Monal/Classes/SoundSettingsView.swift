//
//  SoundsSettingView.swift
//  Monal
//
//  Created by 阿栋 on 4/3/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import AVFoundation

class SoundsDefaultsDB: ObservableObject {
    @defaultsDB("Sound")
    var soundsEnabled:Bool
}

struct SoundSettingsView: View {
    @ObservedObject var defaultsDB = SoundsDefaultsDB()
    let contact: ObservableKVOWrapper<MLContact>
    let delegate: SheetDismisserProtocol
    
    @State private var selectedSound: String
    @State private var playSounds: Bool
    @State private var audioPlayer: AVAudioPlayer?
    @State private var showingSoundPicker = false
    @State private var connectedAccounts: [xmpp]
    @State private var selectedAccount = -1;

    let sounds: [String] = MLSoundManager.sharedInstance().listBundledSounds()
    
    
    init(contact: ObservableKVOWrapper<MLContact>, delegate: SheetDismisserProtocol) {
        self.contact = contact
        self.delegate = delegate
        
        var soundFileName: String
        let receiverJID = "Default"
        let senderJID = contact?.obj.contactJid.lowercased() ?? "global"
        soundFileName = MLSoundManager.sharedInstance().getSoundName(forSenderJID: senderJID, andReceiverJID: receiverJID)
        if (!sounds.contains(soundFileName) && soundFileName != "") {
            soundFileName = "Custom Sound"
        } else if soundFileName == "" {
            soundFileName = "System Sound"
        }
        _selectedSound = State(initialValue: soundFileName)
    }

    
    var body: some View {
        List {
            Section {
                Toggle(isOn: $defaultsDB.soundsEnabled) {
                    if contact.isSelf {
                        Text("Play Sounds Globally")
                    } else {
                        Text("Play Sounds for this Contact")
                    }
                }
            }
            
            if $defaultsDB.soundsEnabled {
                Section {
                    HStack {
                        Text("Custom Sound")
                            .onTapGesture {
                                self.showingSoundPicker = true
                            }
                        
                        Spacer()
                        
                        if selectedSound == "Custom Sound" {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .sheet(isPresented: $showingSoundPicker) {
                        let account = selectedAccount == -1 ? nil : self.connectedAccounts[self.selectedAccount]
                        let receiverJID = selectedAccount == -1 ? "Default" : account!.connectionProperties.identity.jid.lowercased()
                        let senderJID = contact?.obj.contactJid.lowercased() ?? "global"
                        LazyClosureView(SoundPickerView(contact: contact, receiverJID: receiverJID, senderJID: senderJID, onSoundPicked: { (url: URL?) in
                            if (url != nil) {
                                do {
                                    let soundData = try Data(contentsOf: url!)
                                    self.selectedSound = "Custom Sound"
                                    let soundFileName = url!.lastPathComponent
                                    MLSoundManager.sharedInstance().saveSound(soundData, forSenderJID: senderJID, andReceiverJID: receiverJID, withSoundFileName: soundFileName, isCustomSound: 1)
                                } catch {
                                    DDLogDebug("Error playing sound: \(error)")
                                }
                            }
                        }, delegate: delegate))
                    }
                }
            }
            
            
            if playSounds {
                soundSelectionSection
            }

            if playSounds {
                Section {
                    HStack {
                        Spacer()
                        Text("Sounds courtesy Emrah")
                            .foregroundColor(.gray)
                        Spacer()
                    }
                }
            }
        }
        .navigationBarTitle("Sounds", displayMode: .inline)
        .listStyle(GroupedListStyle())
    }
    
    var soundSelectionSection: some View {
        Section(header: Text("SELECT SOUNDS THAT ARE PLAYED WITH NEW MESSAGE NOTIFICATIONS. DEFAULT IS XYLOPHONE.")) {
            HStack {
                Text("System Sound")
                Spacer()
                if selectedSound == "System Sound" {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                self.selectedSound = "System Sound"
                let account = selectedAccount == -1 ? nil : self.connectedAccounts[self.selectedAccount]
                let receiverJID = account == nil ? "Default" : account!.connectionProperties.identity.jid.lowercased()
                let senderJID = contact?.obj.contactJid.lowercased() ?? "global"
                DataLayer.sharedInstance().deleteSound(forAccountId: receiverJID, buddyId: senderJID)
                self.audioPlayer?.stop()
            }

            ForEach(sounds.filter { $0 != "System Sound" }, id: \.self) { sound in
                HStack {
                    Text(sound)
                    Spacer()
                    if sound == selectedSound {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    self.selectedSound = sound
                    self.playSound(soundName: sound)
                }
            }
        }
    }
    
    func playSound(soundName: String) {
        guard let url = Bundle.main.url(forResource: soundName, withExtension: "aif", subdirectory: "AlertSounds") else { return }
        do {
            let soundData = try Data(contentsOf: url)
            audioPlayer = try AVAudioPlayer(data: soundData)
            audioPlayer?.play()
            let account = selectedAccount == -1 ? nil : self.connectedAccounts[self.selectedAccount]
            let receiverJID = account == nil ? "Default" : account!.connectionProperties.identity.jid.lowercased()
            let senderJID = contact?.obj.contactJid.lowercased() ?? "global"
            let soundFileName = self.selectedSound
            MLSoundManager.sharedInstance().saveSound(soundData, forSenderJID: senderJID, andReceiverJID: receiverJID, withSoundFileName: soundFileName, isCustomSound: 0)
        } catch {
            DDLogDebug("Error playing sound: \(error)")
        }
    }
}

