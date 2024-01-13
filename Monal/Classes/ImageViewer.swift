//
//  ImageViewer.swift
//  Monal
//
//  Created by Friedrich Altheide on 07.10.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

import UniformTypeIdentifiers

@available(iOS 16, *)
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

@available(iOS 16, *)
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

struct ImageViewer: View {
    var delegate: SheetDismisserProtocol
    let info: [String:AnyObject]
    @State private var controlsVisible = false
    
    init(delegate: SheetDismisserProtocol, info:[String:AnyObject]) throws {
        self.delegate = delegate
        self.info = info
        if #available(iOS 16, *) {
            let mimeType = UTType(exportedAs:info["mimeType"] as! String, conformingTo:.data)
            DDLogError("mimeType = \(String(describing:mimeType))")
        }
    }
    
//     var body: some View {
//         if (info["mimeType"] as! String).hasPrefix("image/gif") {
//             GIFViewer(data:Binding(get: { try NSData(contentsOfFile:info["cacheFile"] as! String) as Data }, set: { _ in }))
//             .frame(width: 100, height: 200, alignment: .center)
//         }
//     }
    
    var body: some View {
        let image = UIImage(contentsOfFile:info["cacheFile"] as! String)!
        
        ZStack(alignment: .top) {
            Color.background
                .edgesIgnoringSafeArea(.all)
            
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
            
            if controlsVisible {
                VStack {
                    Color.background
                        .edgesIgnoringSafeArea(.all)
                        .overlay(
                            HStack {
                                Spacer().frame(width:20)
                                Text(info["filename"] as! String).foregroundColor(.primary)
                                Spacer()
                                if #available(iOS 16, *) {
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
        }
    }
}

// #Preview {
    // ImageViewer()
// }
