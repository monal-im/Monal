//
//  WebView.swift
//  Monal
//
//  Created by lissine on 30/11/2024.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import WebKit

struct WebKitView: UIViewRepresentable {
    var url: URL

    func makeUIView(context: Context) -> WKWebView {
        return WKWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        var request = URLRequest(url: url)
        if HelperTools.defaultsDB().bool(forKey: "useDnssecForAllConnections") {
            request.requiresDNSSECValidation = true
        }
        webView.load(request)
    }
}

struct WebView: View {
    var url: URL
    var body: some View {
        WebKitView(url: url)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !url.isFileURL {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            UIApplication.shared.open(url)
                        }, label: {
                            Image(systemName: "safari")
                                .accessibilityLabel("Open in default browser")
                        })
                    }
                }
            }
    }
}
