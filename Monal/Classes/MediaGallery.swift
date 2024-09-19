//
//  MediaGallery.swift
//  Monal
//
//  Created by Vaidik on 03.08.24.
//  Copyright © 2021 Monal.im. All rights reserved.

import SwiftUI
import AVKit
import AVFoundation

struct MediaGalleryView: View {
    @State private var mediaItems: [[String: Any]] = []
    let contact: String
    let accountID: NSNumber
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                ForEach(mediaItems.indices, id: \.self) { index in
                    NavigationLink(destination: LazyClosureView {
                        MediaItemSwipeView(currentItem: mediaItems[index], allItems: mediaItems)
                    }) {
                        MediaItemView(fileInfo: mediaItems[index])
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Media Gallery")
        .onAppear {
            fetchDownloadedMediaItems()
        }
    }
    
    private func fetchDownloadedMediaItems() {
        if let attachments = DataLayer.sharedInstance().allAttachments(fromContact: contact, forAccount: accountID) as? [[String: Any]] {
            mediaItems = attachments.filter { fileInfo in
                if let mimeType = fileInfo["mimeType"] as? String,
                   !((fileInfo["needsDownloading"] as? NSNumber)?.boolValue ?? true) &&
                    (mimeType.starts(with: "image/") || mimeType.starts(with: "video/")) {
                    return true
                }
                return false
            }
        }
    }
}

class MediaItem: Identifiable, ObservableObject {
    let id = UUID()
    let fileInfo: [String: Any]
    @Published var thumbnail: UIImage?

    init(fileInfo: [String: Any]) {
        self.fileInfo = fileInfo
        self.thumbnail = nil
        Task {
            await generateThumbnail()
        }
    }

    @MainActor
    func generateThumbnail() async {
        guard let cacheFile = fileInfo["cacheFile"] as? String, let mimeType = fileInfo["mimeType"] as? String else {
            DDLogError("Failed to get cacheFile or mimeType for: \(fileInfo)")
            self.thumbnail = UIImage(systemName: "exclamationmark.triangle")
            return
        }

        if mimeType.starts(with: "image/") {
            if let image = UIImage(contentsOfFile: cacheFile)?.thumbnail(size: CGSize(width: 100, height: 100)) {
                self.thumbnail = image
            } else {
                DDLogError("Failed to generate image thumbnail for: \(fileInfo)")
                self.thumbnail = UIImage(systemName: "photo")
            }
            return
        } else if mimeType.starts(with: "video/") {
            if let thumbnail = await videoPreview(for: fileInfo, in: 1) {
                self.thumbnail = thumbnail.thumbnail(size: CGSize(width: 100, height: 100))
            } else {
                DDLogError("Failed to generate video thumbnail for: \(fileInfo)")
                self.thumbnail = UIImage(systemName: "video")
            }
            return
        }

        DDLogError("Unsupported mime type: \(mimeType)")
        self.thumbnail = UIImage(systemName: "doc")
    }

    func videoPreview(for fileInfo: [String: Any], in seconds: Double) async -> UIImage? {
        let moviePath = URL(fileURLWithPath: fileInfo["cacheFile"] as! String)
        DDLogInfo("Trying to generate thumbnail for: \(String(describing:fileInfo))")

        guard #available(iOS 17.0, macCatalyst 17.0, *) else {
            DDLogDebug("Generating thumbnail with symlink method...")

            //this won't work if we don't have a file extension in our file info (happens if the file was sent/received without an extension)
            //--> just bail out for now (if that happens frequently, we probably should instead use
            //    stringByAppendingPathExtensionForType with UTType.typeWithMIMEType as argument)
            guard let fileExtension = fileInfo["fileExtension"] as? String else {
                DDLogInfo("Could not get file extension for file, not generating thumbnail...")
                return nil
            }

            //create a symlink for our file having the proper file extension
            //the "tmp." prefix will make sure this gets garbage collected by doStartupCleanup in MLFiletransfer
            let symlinkPath = HelperTools.getContainerURL(forPathComponents:["documentCache", "tmp.player_symlink.\(moviePath.lastPathComponent).\(fileExtension)"])
            do {
                if FileManager.default.fileExists(atPath: symlinkPath.path) {
                    try FileManager.default.removeItem(at: symlinkPath)
                }
                try FileManager.default.createSymbolicLink(at: symlinkPath, withDestinationURL: moviePath)
            } catch {
                DDLogError("Error creating symlink: \(error)")
                return nil
            }
            defer {
                if FileManager.default.fileExists(atPath: symlinkPath.path) {
                    try? FileManager.default.removeItem(at: symlinkPath)
                }
            }

            //now generate the preview using the symlink
            let asset = AVURLAsset(url: symlinkPath)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            do {
                let (cgImage, _) = try await imageGenerator.image(at: time)
                return UIImage(cgImage: cgImage)
            } catch {
                DDLogError("Error generating thumbnail: \(error)")
                return nil
            }
        }

        //generate a thumbnail using the modern ios 17 method to attach a mime type to an AVURLAsset
        let asset = AVURLAsset(url: moviePath, options:[AVURLAssetOverrideMIMETypeKey: fileInfo["mimeType"] as! String])
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        do {
            let (cgImage, _) = try await imageGenerator.image(at: time)
            return UIImage(cgImage: cgImage)
        } catch {
            DDLogError("Error generating thumbnail: \(error)")
            return nil
        }
    }
}

struct MediaItemView: View {
    @StateObject private var item: MediaItem

    init(fileInfo: [String: Any]) {
        _item = StateObject(wrappedValue: MediaItem(fileInfo: fileInfo))
    }

    var body: some View {
        ZStack {
            Group {
                if let thumbnail = item.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .frame(width: 50, height: 50)
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray, lineWidth: 1))
            
            // Add play icon overlay for video files
            if let mimeType = item.fileInfo["mimeType"] as? String, mimeType.starts(with: "video/") {
                Image(systemName: "play.circle.fill")
                    .resizable()
                    .frame(width: 30, height: 30)
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
    }
}

struct MediaItemDetailView: View {
    @StateObject private var item: MediaItem
    @StateObject private var dismisser = SheetDismisserProtocol()
    
    init(fileInfo: [String: Any]) {
        _item = StateObject(wrappedValue: MediaItem(fileInfo: fileInfo))
    }

    var body: some View {
        ImageViewerWrapper(info: item.fileInfo as [String: AnyObject], dismisser: dismisser)
            .onAppear {
                if let hostingController = UIApplication.shared.windows.first?.rootViewController?.presentedViewController as? UIHostingController<AnyView> {
                    dismisser.host = hostingController
                }
            }
    }
}

struct MediaItemSwipeView: View {
    @State private var currentIndex: Int
    let allItems: [[String: Any]]

    init(currentItem: [String: Any], allItems: [[String: Any]]) {
        let index = allItems.firstIndex { item in
            // Compare using 'cacheFile'
            if let currentPath = currentItem["cacheFile"] as? String,
               let itemPath = item["cacheFile"] as? String {
                return currentPath == itemPath
            }
            return false
        } ?? 0
        
        self._currentIndex = State(initialValue: index)
        self.allItems = allItems
    }

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(allItems.indices, id: \.self) { index in
                MediaItemDetailView(fileInfo: allItems[index])
                    .tag(index)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .animation(.easeInOut, value: currentIndex)
        .ignoresSafeArea()
        .navigationBarHidden(true)
        .statusBar(hidden: true)
    }
}

struct ImageViewerWrapper: View {
    let info: [String: AnyObject]
    let dismisser: SheetDismisserProtocol
    
    var body: some View {
        Group {
            if let _ = info["mimeType"] as? String {
                try? ImageViewer(delegate: dismisser, info: info)
            } else {
                Text("Invalid file data")
            }
        }
    }
}


