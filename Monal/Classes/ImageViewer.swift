//
//  ImageViewer.swift
//  Monal
//
//  Created by Friedrich Altheide on 07.10.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

import SwiftUI

struct ImageViewer: View {
    var delegate: SheetDismisserProtocol
    let image: UIImage

    @State private var imageScale: CGFloat = 1.0

    var body: some View {
        Image(uiImage: image)
              .resizable()
              .scaledToFit()
              .scaleEffect(imageScale)
              .gesture(
                MagnificationGesture()
                  .onChanged { value in
                    self.imageScale = value.magnitude
                  }
              )
    }
}

// #Preview {
    // ImageViewer()
// }
