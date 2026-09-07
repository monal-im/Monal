//
//  ChatPlaceholder.swift
//  Monal
//
//  Created by Thilo Molitor on 30.11.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

struct ChatPlaceholder: View {
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        ZStack {
            if colorScheme == .dark {
                Color.black
            } else {
                Color.white
            }
            Image(colorScheme == .dark ? .parkWhiteBlack : .parkColors)
                .resizable()
                .scaledToFill()
        }
    }
}

struct ChatPlaceholder_Previews: PreviewProvider {
    static var previews: some View {
        ChatPlaceholder()
    }
}
