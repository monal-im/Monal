//
//  ImageViewer.swift
//  Monal
//
//  Created by Friedrich Altheide on 07.10.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

import UniformTypeIdentifiers
import SVGView
import AVKit

struct GifRepresentation: Transferable {
    let getData: () -> Data
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .gif) { item in
            { () -> Data in
                return item.getData()
            }()
        }
    }
}

struct JpegRepresentation: Transferable {
    let getData: () -> Data
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { item in
            { () -> Data in
                return item.getData()
            }()
        }
    }
}

struct SVGRepresentation: Transferable {
    let getData: () -> Data
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .svg) { item in
            { () -> Data in
                return item.getData()
            }()
        }
    }
}

struct ImageViewer: View {
    var delegate: SheetDismisserProtocol
    let info: [String:AnyObject]
    @State private var previewImage: UIImage?
    @State private var controlsVisible = false
    @StateObject private var customPlayer = CustomAVPlayer()
    @State private var isPlayerReady = false

    init(delegate: SheetDismisserProtocol, info: [String:AnyObject]) throws {
        self.delegate = delegate
        self.info = info
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.background
                .ignoresSafeArea()
            
            if (info["mimeType"] as! String).hasPrefix("image/svg") {
                VStack {
                    ZoomableContainer(maxScale:8.0, doubleTapScale:4.0) {
                        SVGView(contentsOf: URL(fileURLWithPath:info["cacheFile"] as! String))
                    }
                }
            } else if (info["mimeType"] as! String).hasPrefix("image/") {
                if let image = UIImage(contentsOfFile:info["cacheFile"] as! String) {
                    VStack {
                        ZoomableContainer(maxScale:8.0, doubleTapScale:4.0) {
                            if (info["mimeType"] as! String).hasPrefix("image/gif") {
                                GIFViewer(data:Binding(get: { try! NSData(contentsOfFile:info["cacheFile"] as! String) as Data }, set: { _ in }))
                                    .scaledToFit()
                            } else {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                            }
                        }
                    }
                } else {
                    InvalidFileView()
                }
            } else if (info["mimeType"] as! String).hasPrefix("video/") {
                if isPlayerReady, let playerViewController = customPlayer.playerViewController {
                    ZoomableContainer(maxScale:8.0, doubleTapScale:4.0) {
                        AVPlayerControllerRepresentable(playerViewController: playerViewController)
                    }
                } else {
                    ProgressView()
                }
            } else {
                InvalidFileView()
            }
            
            if controlsVisible {
                ControlsOverlay(info: info, previewImage: $previewImage, dismiss: {
                                   self.delegate.dismiss()
                               })
            }
        }.onTapGesture(count: 1) {
            controlsVisible.toggle()
        }.task {
            await loadPreviewAndConfigurePlayer()
        }
    }
    
    private func loadPreviewAndConfigurePlayer() async {
        if (info["mimeType"] as! String).hasPrefix("image/svg") {
            previewImage = await HelperTools.renderUIImage(fromSVGURL:URL(fileURLWithPath:info["cacheFile"] as! String)).toGuarantee().asyncOnMainActor()
        } else if (info["mimeType"] as! String).hasPrefix("image/") {
            previewImage = UIImage(contentsOfFile:info["cacheFile"] as! String)
        } else if (info["mimeType"] as! String).hasPrefix("video/") {
            if let filePath = info["cacheFile"] as? String,
               let mimeType = info["mimeType"] as? String {
                customPlayer.configurePlayer(filePath: filePath, mimeType: mimeType)
                isPlayerReady = true
            }
        }
    }
}

class CustomAVPlayer: ObservableObject {
    @Published var player: AVPlayer?
    @Published var playerViewController: AVPlayerViewController?
    
    func configurePlayer(filePath: String, mimeType: String) {
        // Clear existing player
        player = nil
        playerViewController = nil
        
        // Create URL
        let videoFileUrl = URL(fileURLWithPath: filePath)
        
        // Create asset with MIME type
        let videoAsset = AVURLAsset(url: videoFileUrl, options: [
            "AVURLAssetOutOfBandMIMETypeKey": mimeType
        ])
        
        // Create player and player view controller
        let playerItem = AVPlayerItem(asset: videoAsset)
        player = AVPlayer(playerItem: playerItem)
        playerViewController = AVPlayerViewController()
        playerViewController?.player = player
        
        DDLogDebug("Created AVPlayer(\(mimeType)): \(String(describing: player))")
    }
}

struct AVPlayerControllerRepresentable: UIViewControllerRepresentable {
    let playerViewController: AVPlayerViewController
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        return playerViewController
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

struct InvalidFileView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Invalid file!")
            Spacer().frame(height: 24)
            Image(systemName: "xmark.square.fill")
                .resizable()
                .frame(width: 128.0, height: 128.0)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
            Spacer()
        }
    }
}

struct ControlsOverlay: View {
    let info: [String: AnyObject]
    @Binding var previewImage: UIImage?
    let dismiss: () -> Void
    
    var body: some View {
        VStack {
            Color.background
                .ignoresSafeArea()
                .overlay(
                    HStack {
                        Spacer().frame(width: 20)
                        Text(info["filename"] as! String).foregroundColor(.primary)
                        Spacer()
                        
                        if let image = previewImage {
                            if (info["mimeType"] as! String).hasPrefix("image/svg") {
                                ShareLink(
                                    item: SVGRepresentation(getData: {
                                        try! NSData(contentsOfFile: info["cacheFile"] as! String) as Data
                                    }), preview: SharePreview("Share image", image: Image(uiImage: image))
                                )
                                .labelStyle(.iconOnly)
                                .foregroundColor(.primary)
                            } else if (info["mimeType"] as! String).hasPrefix("image/gif") {
                                ShareLink(
                                    item: GifRepresentation(getData: {
                                        try! NSData(contentsOfFile: info["cacheFile"] as! String) as Data
                                    }), preview: SharePreview("Share image", image: Image(uiImage: image))
                                )
                                .labelStyle(.iconOnly)
                                .foregroundColor(.primary)
                            } else if (info["mimeType"] as! String).hasPrefix("video/") {
                                if let fileURL = URL(string: info["cacheFile"] as! String) {
                                    let mediaItem = MediaItem(fileInfo: info)
                                    ShareLink(item: fileURL, preview: SharePreview("Share video", image: Image(uiImage: mediaItem.thumbnail ?? UIImage(systemName: "video")!)))
                                        .labelStyle(.iconOnly)
                                        .foregroundColor(.primary)
                                }
                            } else {
                                ShareLink(
                                    item: JpegRepresentation(getData: {
                                        try! NSData(contentsOfFile: info["cacheFile"] as! String) as Data
                                    }), preview: SharePreview("Share image", image: Image(uiImage: image))
                                )
                                .labelStyle(.iconOnly)
                                .foregroundColor(.primary)
                            }
                            Spacer().frame(width: 20)
                        }
                        
                        Button(action: dismiss, label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.primary)
                                .font(.system(size: UIFontMetrics.default.scaledValue(for: 24)))
                        })
                        Spacer().frame(width: 20)
                    }
                )
        }.frame(height: 80)
    }
}
