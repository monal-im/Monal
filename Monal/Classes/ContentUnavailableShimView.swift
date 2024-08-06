//
//  ContentNotAvailableView.swift
//  Monal
//
//  Created by Matthew Fennell <matthew@fennell.dev> on 05/08/2024.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import SwiftUI

struct ContentUnavailableShimView: View {
    private var reason: String
    private var systemImage: String
    private var description: Text

    init(_ reason: String, systemImage: String, description: Text) {
        self.reason = reason
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        if #available(iOS 17, *) {
            ContentUnavailableView(reason, systemImage: systemImage, description: description)
        } else {
            VStack {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .font(.largeTitle)
                    .padding(.bottom, 4)
                Text(reason)
                    .fontWeight(.bold)
                    .font(.title3)
                description
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

#Preview {
    ContentUnavailableShimView("Cannot Display", systemImage: "iphone.homebutton.slash", description: Text("Cannot display for this reason."))
}
