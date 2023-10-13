//
//  ImageViewer.swift
//  Monal
//
//  Created by Friedrich Altheide on 07.10.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

struct ImageViewer: View {
    var delegate: SheetDismisserProtocol
    let image: UIImage
    let filename: String
    let animatedImageData: Data?
    @State private var controlsVisible = false
    
//     var body: some View {
//         if let animatedImageData = animatedImageData {
//             GIFViewer(data:Binding(get: { animatedImageData }, set: { _ in }))
//             .frame(width: 100, height: 200, alignment: .center)
//         }
//     }
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.background
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                ZoomableContainer(maxScale:8.0, doubleTapScale:4.0) {
                    if let animatedImageData = animatedImageData {
                        GIFViewer(data:Binding(get: { animatedImageData }, set: { _ in }))
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
                                Text(filename).foregroundColor(.primary)
                                Spacer()
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
