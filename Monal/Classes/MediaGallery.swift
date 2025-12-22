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
    @State private var mediaItems: [MLFiletransferInfo] = []
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
        .navigationTitle(Text("Shared Media"))
        .onAppear {
            fetchDownloadedMediaItems()
        }
    }
    
    private func fetchDownloadedMediaItems() {
        if let attachments = DataLayer.sharedInstance().allAttachments(fromContact: contact, forAccount: accountID) as? [MLFiletransferInfo] {
            mediaItems = attachments.filter { fileInfo in
                if fileInfo.downloadState == .complete, (fileInfo.isImage || fileInfo.isVideo) {
                    return true
                }
                return false
            }
        }
    }
}

class MediaItem: Identifiable, ObservableObject {
    let id = UUID()
    let fileInfo: MLFiletransferInfo
    @Published var thumbnail: UIImage?

    init(fileInfo: MLFiletransferInfo) {
        self.fileInfo = fileInfo
        self.thumbnail = nil
        Task { @MainActor in
            await generateThumbnail()
        }
    }

    @MainActor
    func generateThumbnail() async {
        guard let cacheFile = fileInfo.cacheFile else {
            DDLogError("Failed to get cacheFile for: \(fileInfo)")
            self.thumbnail = UIImage(systemName: "exclamationmark.triangle")
            return
        }

        if fileInfo.isImage {
            if let image = UIImage(contentsOfFile: cacheFile) {
                self.thumbnail = image
            } else {
                DDLogError("Failed to generate image thumbnail for: \(fileInfo)")
                self.thumbnail = UIImage(systemName: "photo")
            }
            return
        } else if fileInfo.isVideo {
            if let thumbnail = await videoPreview(for:fileInfo) {
                self.thumbnail = thumbnail
            } else {
                DDLogError("Failed to generate video thumbnail for: \(fileInfo)")
                self.thumbnail = UIImage(systemName: "video")
            }
            return
        }

        DDLogError("Unsupported mime type: \(fileInfo.mimeType ?? "(unknown)")")
        self.thumbnail = UIImage(systemName: "doc")
    }

    @MainActor
    func videoPreview(for fileInfo: MLFiletransferInfo) async -> UIImage? {
        let moviePath = URL(fileURLWithPath: fileInfo.cacheFile!)
        DDLogInfo("Trying to generate video thumbnail for: \(String(describing:fileInfo))")
        
        let payload: NSDictionary? = try? await HelperTools.addUploadItemPreview(
            forItem:moviePath,
            provider:nil,
            andPayload:[:]
        ).toTypedPromise().asyncOnMainActor()
        guard let image = payload?["preview"] as? UIImage else {
            return try? await HelperTools.generateVideoThumbnail(
                fromFile:fileInfo.cacheFile!,
                havingMimeType:fileInfo.mimeType! ,
                andFileExtension:fileInfo.fileExtension
            ).toTypedPromise().asyncOnMainActor()
        }
        return image
    }
}

struct MediaItemView: View {
    @StateObject private var item: MediaItem

    init(fileInfo: MLFiletransferInfo) {
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
            if item.fileInfo.isVideo {
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
    
    init(fileInfo: MLFiletransferInfo) {
        _item = StateObject(wrappedValue: MediaItem(fileInfo: fileInfo))
    }

    var body: some View {
        ImageViewerWrapper(info: item.fileInfo as MLFiletransferInfo, dismisser: dismisser)
            .onAppear {
                let appDelegate = UIApplication.shared.delegate as! MonalAppDelegate
                if let hostingController = appDelegate.getTopViewController() as? UIHostingController<AnyView> {
                    dismisser.host = hostingController
                }
            }
    }
}

struct MediaItemSwipeView: View {
    @State private var currentIndex: Int
    let allItems: [MLFiletransferInfo]

    init(currentItem: MLFiletransferInfo, allItems: [MLFiletransferInfo]) {
        let index = allItems.firstIndex { item in
            // Compare using 'cacheFile'
            if let currentPath = currentItem.cacheFile,
               let itemPath = item.cacheFile {
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
    let info: MLFiletransferInfo
    let dismisser: SheetDismisserProtocol
    
    var body: some View {
        Group {
            if info.downloadState == DownloadState.complete {
                try? ImageViewer(delegate: dismisser, info: info)
            } else {
                Text("Invalid file data")
            }
        }
    }
}


