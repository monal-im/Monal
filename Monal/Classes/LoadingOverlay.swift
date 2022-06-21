//
//  LoadingOverlay.swift
//  Monal
//
//  Created by Jan on 21.06.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI

struct WelcomeLogInOverlay<Content: View>: View {
    let underlyingView: Content
    @State var headline: String
    @State var description: String

    var body: some View {
        ZStack {
            underlyingView
                .disabled(true)
                .blur(radius: 3)
            VStack{
                Text(self.headline).font(.headline)
                Text(self.description).font(.footnote)
                ProgressView()
            }
            .frame(width: 200, height: 100)
            .background(Color.secondary.colorInvert())
            .cornerRadius(20)
        }
    }
}

struct WelcomeLogInOverlay_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        WelcomeLogInOverlay<WelcomeLogIn>(underlyingView: WelcomeLogIn(delegate: delegate), headline: "Loading...", description: "More info?")
    }
}
