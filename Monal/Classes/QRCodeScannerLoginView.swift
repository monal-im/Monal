//
//  QRCodeScannerView.swift
//  Monal
//
//  Created by CC on 07.05.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI

struct QRCodeScannerLoginView: UIViewControllerRepresentable {
    @Binding private var account : String
    @Binding private var password : String

    class Coordinator: NSObject, MLLQRCodeScannerAccountLoginDelegate {
        var parent: QRCodeScannerLoginView

        init(_ parent: QRCodeScannerLoginView) {
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

    func makeUIViewController(context: UIViewControllerRepresentableContext<QRCodeScannerLoginView>) -> MLQRCodeScanner {
        let qrCodeScannerViewController = MLQRCodeScanner()
        qrCodeScannerViewController.loginDelegate = context.coordinator
        return qrCodeScannerViewController
    }

    func updateUIViewController(_ uiViewController: MLQRCodeScanner, context: UIViewControllerRepresentableContext<QRCodeScannerLoginView>) {
    }

    func makeCoordinator() -> QRCodeScannerLoginView.Coordinator {
        Coordinator(self)
    }
}
