//
//  ImageViewer.swift
//  Monal
//
//  Created by Friedrich Altheide on 07.10.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

import UniformTypeIdentifiers
import SVGView

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

    init(delegate: SheetDismisserProtocol, info:[String:AnyObject]) throws {
        self.delegate = delegate
        self.info = info
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.background
                .edgesIgnoringSafeArea(.all)
            
            if (info["mimeType"] as! String).hasPrefix("image/svg") {
                VStack {
                    ZoomableContainer(maxScale:8.0, doubleTapScale:4.0) {
                        SVGView(contentsOf: URL(fileURLWithPath:info["cacheFile"] as! String))
                    }
                }
            } else if let image = UIImage(contentsOfFile:info["cacheFile"] as! String) {
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
                VStack {
                    Spacer()
                    Text("Invalid image file!")
                    Spacer().frame(height: 24)
                    Image(systemName: "xmark.square.fill")
                        .resizable()
                        .frame(width: 128.0, height: 128.0)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                    Spacer()
                }
            }
            
            if controlsVisible {
                VStack {
                    Color.background
                        .edgesIgnoringSafeArea(.all)
                        .overlay(
                            HStack {
                                Spacer().frame(width:20)
                                Text(info["filename"] as! String).foregroundColor(.primary)
                                Spacer()
                                
                                if (info["mimeType"] as! String).hasPrefix("image/svg"), let image = previewImage {
                                    ShareLink(
                                        item: SVGRepresentation(getData: {
                                            try! NSData(contentsOfFile:info["cacheFile"] as! String) as Data
                                        }), preview: SharePreview("Share image", image: Image(uiImage: image))
                                    )
                                        .labelStyle(.iconOnly)
                                        .foregroundColor(.primary)
                                    Spacer().frame(width:20)
                                } else if let image = previewImage {
                                    if (info["mimeType"] as! String).hasPrefix("image/gif") {
                                        ShareLink(
                                            item: GifRepresentation(getData: {
                                                try! NSData(contentsOfFile:info["cacheFile"] as! String) as Data
                                            }), preview: SharePreview("Share image", image: Image(uiImage: image))
                                        )
                                            .labelStyle(.iconOnly)
                                            .foregroundColor(.primary)
                                    } else {
                                        // even share non-gif images as Data instead of Image, because this leads to fewer crashes of other apps
                                        // see https://medium.com/@timonus/reduce-share-extension-crashes-from-your-app-with-this-one-weird-trick-6b86211bb175
                                        ShareLink(
                                            item: JpegRepresentation(getData: {
                                                try! NSData(contentsOfFile:info["cacheFile"] as! String) as Data
                                            }), preview: SharePreview("Share image", image: Image(uiImage: image))
                                        )
                                            .labelStyle(.iconOnly)
                                            .foregroundColor(.primary)
                                    }
                                    Spacer().frame(width:20)
                                }
                                
                                Button(action: {
                                    self.delegate.dismiss()
                                }, label: {
                                    Image(systemName: "xmark")
                                        .foregroundColor(.primary)
                                        .font(.system(size: UIFontMetrics.default.scaledValue(for: 24)))
                                })
                                Spacer().frame(width:20)
                            }
                        )
                }.frame(height: 80)
            }
        }.onTapGesture(count: 1) {
            controlsVisible = !controlsVisible
        }.task {
            if (info["mimeType"] as! String).hasPrefix("image/svg") {
                previewImage = await HelperTools.renderUIImage(fromSVGURL:URL(fileURLWithPath:info["cacheFile"] as! String)).toGuarantee().asyncOnMainActor()
            } else {
                previewImage = UIImage(contentsOfFile:info["cacheFile"] as! String)
            }
        }
    }
}

// #Preview {
    // ImageViewer()
// }
