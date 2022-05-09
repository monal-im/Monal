//
//  QRCodeScannerContactView.swift
//  Monal
//
//  Created by Jan on 16.05.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI

struct QRCodeScannerContactView: UIViewControllerRepresentable {
    @Binding private var jid : String
    @Binding private var fingerprints : Dictionary<NSInteger, String>

    class Coordinator: NSObject, MLLQRCodeScannerContactDelegate {
        var parent: QRCodeScannerContactView

        init(_ parent: QRCodeScannerContactView) {
            self.parent = parent
        }

        func MLQRCodeContactScanned(jid: String, fingerprints: Dictionary<NSInteger, String>) {
            parent.jid = jid
            parent.fingerprints = fingerprints
        }
    }

    init(_ jid: Binding<String>, _ fingerprints: Binding<Dictionary<NSInteger, String>>) {
        self._jid = jid
        self._fingerprints = fingerprints
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<QRCodeScannerContactView>) -> MLQRCodeScanner {
        let qrCodeScannerViewController = MLQRCodeScanner()
        qrCodeScannerViewController.contactDelegate = context.coordinator
        return qrCodeScannerViewController
    }

    func updateUIViewController(_ uiViewController: MLQRCodeScanner, context: UIViewControllerRepresentableContext<QRCodeScannerContactView>) {
    }

    func makeCoordinator() -> QRCodeScannerContactView.Coordinator {
        Coordinator(self)
    }
}
