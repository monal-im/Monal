//
//  BoardingCards.swift
//  Monal
//
//  Created by Vaidik Dubey on 05/06/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import SwiftUI

class OnboardingState: ObservableObject {
    @defaultsDB("hasCompletedOnboarding")
    var hasCompletedOnboarding: Bool
}

struct OnboardingCard: Identifiable {
    let id = UUID()
    let title: Text?
    let description: Text?
    let imageName: String?
    let articleText: Text?
    let customView: AnyView?
}

struct OnboardingView: View {
    @ObservedObject var onboardingState = OnboardingState()
    var delegate: SheetDismisserProtocol
    let cards: [OnboardingCard]
    
    @State private var currentIndex = 0
    
    var body: some View {
        VStack {
            TabView(selection: $currentIndex) {
                ForEach(cards.indices, id: \.self) { index in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            
                            HStack {
                                if currentIndex > 0 {
                                    Button(action: {
                                        currentIndex -= 1
                                    }) {
                                        Image(systemName: "chevron.left")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            
                            if let imageName = cards[index].imageName {
                                HStack {
                                    Image(systemName: imageName)
                                        .font(.custom("MarkerFelt-Wide", size: 80))
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            VStack {
                                if let title = cards[index].title {
                                    title
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                        .padding(.bottom, 4)
                                }
                                
                                if let description = cards[index].description {
                                    description
                                        .font(.custom("HelveticaNeue-Medium", size: 20))
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                    Divider()
                                }
                            }
                            
                            if let articleText = cards[index].articleText {
                                articleText
                                    .font(.custom("HelveticaNeue-Medium", size: 20))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                            }
                            
                            if let view = cards[index].customView {
                                view
                                    .frame(minWidth: 350, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
                            }
                            
                            HStack {
                                Spacer()
                                if index < cards.count - 1 {
                                    Button(action: {
                                        currentIndex += 1
                                    }) {
                                        HStack {
                                            Text("Next")
                                                .fontWeight(.bold)
                                            Image(systemName: "chevron.right")
                                        }
                                        .foregroundColor(.blue)
                                    }
                                }
                                Spacer()
                            }
                            
                            HStack {
                                Spacer()
                                if index == cards.count - 1 {
                                    Button(action: {
                                        delegate.dismiss()
                                        onboardingState.hasCompletedOnboarding = true
                                    }) {
                                        Text("Close")
                                            .fontWeight(.bold)
                                            .padding()
                                            .background(Color.blue)
                                            .foregroundColor(.white)
                                            .cornerRadius(10)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .padding()
                    }
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(10)
                    .shadow(color: Color.gray.opacity(0.3), radius: 10)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 5)
                }
            }
            .tabViewStyle(PageTabViewStyle())
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
            .frame(width: 350, height: 770)
            .padding()
        }
        .background(Color.clear)
    }
}

@ViewBuilder
func createOnboardingView(delegate: SheetDismisserProtocol) -> some View {
    let cards = [
        OnboardingCard(
            title: Text("Welcome to Monal !"),
            description: Text("Privacy like its 1999 🔒"),
            imageName: "hand.wave",
            articleText: Text("""
            Modern iOS and MacOS XMPP chat client.
            """),
            customView: nil
        ),
        OnboardingCard(
            title: Text("Features"),
            description: Text("Here's a quick look at what you can expect:"),
            imageName: "sparkles",
            articleText: Text("""
            • 🔐 OMEMO Encryption : Secure multi-end messaging using the OMEMO protocol..
            
            • 🛜 Decentralized Network : Leverages the decentralized nature of XMPP, avoiding central servers.
            
            • 🌐 Data privacy : We do not sell or track information for external parties (nor for anyone else).
            
            • 👨‍💻 Open Source : The app's source code is publicly available for audit and contribution.
            """),
            customView: nil
        ),
        OnboardingCard(
            title: Text("Settings"),
            description: Text("These are important privacy settings you may want to review !"),
            imageName: nil,
            articleText: nil,
            customView: AnyView(PrivacySettingsOnboarding(onboardingActive: true))
        )
    ]
    OnboardingView(delegate: delegate, cards: cards)
}

struct OnboardingView_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        createOnboardingView(delegate: delegate)
                    .environmentObject(OnboardingState())
    }
}
