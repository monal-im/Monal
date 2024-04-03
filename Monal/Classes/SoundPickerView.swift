//
//  SoundPickerView.swift
//  Monal
//
//  Created by 阿栋 on 3/29/24.
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
    @State private var selectedAudioFileName: String?

    
    let contact: ObservableKVOWrapper<MLContact>?
    let receiverJID: String
    let senderJID: String
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
                            let custom = MLSoundManager.sharedInstance().getIsCustomSound(forAccountId: receiverJID, buddyId: senderJID)
                            let soundName = MLSoundManager.sharedInstance().getSoundName(forSenderJID: senderJID, andReceiverJID: receiverJID)
                            let textContent = (custom == 1 && audioData != nil && selectedAudioFileName == nil) ? soundName : (selectedAudioFileName ?? "Select sound file")
                            Text(textContent)
                                .foregroundColor(.primary)
                            Spacer()
                            if audioData != nil {
                                Button(action: {
                                    self.selectedAudioURL = nil
                                    self.audioPlayer?.stop()
                                    self.audioPlayer = nil
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                Button(action: {
                                    playAudioWithData(data: audioData!)
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
                    presentationMode.wrappedValue.dismiss()
                } else {
                    self.selectedAudioURL = nil
                    onSoundPicked(self.selectedAudioURL)
                    presentationMode.wrappedValue.dismiss()
                }
            })
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker(onPicked: { url in
                    do {
                        selectedAudioURL = url
                        
                        let data = try Data(contentsOf: url)
                        self.audioData = data
                        self.selectedAudioFileName = url.lastPathComponent
                        self.playAudioWithData(data: data)
                    } catch {
                        DDLogError("Unable to load audio data: \(error)")
                    }
                    self.showDocumentPicker = false
                }, onDismiss: {
                    self.showDocumentPicker = false
                })
            }
            .onAppear {
                let custom = MLSoundManager.sharedInstance().getIsCustomSound(forAccountId: receiverJID, buddyId: senderJID)
                if custom == 1 {
                    let data = MLSoundManager.sharedInstance().getSoundData(forSenderJID: senderJID, andReceiverJID: receiverJID)
                    self.audioData = data
                }
            }
        }
    }

    func playAudioWithData(data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            DDLogError("Cannot play audio: \(error)")
        }
    }
}
