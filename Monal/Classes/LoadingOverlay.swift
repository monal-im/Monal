//
//  LoadingOverlay.swift
//  Monal
//
//  Created by Jan on 21.06.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI

struct WelcomeLogInOverlayInPlace: View {
    var headline: String
    var description: String

    var body: some View {
        VStack{
            Text(self.headline).font(.headline)
            Text(self.description).font(.footnote)
            ProgressView()
        }
        .frame(width: 250, height: 100)
        .background(Color.secondary.colorInvert())
        .cornerRadius(20)
    }
}

struct WelcomeLogInOverlay<Content: View>: View {
    let underlyingView: Content
    @State var headline: String
    @State var description: String

    var body: some View {
        ZStack {
            underlyingView
                .disabled(true)
                .blur(radius: 3)
            WelcomeLogInOverlayInPlace(headline: self.headline, description: self.description)
        }
    }
}

struct WelcomeLogInOverlay_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        WelcomeLogInOverlay<WelcomeLogIn>(underlyingView: WelcomeLogIn(delegate: delegate, hasParentNavigationView: false), headline: "Loading...", description: "More info?")
    }
}
