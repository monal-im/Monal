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
    @ObservedObject var settings: ContactSettings
    @State private var selectedSound: String
    @State private var playSounds: Bool
    @State private var audioPlayer: AVAudioPlayer?
    let sounds = ["System Sound", "Morse", "Xylophone", "Bloop", "Bing", "Pipa", "Water", "Forest", "Echo", "Area 51", "Wood", "Chirp", "Sonar"]

    init(settings: ContactSettings) {
        self.settings = settings
        _selectedSound = State(initialValue: UserDefaults.standard.string(forKey: settings.contactJid + "AlertSoundFile") ?? "System Sound")
        if UserDefaults.standard.object(forKey: settings.contactJid + "PlaySounds") == nil {
           _playSounds = State(initialValue: true)
        } else {
           _playSounds = State(initialValue: UserDefaults.standard.bool(forKey: settings.contactJid + "PlaySounds"))
        }
    }
    
    var body: some View {
        List {
            Section {
                Toggle(isOn: $playSounds) {
                    Text("Play Sounds")
                }
                .onChange(of: playSounds) { newValue in
                    let key = settings.contactJid + "PlaySounds"
                    UserDefaults.standard.set(newValue, forKey: key)
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
                    self.selectedSound = sounds[index]
                    let key = (settings.contactJid) + "AlertSoundFile"
                    if index > 0 {
                        self.playSound(index: index)
                        UserDefaults.standard.set(sounds[index], forKey: key)
                    } else {
                        UserDefaults.standard.removeObject(forKey: key)
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
            print("Error playing sound: \(error)")
        }
    }
}

class ContactSettings: ObservableObject {
    @Published var contactJid: String
    
    init(contactJid: String) {
        self.contactJid = contactJid
    }
}



@objc class SoundsSettingViewController: NSObject {
    @objc static func createSoundsSettingView(contactJid: String) -> UIViewController {
        let settings = ContactSettings(contactJid: contactJid)
        let SoundsSettingSwiftUIView = SoundsSettingView(settings: settings)
        let hostingController = UIHostingController(rootView: SoundsSettingSwiftUIView)
        return hostingController
    }
}
