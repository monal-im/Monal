//
//  SoundPickerView.swift
//  Monal
//
//  Created by 阿栋 on 3/7/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import SwiftUI
import UIKit
import AVFoundation

struct DocumentPicker: UIViewControllerRepresentable {
    var onPicked: (URL) -> Void
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate, UINavigationControllerDelegate {
        var parent: DocumentPicker

        init(_ documentPicker: DocumentPicker) {
            self.parent = documentPicker
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let pickedURL = urls.first else { return }
            parent.onPicked(pickedURL)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onDismiss()
        }
    }
}

struct SoundPickerView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var showDocumentPicker = false
    @State private var selectedAudioURL: URL?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioData: Data?

    let contact: ObservableKVOWrapper<MLContact>?
    let onSoundPicked: (URL?) -> Void
    let delegate: SheetDismisserProtocol
    

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("SELECT A SOUND TO PLAY WITH NOTIFICATIONS.")) {
                    Button(action: {
                        showDocumentPicker = true
                    }) {
                        HStack {
                            Text(selectedAudioURL != nil ? selectedAudioURL!.lastPathComponent : "Select sound file")
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedAudioURL != nil {
                                Button(action: {
                                    self.selectedAudioURL = nil
                                    self.audioPlayer?.stop()
                                    self.audioPlayer = nil
                                    MLSoundManager.sharedInstance().deleteSoundData(contact?.obj)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                Button(action: {
                                    playAudio(url: selectedAudioURL!)
                                }) {
                                    Image(systemName: "play.circle")
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                        }
                    }
                }
            }
            .navigationBarTitle("Sound Selection", displayMode: .inline)
            .navigationBarItems(trailing: Button("Save") {
                if let selectedURL = selectedAudioURL {
                    onSoundPicked(selectedURL)
                    MLSoundManager.sharedInstance().saveSoundData(for: self.contact?.obj, withSound: audioData!)
                    presentationMode.wrappedValue.dismiss()
                } else {
                    self.selectedAudioURL = nil
                    onSoundPicked(self.selectedAudioURL)
                    presentationMode.wrappedValue.dismiss()
                }
            })
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker(onPicked: { url in
                    selectedAudioURL = url
                    playAudio(url: url)
                    loadAudioData(from: url)
                    showDocumentPicker = false
                }, onDismiss: {
                    showDocumentPicker = false
                })
            }
            .onAppear {
                let soundURLString = MLSoundManager.sharedInstance().loadSoundURL(for: contact?.obj)
                if let soundURL = URL(string: soundURLString) {
                    selectedAudioURL = soundURL
                    loadAudioData(from: soundURL)
                }
            }
        }
    }

    func playAudio(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            DDLogDebug("Cannot play audio: \(error)")
        }
    }
    
    func loadAudioData(from url: URL) {
        do {
            audioData = try Data(contentsOf: url)
        } catch {
            DDLogDebug("Load audio data failure: \(error)")
        }
    }
}
