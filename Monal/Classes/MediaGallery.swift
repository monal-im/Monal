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

struct MediaItemView: View {
    @StateObject private var fileInfo: ObservableKVOWrapper<MLFiletransferInfo>

    init(fileInfo: MLFiletransferInfo) {
        _fileInfo = StateObject(wrappedValue: ObservableKVOWrapper(fileInfo))
    }

    var body: some View {
        ZStack {
            Group {
                if (fileInfo.thumbnailURL as URL?) != nil {
                    AsyncImage(url: fileInfo.thumbnailURL) { image in
                        image
                            .resizable()
                            //.scaledToFit()        //leaves empty room around image if not having a square format
                            .scaledToFill()         //this is what the ios gallery app uses (will crop the edges of that preview)
                    } placeholder: { //placeholder while the thumbnail is being loaded from disk
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                } else { //placeholder if the thumbnailURL is nil, for example while the thumbnail is being generated
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                }
            }
            .frame(width: 100, height: 100, alignment: .center)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray, lineWidth: 1))
            
            // Add play icon overlay for video files
            if fileInfo.isVideo {
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
    @StateObject private var fileInfo: ObservableKVOWrapper<MLFiletransferInfo>
    @StateObject private var dismisser = SheetDismisserProtocol()
    
    init(fileInfo: MLFiletransferInfo) {
        _fileInfo = StateObject(wrappedValue: ObservableKVOWrapper(fileInfo))
    }

    var body: some View {
        ImageViewerWrapper(info: fileInfo, dismisser: dismisser)
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
            // Compare using 'cacheFilePath'
            if let currentPath = currentItem.cacheFilePath,
               let itemPath = item.cacheFilePath {
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
    @ObservedObject var info: ObservableKVOWrapper<MLFiletransferInfo>
    let dismisser: SheetDismisserProtocol
    
    var body: some View {
        Group {
            if info.downloadState as DownloadState.RawValue == DownloadState.complete.rawValue {
                try? ImageViewer(delegate: dismisser, info: info)
            } else {
                Text("Invalid file data")
            }
        }
    }
}
