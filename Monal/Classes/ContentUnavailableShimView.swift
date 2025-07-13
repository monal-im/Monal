//
//  ContentUnavailableShimView.swift
//  Monal
//
//  Created by Matthew Fennell <matthew@fennell.dev> on 05/08/2024.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

struct ContentUnavailableShimView: View {
    private var reason: LocalizedStringKey
    private var image: String?
    private var systemImage: String?
    private var description: Text

    init(_ reason: LocalizedStringKey, image: String, description: Text) {
        self.image = image
        self.reason = reason
        self.description = description
    }
    
    init(_ reason: LocalizedStringKey, systemImage: String, description: Text) {
        self.systemImage = systemImage
        self.reason = reason
        self.description = description
    }

    var body: some View {
        //this won't show "bigger" images and is rather useless
//         if #available(iOS 17, *) {
//             if let systemImage = systemImage {
//                 ContentUnavailableView(reason, systemImage: systemImage, description: description)
//             } else if let image = image {
//                 ContentUnavailableView(reason, image: image, description: description)
//             }
//         } else {
        VStack(alignment: .center) {
            HStack {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64.0, height: 64.0)
                        .foregroundStyle(.secondary)
                        .font(.largeTitle)
                        .padding(.bottom, 32)
                } else if let image = image {
                    Image(decorative: image)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .font(.largeTitle)
                        .padding(.bottom, 32)
                }
            }
            Text(reason)
                .fontWeight(.bold)
                .font(.title3)
            description
                .foregroundStyle(.secondary)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)
        }
        .applyClosure {view in
            if #available(iOS 17, *) {
                view.containerRelativeFrame(.horizontal) { size, axis in
                    size * 0.8
                }
            } else {
                HStack {
                    Spacer().frame(width: 32)
                    view
                    Spacer().frame(width: 32)
                }
            }
        }
    }
}

extension ContentUnavailableShimView {
    static var search: ContentUnavailableShimView = ContentUnavailableShimView("No Results", systemImage: "magnifyingglass", description: Text("Check the spelling or try a new search."))
    static func search(text: String) -> ContentUnavailableShimView {
        return ContentUnavailableShimView("No Results for \"\(text)\"", systemImage: "magnifyingglass", description: Text("Check the spelling or try a new search."))
    }
}

#Preview {
    ContentUnavailableShimView("Cannot Display", systemImage: "iphone.homebutton.slash", description: Text("Cannot display for this reason."))
}
