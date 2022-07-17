//
//  LoadingOverlay.swift
//  Monal
//
//  Created by Jan on 21.06.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI

struct LoadingOverlay: View {
    var headline: String
    var description: String
    var enabled: Bool = false

    var body: some View {
        if enabled == true {
            VStack {
                Text(self.headline).font(.headline)
                Text(self.description).font(.footnote)
                ProgressView()
            }
            .frame(width: 250, height: 100)
            .background(Color.secondary.colorInvert())
            .cornerRadius(20)
        }
    }
}

struct LoadingOverlay_Previews: PreviewProvider {
    static private var overlay = LoadingOverlay(headline: "Loading...", description: "More info?", enabled: true)
    static var previews: some View {
        ZStack {
            Form {
                Text("Entry 1")
                Text("Entry 2")
                Text("Entry 3")
            }
            .disabled(true)
            .blur(radius: 3) // <- disabled/blur are the recommended changes to the background
            overlay
        }
    }
}
