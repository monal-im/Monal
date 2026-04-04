//
//  RichAlert.swift
//  Monal
//
//  Created by Thilo Molitor on 25.12.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

import ViewExtractor
import FrameUp

struct RichAlertView<T, TitleContent, BodyContent, ButtonContent>: ViewModifier where TitleContent: View, BodyContent: View, ButtonContent: View {
    @Binding public var isPresented: T?
    let alertTitle: (T) -> TitleContent
    let alertBody: (T) -> BodyContent
    let alertButtons: (T) -> ButtonContent
    @State private var scrollViewContentSize: CGSize = .zero
    
    public func body(content: Content) -> some View {
        return ZStack(alignment: .center) {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            
            content
                .disabled(isPresented != nil)
                .blur(radius:(isPresented != nil ? 3 : 0))
            
            if let data:T = isPresented {
                VStack {
                    alertTitle(data)
                        .font(.headline)
                        .padding([.leading, .trailing], 24)
                    Divider()
                    SmartScrollView(.vertical, showsIndicators: true, optionalScrolling: true, shrinkToFit: true) {
                        VStack {
                            alertBody(data)
                                .padding([.leading, .trailing], 24)
                        }
                    }
                    let buttonViews = alertButtons(data)
                    Extract(buttonViews) { views in
                        if views.count == 0 || buttonViews is EmptyView  {
                            Divider()
                            Button("Close") {
                                isPresented = nil
                            }
                                .padding([.leading, .trailing], 24)
                                .buttonStyle(DefaultButtonStyle())
                        } else {
                            ForEach(views) { view in
                                Divider()
                                .padding(0)
                                view
                                    .padding([.leading, .trailing], 24)
                                    .buttonStyle(DefaultButtonStyle())
                            }
                        }
                    }
                }
                .foregroundColor(.primary)
                .padding([.top, .bottom], 13)
                .frame(width: 320)
                .background(Color.background)
                .cornerRadius(16)
                .shadow(color: Color.primary.opacity(0.4), radius: 16, x: 0, y: 0)
                .padding([.top, .bottom], 24)
            }
        }
        .transition(.opacity)
    }
}

//this contains all possible variants to use this (view builders don't seem to be able to take default arguments :/ )
extension View {
    //title(X), body(X), (buttons)
    func richAlert<T>(isPresented: Binding<T?>, @ViewBuilder title: @escaping (_ data: T) -> some View, @ViewBuilder body: @escaping (_ data: T) -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:title, alertBody:body, alertButtons:{ _ in EmptyView() }))
    }
    func richAlert<T>(isPresented: Binding<T?>, title: @autoclosure @escaping () -> some View, @ViewBuilder body: @escaping (_ data: T) -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:{ _ in title() }, alertBody:body, alertButtons:{ _ in EmptyView() }))
    }
    //title(), body(X), (buttons)
    func richAlert<T>(isPresented: Binding<T?>, @ViewBuilder title: @escaping () -> some View, @ViewBuilder body: @escaping (_ data: T) -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:{ _ in title() }, alertBody:body, alertButtons:{ _ in EmptyView() }))
    }
    
    //title(X), body(), (buttons)
    func richAlert<T>(isPresented: Binding<T?>, @ViewBuilder title: @escaping (_ data: T) -> some View, @ViewBuilder body: @escaping () -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:title, alertBody:{ _ in body() }, alertButtons:{ _ in EmptyView() }))
    }
    func richAlert<T>(isPresented: Binding<T?>, title: @autoclosure @escaping () -> some View, @ViewBuilder body: @escaping () -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:{ _ in title() }, alertBody:{ _ in body() }, alertButtons:{ _ in EmptyView() }))
    }
    //title(), body(), (buttons)
    func richAlert<T>(isPresented: Binding<T?>, @ViewBuilder title: @escaping () -> some View, @ViewBuilder body: @escaping () -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:{ _ in title() }, alertBody:{ _ in body() }, alertButtons:{ _ in EmptyView() }))
    }
    
    
    //title(X), body(X), buttons(X)
    func richAlert<T>(isPresented: Binding<T?>, @ViewBuilder title: @escaping (_ data: T) -> some View, @ViewBuilder body: @escaping (_ data: T) -> some View, @ViewBuilder buttons: @escaping (_ data: T) -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:title, alertBody:body, alertButtons:buttons))
    }
    func richAlert<T>(isPresented: Binding<T?>, title: @autoclosure @escaping () -> some View, @ViewBuilder body: @escaping (_ data: T) -> some View, @ViewBuilder buttons: @escaping (_ data: T) -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:{ _ in title() }, alertBody:body, alertButtons:buttons))
    }
    //apparently this is sometimes somehow needed to not confuse the compiler into using some of the other functions instead of this
    //(it tries to use the title(), body(), buttons(X) variant in Quicksy_RegisterAccount)
    func richAlertX<T>(isPresented: Binding<T?>, title: @autoclosure @escaping () -> some View, @ViewBuilder body: @escaping (_ data: T) -> some View, @ViewBuilder buttons: @escaping (_ data: T) -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:{ _ in title() }, alertBody:body, alertButtons:buttons))
    }
    //title(), body(X), buttons(X)
    func richAlert<T>(isPresented: Binding<T?>, @ViewBuilder title: @escaping () -> some View, @ViewBuilder body: @escaping (_ data: T) -> some View, @ViewBuilder buttons: @escaping (_ data: T) -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:{ _ in title() }, alertBody:body, alertButtons:buttons))
    }
    
    //title(X), body(), buttons(X)
    func richAlert<T>(isPresented: Binding<T?>, @ViewBuilder title: @escaping (_ data: T) -> some View, @ViewBuilder body: @escaping () -> some View, @ViewBuilder buttons: @escaping (_ data: T) -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:title, alertBody:{ _ in body() }, alertButtons:buttons))
    }
    func richAlert<T>(isPresented: Binding<T?>, title: @autoclosure @escaping () -> some View, @ViewBuilder body: @escaping () -> some View, @ViewBuilder buttons: @escaping (_ data: T) -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:{ _ in title() }, alertBody:{ _ in body() }, alertButtons:buttons))
    }
    //title(), body(), buttons(X)
    func richAlert<T>(isPresented: Binding<T?>, @ViewBuilder title: @escaping () -> some View, @ViewBuilder body: @escaping () -> some View, @ViewBuilder buttons: @escaping (_ data: T) -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:{ _ in title() }, alertBody:{ _ in body() }, alertButtons:buttons))
    }
    
    
    //title(X), body(X), buttons()
    func richAlert<T>(isPresented: Binding<T?>, @ViewBuilder title: @escaping (_ data: T) -> some View, @ViewBuilder body: @escaping (_ data: T) -> some View, @ViewBuilder buttons: @escaping () -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:title, alertBody:body, alertButtons:{ _ in buttons() }))
    }
    func richAlert<T>(isPresented: Binding<T?>, title: @autoclosure @escaping () -> some View, @ViewBuilder body: @escaping (_ data: T) -> some View, @ViewBuilder buttons: @escaping () -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:{ _ in title() }, alertBody:body, alertButtons:{ _ in buttons() }))
    }
    //title(), body(X), buttons()
    func richAlert<T>(isPresented: Binding<T?>, @ViewBuilder title: @escaping () -> some View, @ViewBuilder body: @escaping (_ data: T) -> some View, @ViewBuilder buttons: @escaping () -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:{ _ in title() }, alertBody:body, alertButtons:{ _ in buttons() }))
    }
    
    //title(X), body(), buttons()
    func richAlert<T>(isPresented: Binding<T?>, @ViewBuilder title: @escaping (_ data: T) -> some View, @ViewBuilder body: @escaping () -> some View, @ViewBuilder buttons: @escaping () -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:title, alertBody:{ _ in body() }, alertButtons:{ _ in buttons() }))
    }
    func richAlert<T>(isPresented: Binding<T?>, title: @autoclosure @escaping () -> some View, @ViewBuilder body: @escaping () -> some View, @ViewBuilder buttons: @escaping () -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:{ _ in title() }, alertBody:{ _ in body() }, alertButtons:{ _ in buttons() }))
    }
    //title(), body(), buttons()
    func richAlert<T>(isPresented: Binding<T?>, @ViewBuilder title: @escaping () -> some View, @ViewBuilder body: @escaping () -> some View, @ViewBuilder buttons: @escaping () -> some View) -> some View {
        modifier(RichAlertView(isPresented:isPresented, alertTitle:{ _ in title() }, alertBody:{ _ in body() }, alertButtons:{ _ in buttons() }))
    }
}


struct RichAlert_Previews: PreviewProvider {
    static var previews: some View {
        Color.clear
        .richAlert(isPresented:Binding(get:{true}, set:{_ in}), title:Text("Cool Title")) {
            VStack {
                Text("Rich Text")
                Text("BODY")
            }
        }
    }
}
