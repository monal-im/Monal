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

// 用于选择文档的UIViewControllerRepresentable
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

    let onSoundPicked: (URL?) -> Void

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
                                    MLSoundManager.sharedInstance().deleteSoundData()
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
                    MLSoundManager.sharedInstance().saveSound(audioData)
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
                let soundURLString = MLSoundManager.sharedInstance().loadSoundURL()
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
            print("Cannot play audio: \(error)")
        }
    }
    
    func loadAudioData(from url: URL) {
        do {
            audioData = try Data(contentsOf: url)
        } catch {
            print("加载音频数据失败: \(error)")
        }
    }
}




//struct SoundPickerView: View {
//    @Environment(\.presentationMode) var presentationMode
//    @State private var showDocumentPicker = false
//    @State private var selectedAudioURL: URL?
//    @State private var audioPlayer: AVAudioPlayer?
//    @State private var audioData: Data? // 用于存储音频文件的数据
//
//    let onSoundPicked: (URL) -> Void
//
//    var body: some View {
//        VStack {
//            if let audioURL = selectedAudioURL {
//                // 展示选中的音频文件名称
//                Text(audioURL.lastPathComponent)
//                    .padding()
//                    .onTapGesture {
//                        playAudio(url: audioURL)
//                    }
//                
//                // 如果有音频数据，可以在这里添加对应的 UI 组件来展示数据
//                // 例如，展示音频文件的大小
//                if let audioData = audioData {
//                    Text("文件大小: \(audioData.count) bytes")
//                        .padding()
//                }
//
//                // 确认按钮
//                Button("确认") {
//                    if let url = selectedAudioURL {
//                        onSoundPicked(url)
//                        presentationMode.wrappedValue.dismiss()
//                        MLSoundManager.sharedInstance().saveSound(audioData)
//                    }
//                }
//                .padding()
//            } else {
//                Button("选择声音文件") {
//                    showDocumentPicker = true
//                }
//                .padding()
//            }
//        }
//        .navigationBarTitle("选择声音", displayMode: .inline)
//        .sheet(isPresented: $showDocumentPicker) {
//            DocumentPicker(onPicked: { url in
//                selectedAudioURL = url
//                loadAudioData(from: url)
//                showDocumentPicker = false
//            }, onDismiss: {
//                showDocumentPicker = false
//            })
//        }
//    }
//
//    func playAudio(url: URL) {
//        do {
//            audioPlayer = try AVAudioPlayer(contentsOf: url)
//            audioPlayer?.play()
//        } catch {
//            print("播放音频失败: \(error)")
//        }
//    }
//
//    // 加载音频数据的方法
//    func loadAudioData(from url: URL) {
//        do {
//            audioData = try Data(contentsOf: url)
//        } catch {
//            print("加载音频数据失败: \(error)")
//        }
//    }
//}
