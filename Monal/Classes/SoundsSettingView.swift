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

    let sounds = ["System Sound", "Morse", "Xylophone", "Bloop", "Bing", "Pipa", "Water", "Forest", "Echo", "Area 51", "Wood", "Chirp", "Sonar"]
    
    let contact: ObservableKVOWrapper<MLContact>?
    let delegate: SheetDismisserProtocol
    
    init(contact: ObservableKVOWrapper<MLContact>?, delegate: SheetDismisserProtocol) {
        self.contact = contact
        self.delegate = delegate
        var soundKey: String
        soundKey = "chat_\(contact?.obj.contactJid.lowercased() ?? "")_AlertSoundFile"
        _playSounds = State(initialValue: HelperTools.defaultsDB().bool(forKey: "Sound"))
    
        let savedSound = HelperTools.defaultsDB().string(forKey: soundKey) ?? "Xylophone"
        
        if savedSound == "Xylophone" {
            _selectedSound = State(initialValue: sounds[2])
        } else if savedSound == "CustomizeSound" {
            _selectedSound = State(initialValue: "Custom Sound")
        } else {
            let soundIndex = Int(savedSound.replacingOccurrences(of: "alert", with: "")) ?? -1
            if soundIndex >= 1 && soundIndex <= 12 {
                _selectedSound = State(initialValue: sounds[soundIndex])
            } else if soundIndex == 0 {
                _selectedSound = State(initialValue: "System Sound")
            } else {
                _selectedSound = State(initialValue: sounds[2])
                DDLogVerbose("The audio file does not exist")
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
                        
                        if selectedSound == "Custom Sound" {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .sheet(isPresented: $showingSoundPicker) {
                        LazyClosureView(SoundPickerView(contact: contact, onSoundPicked: { (url: URL?) in
                            if url == nil {
                                self.selectedSound = "Xylophone"
                                let key = "chat_\(contact?.obj.contactJid.lowercased() ?? "")_AlertSoundFile"
                                let filename = String(format: "alert2")
                                HelperTools.defaultsDB().setValue(filename, forKey: key)
                                HelperTools.defaultsDB().synchronize()
                            } else {
                                self.selectedSound = "Custom Sound"
                                let key = "chat_\(contact?.obj.contactJid.lowercased() ?? "")_AlertSoundFile"
                                HelperTools.defaultsDB().setValue("CustomizeSound", forKey: key)
                                HelperTools.defaultsDB().synchronize()
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
               ForEach(Array(sounds.enumerated()), id: \.element) { index, sound in
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
                       let key = "chat_\(contact?.obj.contactJid ?? "")_AlertSoundFile"
                       let filename = String(format: "alert%ld", index)
                       HelperTools.defaultsDB().setValue(filename, forKey: key)
                       if index > 0 {
                           self.playSound(index: index)
                       } else {
                           self.audioPlayer?.stop()
                       }
                   }
               }
           }
       }

    func playSound(index: Int) {
        let filename = "alert\(index)"
        guard let url = Bundle.main.url(forResource: filename, withExtension: "aif", subdirectory: "AlertSounds") else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            DDLogDebug("Error playing Sound \(error)")
        }
    }
}

