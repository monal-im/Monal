//
//  LoadingOverlay.swift
//  Monal
//
//  Created by Jan on 21.06.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI
import monalxmpp

//data class for overlay state
class LoadingOverlayState : ObservableObject {
    var enabled: Bool
    var headline: AnyView
    var description: AnyView
    init(enabled:Bool = false, headline:AnyView = AnyView(Text("")), description:AnyView = AnyView(Text(""))) {
        self.enabled = enabled
        self.headline = headline
        self.description = description
    }
}

//view modifier for overlay
struct LoadingOverlay: ViewModifier {
    @ObservedObject var state : LoadingOverlayState
    public func body(content: Content) -> some View {
        ZStack(alignment: .center) {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            
            content
            .disabled(state.enabled == true)
            .blur(radius:(state.enabled == true ? 3 : 0))
            
            if(state.enabled == true) {
                VStack {
                    state.headline.font(.headline)
                    state.description.font(.footnote)
                    ProgressView()
                }
                .frame(width: 250, height: 100)
                .background(Color.secondary.colorInvert())
                .cornerRadius(20)
            }
        }
    }
}

//this extension contains the easy-access view modifier
extension View {    
    func addLoadingOverlay(_ overlay: LoadingOverlayState) -> some View {
        modifier(LoadingOverlay(state:overlay))
    }
}

func showLoadingOverlay<T1:View, T2:View>(_ overlay: LoadingOverlayState, headlineView headline: T1, descriptionView description: T2) {
    overlay.headline = AnyView(headline)
    overlay.description = AnyView(description)
    overlay.enabled = true
    //only rerender ui once (not sure if this optimization is really needed, if this is missing, use @Published for member vars of state class)
    overlay.objectWillChange.send()
}

func showLoadingOverlay<T:StringProtocol>(_ overlay: LoadingOverlayState, headline: T, description: T = "") {
    overlay.headline = AnyView(Text(headline))
    overlay.description = AnyView(Text(description))
    overlay.enabled = true
    //only rerender ui once (not sure if this optimization is really needed, if this is missing, use @Published for member vars of state class)
    overlay.objectWillChange.send()
}

func hideLoadingOverlay(_ overlay: LoadingOverlayState) {
    overlay.headline = AnyView(Text(""))
    overlay.description = AnyView(Text(""))
    overlay.enabled = false
    //only rerender ui once (not sure if this optimization is really needed, if this is missing, use @Published for member vars of state class)
    overlay.objectWillChange.send()
}

struct LoadingOverlay_Previews: PreviewProvider {
    @ObservedObject static var overlay1 = LoadingOverlayState(enabled:true, headline:AnyView(Text("Loading")), description:AnyView(Text("More info?")))
    @ObservedObject static var overlay2 = LoadingOverlayState(enabled:true, headline:AnyView(Text("Loading")), description:AnyView(HStack {
        Image(systemName: "checkmark")
        Text("Doing a lot of work...")
    }))
    static var previews: some View {
        Form {
            Text("Entry 1")
            Text("Entry 2")
            Text("Entry 3")
        }
        .addLoadingOverlay(overlay1)
        
        Form {
            Text("Entry 1")
            Text("Entry 2")
            Text("Entry 3")
        }
        .addLoadingOverlay(overlay2)
    }
}
