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
    let accountNo: NSNumber
    
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
        if let attachments = DataLayer.sharedInstance().allAttachments(fromContact: contact, forAccount: accountNo) as? [[String: Any]] {
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
            if let image = UIImage(contentsOfFile: cacheFile) {
                self.thumbnail = image
            } else {
                DDLogError("Failed to generate image thumbnail for: \(fileInfo)")
                self.thumbnail = UIImage(systemName: "photo")
            }
            return
        } else if mimeType.starts(with: "video/") {
            if let thumbnail = await videoPreview(for:fileInfo) {
                self.thumbnail = thumbnail
            } else {
                DDLogError("Failed to generate video thumbnail for: \(fileInfo)")
                self.thumbnail = UIImage(systemName: "video")
            }
            return
        }

        DDLogError("Unsupported mime type: \(mimeType)")
        self.thumbnail = UIImage(systemName: "doc")
    }

    @MainActor
    func videoPreview(for fileInfo: [String: Any]) async -> UIImage? {
        let moviePath = URL(fileURLWithPath: fileInfo["cacheFile"] as! String)
        DDLogInfo("Trying to generate video thumbnail for: \(String(describing:fileInfo))")
        
        var payload: NSMutableDictionary = [:]
        HelperTools.addUploadItemPreview(forItem:moviePath, provider:nil, andPayload:payload) { newPayload in
            payload = newPayload ?? [:]
        }
        guard let image = payload["preview"] as? UIImage else {
            return try? await HelperTools.generateVideoThumbnail(
                fromFile:fileInfo["cacheFile"] as! String,
                havingMimeType:fileInfo["mimeType"] as! String,
                andFileExtension:fileInfo["fileExtension"] as? String
            ).toPromise().asyncOnMainActor()
        }
        return image
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
                        //.scaledToFit()        //leaves empty room around image if not having a square format
                        .scaledToFill()         //this is what the ios gallery app uses (will crop the edges of that preview)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                }
            }
            .frame(width: 100, height: 100, alignment: .center)
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
        .edgesIgnoringSafeArea(.all)
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


