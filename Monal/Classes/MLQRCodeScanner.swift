//
//  MLQRCodeScanner.swift
//  Monal
//
//  Created by Friedrich Altheide on 20.11.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

import CocoaLumberjack
import AVFoundation
import UIKit
import SwiftUI
import SafariServices

@objc protocol MLLQRCodeScannerAccountLoginDelegate : AnyObject
{
    func MLQRCodeAccountLoginScanned(jid: String, password: String)
    func closeQRCodeScanner()
}

struct XMPPLoginQRCode : Codable
{
    let usedProtocol:String
    let address:String
    let password:String

    private enum CodingKeys: String, CodingKey
    {
        case usedProtocol = "protocol", address, password
    }
}

@objc class MLQRCodeScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate
{
    @objc weak var loginDelegate : MLLQRCodeScannerAccountLoginDelegate?

    var videoPreviewLayer: AVCaptureVideoPreviewLayer!;
    var captureSession: AVCaptureSession!;

    override func viewDidLoad()
    {
        super.viewDidLoad()
        self.title = NSLocalizedString("QR-Code Scanner", comment: "")
        view.backgroundColor = UIColor.black

        switch AVCaptureDevice.authorizationStatus(for: .video)
        {
            case .authorized:
                self.setupCaptureSession()

            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted {
                        DispatchQueue.main.async {
                            self.setupCaptureSession()
                        }
                    }
                }

            case .denied:
                return

            case .restricted:
                return

            @unknown default:
                return;
        }
    }

    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)

        if (captureSession?.isRunning == false)
        {
            captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool)
    {
        if (captureSession?.isRunning == true)
        {
            captureSession.stopRunning()
        }
        super.viewWillDisappear(animated)
    }

    func setupCaptureSession()
    {
        // init capture session
        captureSession = AVCaptureSession()
        guard let captureDevice = AVCaptureDevice.default(for: .video)
        else
        {
            errorMsg(title: NSLocalizedString("QR-Code video error", comment: "QR-Code-Scanner"), msg: NSLocalizedString("Could not get default capture device", comment: "QR-Code-Scanner"))
            return;
        }
        let videoInput: AVCaptureDeviceInput

        do
        {
            videoInput = try AVCaptureDeviceInput(device: captureDevice)
        } catch
        {
            errorMsg(title: NSLocalizedString("QR-Code video error", comment: "QR-Code-Scanner"), msg: NSLocalizedString("Could not init video session", comment: "QR-Code-Scanner"))
            return
        }
        if(captureSession.canAddInput(videoInput))
        {
            captureSession.addInput(videoInput)
        }
        else
        {
            errorMsgNoCameraFound()
            return;
        }
        let metadataOutput = AVCaptureMetadataOutput()

        if (captureSession.canAddOutput(metadataOutput)) {
            captureSession.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            errorMsgNoCameraFound()
            return
        }

        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer.frame = view.layer.bounds
        videoPreviewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(videoPreviewLayer)

        captureSession.startRunning()
    }

    func errorMsgNoCameraFound()
    {
        captureSession = nil

        errorMsg(title: NSLocalizedString("Could not access camera", comment: "QR-Code-Scanner: camera not found"), msg: NSLocalizedString("It does not seem as your device has a camera. Please use a device with a camera for scanning", comment: "QR-Code-Scanner: Camera not found"))
    }

    override var prefersStatusBarHidden: Bool
    {
        return false
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask
    {
        return .portrait
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession.stopRunning()

        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }

            guard let qrCodeAsString = readableObject.stringValue else {
                return handleQRCodeError()
            }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))

            //open https?:// urls in safari view controller just as they would if the qrcode was scanned using the camera app
            if qrCodeAsString.hasPrefix("https://") || qrCodeAsString.hasPrefix("http://") {
                if let url = URL(string:qrCodeAsString) {
                    let vc = SFSafariViewController(url:url, configuration:SFSafariViewController.Configuration())
                    present(vc, animated: true)
                }
            //let our app delegate handle all xmpp: urls
            } else if qrCodeAsString.hasPrefix("xmpp:") {
                guard let url = URL(string:qrCodeAsString) else {
                    return handleQRCodeError()
                }
                return (UIApplication.shared.delegate as! MonalAppDelegate).handleXMPPURL(url)
            //if none of the above: handle json provisioning qrcodes, see: https://github.com/iNPUTmice/Conversations/issues/3796
            } else {
                // check if we have a json object
                guard let qrCodeData = qrCodeAsString.data(using:.utf8) else {
                    return handleQRCodeError()
                }
                let jsonDecoder = JSONDecoder()
                do {
                    let loginData = try jsonDecoder.decode(XMPPLoginQRCode.self, from:qrCodeData)
                    handleAccountLogin(loginData:loginData)
                } catch {
                    handleQRCodeError()
                }
                return
            }
        }
    }

    func errorMsg(title: String, msg: String, startCaptureOnClose: Bool = false)
    {
        let ac = UIAlertController(title: title, message: msg, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: NSLocalizedString("Close", comment: ""), style: .default)
        {
            action -> Void in
            // start capture again after invalid qr code
            if(startCaptureOnClose == true)
            {
                self.captureSession.startRunning()
            }
            else if (self.loginDelegate != nil) {
                self.loginDelegate?.closeQRCodeScanner()
            }
        }
        )
        DispatchQueue.main.async{
            self.present(ac, animated: true)
        }
    }

    func handleAccountLogin(loginData: XMPPLoginQRCode)
    {
        if(loginData.usedProtocol == "xmpp")
        {
            if(self.loginDelegate != nil)
            {
				self.navigationController?.popViewController(animated: true)
				self.loginDelegate?.MLQRCodeAccountLoginScanned(jid: loginData.address, password: loginData.password)
            }
            else
            {
                errorMsg(title: NSLocalizedString("Wrong menu", comment: "QR-Code-Scanner: account scan wrong menu"), msg: NSLocalizedString("The qrcode contains login credentials for an acount. Go to settings -> new account and rescan the qrcode", comment: "QR-Code-Scanner: account scan wrong menu"), startCaptureOnClose: true)
            }
        }
    }

    func handleQRCodeError()
    {
        errorMsg(title: NSLocalizedString("Invalid format", comment: "QR-Code-Scanner: invalid format"), msg: NSLocalizedString("We could not find a xmpp related QR-Code", comment: "QR-Code-Scanner: invalid format"), startCaptureOnClose: true)
    }
}

struct MLQRCodeScanner : UIViewControllerRepresentable {
    let handleLogin: ((String, String) -> Void)?
    let handleClose: (() -> Void)

    class Coordinator: NSObject, MLLQRCodeScannerAccountLoginDelegate {
        let handleLogin: ((String, String) -> Void)?
        let handleClose: (() -> Void)

        func MLQRCodeAccountLoginScanned(jid: String, password: String) {
            if(self.handleLogin != nil) {
                self.handleLogin!(jid, password)
            }
        }

        func closeQRCodeScanner() {
            self.handleClose()
        }

        init(handleLogin: ((String, String) -> Void)?, handleClose: @escaping () -> Void) {
            self.handleLogin = handleLogin
            self.handleClose = handleClose
        }
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<MLQRCodeScanner>) -> MLQRCodeScannerController {
        let qrCodeScannerViewController = MLQRCodeScannerController()
        if(self.handleLogin != nil) {
            qrCodeScannerViewController.loginDelegate = context.coordinator
        }
        return qrCodeScannerViewController
    }

    func updateUIViewController(_ uiViewController: MLQRCodeScannerController, context: UIViewControllerRepresentableContext<MLQRCodeScanner>) {
    }

    func makeCoordinator() -> MLQRCodeScanner.Coordinator {
        Coordinator(handleLogin: self.handleLogin, handleClose: self.handleClose);
    }

    init(handleClose: @escaping () -> Void) {
        self.handleLogin = nil
        self.handleClose = handleClose
    }

    init(handleLogin: @escaping (String, String) -> Void, handleClose: @escaping () -> Void) {
        self.handleLogin = handleLogin
        self.handleClose = handleClose
    }
}
