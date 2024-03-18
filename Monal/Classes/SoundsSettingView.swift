//
//  SoundsSettingView.swift
//  Monal
//
//  Created by 阿栋 on 3/6/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import SwiftUI
import AVFoundation

struct SoundsSettingView: View {
    @State private var selectedSound: String
    @State private var playSounds: Bool
    @State private var audioPlayer: AVAudioPlayer?
    @State private var showingSoundPicker = false

    let sounds: [String] = MLSoundManager.sharedInstance().loadSoundFromResource()
    
    let contact: ObservableKVOWrapper<MLContact>?
    let delegate: SheetDismisserProtocol
    
    init(contact: ObservableKVOWrapper<MLContact>?, delegate: SheetDismisserProtocol) {
        self.contact = contact
        self.delegate = delegate
        var soundKey: String
        var suffixBuiltin: String
        var suffixCustom: String
        soundKey = "chat_\(contact?.obj.contactJid.lowercased() ?? "global")_AlertSoundFile"
        suffixCustom = "Custom"
        suffixBuiltin = "Builtin"
        _playSounds = State(initialValue: HelperTools.defaultsDB().bool(forKey: "Sound"))
        _selectedSound = State(initialValue: "Xylophone")
        let savedSound = HelperTools.defaultsDB().string(forKey: soundKey) ?? "Xylophone"
        
        if savedSound.hasSuffix(suffixCustom) {
            _selectedSound = State(initialValue: "Custom Sound")
        } else if savedSound == "System Sound" {
            _selectedSound = State(initialValue: "System Sound")
        } else if savedSound.hasSuffix(suffixBuiltin) {
            let savedSoundFileName = URL(fileURLWithPath: extractMiddleComponent(from: savedSound) ?? "").deletingPathExtension().lastPathComponent
            let soundIndex = sounds.firstIndex(of: savedSoundFileName) ?? -1;
            if (soundIndex == -1) {
                _selectedSound = State(initialValue: "Xylophone")
            } else {
                _selectedSound = State(initialValue: sounds[soundIndex])
            }
        }
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
            if playSounds {
                Section {
                    HStack {
                        Text("Custom Sound")
                            .onTapGesture {
                                self.showingSoundPicker = true
                            }
                        
                        Spacer()
                        
                        if selectedSound.hasPrefix("Custom Sound") {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .sheet(isPresented: $showingSoundPicker) {
                        LazyClosureView(SoundPickerView(contact: contact, onSoundPicked: { (url: URL?) in
                            if url == nil {
                                let fileName = "\(contact?.obj.contactJid.lowercased() ?? "global")_Xylophone.aif_Builtin"
                                self.selectedSound = "Xylophone"
                                let key = "chat_\(contact?.obj.contactJid.lowercased() ?? "global")_AlertSoundFile"
                                HelperTools.defaultsDB().setValue(fileName, forKey: key)
                                HelperTools.defaultsDB().synchronize()
                            } else {
                                do {
                                    let soundData = try Data(contentsOf: url!)
                                    let prefix = contact?.obj.contactJid.lowercased() ??  "global"
                                    let fileName = "\(prefix)_\(url!.lastPathComponent)_Custom"
                                    self.selectedSound = "Custom Sound"
                                    let key = "chat_\(contact?.obj.contactJid.lowercased() ?? "global")_AlertSoundFile"
                                    HelperTools.defaultsDB().setValue(fileName, forKey: key)
                                    HelperTools.defaultsDB().synchronize()
                                    MLSoundManager.sharedInstance().saveSound(soundData, andWithSoundFileName: fileName, withPrefix: prefix)
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
                let key = "chat_\(contact?.obj.contactJid.lowercased() ?? "global")_AlertSoundFile"
                HelperTools.defaultsDB().setValue(self.selectedSound, forKey: key)
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
            let prefix = contact?.obj.contactJid.lowercased() ?? "global"
            let key = "chat_\(prefix)_AlertSoundFile"
            let soundFileName = "\(contact?.obj.contactJid.lowercased() ?? "global")_\(soundName).aif_Builtin"
            HelperTools.defaultsDB().setValue(soundFileName, forKey: key)
            MLSoundManager.sharedInstance().saveSound(soundData, andWithSoundFileName: soundFileName, withPrefix: prefix)
        } catch {
            DDLogDebug("Error playing sound: \(error)")
        }
    }
    
    func extractMiddleComponent(from string: String) -> String? {
        let components = string.split(separator: "_")
        guard components.count > 2 else {
            DDLogDebug("Format not recognized or missing sections.")
            return nil
        }
        let middleComponents = components[1..<components.count-1]
        let extractedString = middleComponents.joined(separator: "_")
        return extractedString
    }
}
