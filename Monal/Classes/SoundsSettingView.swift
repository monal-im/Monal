//
//  SoundsSettingView.swift
//  Monal
//
//  Created by 阿栋 on 4/3/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import SwiftUI
import AVFoundation

struct SoundsSettingView: View {
    @State private var selectedSound: String
    @State private var playSounds: Bool
    @State private var audioPlayer: AVAudioPlayer?
    @State private var showingSoundPicker = false
    @State private var connectedAccounts: [xmpp]
    @State private var selectedAccount = -1;

    let sounds: [String] = MLSoundManager.sharedInstance().listBundledSounds()
    
    let contact: ObservableKVOWrapper<MLContact>?
    let delegate: SheetDismisserProtocol
    
    init(contact: ObservableKVOWrapper<MLContact>?, delegate: SheetDismisserProtocol) {
        self.contact = contact
        self.delegate = delegate
        _playSounds = State(initialValue: HelperTools.defaultsDB().bool(forKey: "Sound"))
        self.connectedAccounts = MLXMPPManager.sharedInstance().connectedXMPP as! [xmpp]
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
            if (contact == nil) {
                Section {
                    Toggle(isOn: $playSounds) {
                        Text("Play Sounds")
                    }
                    .onChange(of: playSounds) { newValue in
                        HelperTools.defaultsDB().setValue(newValue, forKey: "Sound")
                    }
                }
            }
            
            if connectedAccounts.count >= 1 {
                Picker("Use account", selection: $selectedAccount) {
                    Text("Default").tag(-1)
                    ForEach(Array(self.connectedAccounts.enumerated()), id: \.element) { idx, account in
                        Text(account.connectionProperties.identity.jid).tag(idx)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedAccount) { newValue in
                    let account = selectedAccount == -1 ? nil : self.connectedAccounts[self.selectedAccount]
                    let receiverJID = account == nil ? "Default" : account!.connectionProperties.identity.jid.lowercased()
                    let senderJID = contact?.obj.contactJid.lowercased() ?? "global"
                    var soundFileName = MLSoundManager.sharedInstance().getSoundName(forSenderJID: senderJID, andReceiverJID: receiverJID)
                    if soundFileName == "" {
                        soundFileName = "System Sound"
                    }
                    selectedSound = soundFileName
                }
            }
            
            if playSounds {
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

