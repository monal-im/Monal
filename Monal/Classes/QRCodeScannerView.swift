//
//  QRCodeScannerView.swift
//  Monal
//
//  Created by CC on 07.05.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI

struct QRCodeScannerView: UIViewControllerRepresentable {
    @Binding private var account : String
    @Binding private var password : String

    class Coordinator: NSObject, MLLQRCodeScannerAccountLoginDeleagte {
        var parent: QRCodeScannerView
        
        init(_ parent: QRCodeScannerView) {
            self.parent = parent
        }
        
        func MLQRCodeAccountLoginScanned(jid: String, password: String) {
            parent.account = jid
            parent.password = password
        }
    }

    init(_ account: Binding<String>, _ password: Binding<String>) {
        self._account = account
        self._password = password
    }
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<QRCodeScannerView>) -> MLQRCodeScanner {
        let qrCodeScannerViewController = MLQRCodeScanner()
        qrCodeScannerViewController.loginDelegate = context.coordinator
        return qrCodeScannerViewController
    }

    func updateUIViewController(_ uiViewController: MLQRCodeScanner, context: UIViewControllerRepresentableContext<QRCodeScannerView>) {
    }
    
    func makeCoordinator() -> QRCodeScannerView.Coordinator {
        Coordinator(self)
    }
}
