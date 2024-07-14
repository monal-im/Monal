//
//  BoardingCards.swift
//  Monal
//
//  Created by Vaidik Dubey on 05/06/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import FrameUp

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
    var delegate: SheetDismisserProtocol
    let cards: [OnboardingCard]
    @ObservedObject var onboardingState = OnboardingState()
    @State private var currentIndex = 0
    
    var body: some View {
        ZStack {
            /// Ensure the ZStack takes the entire area
            Color.clear
            
            ForEach(Array(zip(cards, cards.indices)), id: \.1) { card, index in
                /// Only show card that's visible
                if index == currentIndex {
                    GeometryReader { proxy in
                        SmartScrollView(.vertical, showsIndicators: true, optionalScrolling: true, shrinkToFit: false) {
                            VStack(alignment: .leading, spacing: 16) {
                                
                                if currentIndex > 0 {
                                    Button {
                                        currentIndex -= 1
                                    } label: {
                                        Label("Back", systemImage: "chevron.left")
                                            .labelStyle(.iconOnly)
                                            .foregroundColor(.blue)
                                            .padding()
                                    }
                                }
                                
                                HStack {
                                    if let imageName = card.imageName {
                                        Image(systemName: imageName)
                                            .font(.custom("MarkerFelt-Wide", size: 80))
                                            .foregroundColor(.blue)
                                            .accessibilityHidden(true)
                                        
                                    }
                                    
                                    card.title?
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                        .padding(.bottom, 4)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isHeader)
                                
                                if let description = card.description {
                                    description
                                        .font(.custom("HelveticaNeue-Medium", size: 20))
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                        /// This ensures text doesn't get truncated which sometimes happens in ScrollView
                                        .fixedSize(horizontal: false, vertical: true)
                                    
                                    Divider()
                                }
                                
                                card.articleText?
                                    .font(.custom("HelveticaNeue-Medium", size: 20))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                
                                card.customView
                                
                                Spacer()
                                
                                Group {
                                    if index < cards.count - 1 {
                                        Button {
                                            currentIndex += 1
                                        } label: {
                                            HStack {
                                                Text("Next")
                                                    .fontWeight(.bold)
                                                Image(systemName: "chevron.right")
                                            }
                                        }
                                    } else {
                                        Button {
                                            onboardingState.hasCompletedOnboarding = true
                                            delegate.dismiss()
                                        } label: {
                                            Text("Close")
                                                .fontWeight(.bold)
                                                .padding()
                                                .background(Color.blue)
                                                .foregroundColor(.white)
                                                .cornerRadius(10)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .padding(.bottom, 16)
                            .padding()
                            /// Sets the minimum frame height to the available height of the scrollview and the maxHeight to infinity
                            .frame(minHeight: proxy.size.height, maxHeight: .infinity)
                        }
                    }
                    .accessibilityAddTraits(.isModal)
                }
            }
        }
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
            • 🔐 OMEMO Encryption : Secure multi-end messaging using the OMEMO protocol.
            
            • 🛜 Decentralized Network : Leverages the decentralized nature of XMPP, avoiding central servers.
            
            • 🌐 Data privacy : We do not sell or track information for external parties (nor for anyone else).
            
            • 👨‍💻 Open Source : The app's source code is publicly available for audit and contribution.
            """),
            customView: nil
        ),
        OnboardingCard(
            title: Text("Settings"),
            description: Text("These are important privacy settings you may want to review!"),
            imageName: nil,
            articleText: nil,
            customView: AnyView(PrivacySettingsSubview(onboardingPart:0))
        ),
        OnboardingCard(
            title: Text("Settings"),
            description: Text("These are important privacy settings you may want to review!"),
            imageName: nil,
            articleText: nil,
            customView: AnyView(PrivacySettingsSubview(onboardingPart:1))
        ),
        OnboardingCard(
            title: Text("Even more to customize!"),
            description: Text("You can customize even more, just use the button below to open the settings."),
            imageName: "hand.wave",
            articleText: nil,
            customView: AnyView(TakeMeToSettingsView(delegate:delegate))
        ),
    ]
    OnboardingView(delegate: delegate, cards: cards)
}

struct TakeMeToSettingsView: View {
    @ObservedObject var onboardingState = OnboardingState()
    var delegate: SheetDismisserProtocol
    
    var body: some View {
        HStack {
            Spacer()
            Button(action: {
                let appDelegate = UIApplication.shared.delegate as! MonalAppDelegate
                if let activeChats = appDelegate.activeChats {
                    activeChats.enqueueGeneralSettings = true
                }
                onboardingState.hasCompletedOnboarding = true
                delegate.dismiss()
            }) {
                Text("Take me to settings")
                    .fontWeight(.bold)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            Spacer()
        }
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        createOnboardingView(delegate: delegate)
                    .environmentObject(OnboardingState())
    }
}
