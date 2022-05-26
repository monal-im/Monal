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

@objc protocol MLLQRCodeScannerAccountLoginDelegate : AnyObject
{
    func MLQRCodeAccountLoginScanned(jid: String, password: String)
    func closeQRCodeScanner()
}

@objc protocol MLLQRCodeScannerContactDelegate : AnyObject
{
    func MLQRCodeContactScanned(jid: String, fingerprints: Dictionary<NSInteger, String>)
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

@available(macCatalyst 14.0, *)
@available(iOS 14.0, *)
@objc class MLQRCodeScanner: UIViewController, AVCaptureMetadataOutputObjectsDelegate
{
    @objc weak var loginDelegate : MLLQRCodeScannerAccountLoginDelegate?
    @objc weak var contactDelegate : MLLQRCodeScannerContactDelegate?

    var videoPreviewLayer: AVCaptureVideoPreviewLayer!;
    var captureSession: AVCaptureSession!;

    override func viewDidLoad()
    {
        super.viewDidLoad()
        self.title = NSLocalizedString("QR-Code Scanner", comment: "")
        view.backgroundColor = UIColor.black

#if TARGET_OS_MACCATALYST
        switch AVCaptureDevice.authorizationStatus(for: .video)
        {
            case .authorized:
                self.setupCaptureSession()

            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted {
                        self.setupCaptureSession()
                    }
                }

            case .denied:
                return

            case .restricted:
                return
        }
#else
        setupCaptureSession()
#endif
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

            guard let qrCodeAsString = readableObject.stringValue
            else
            {
                handleQRCodeError()
                return
            }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))

            if(qrCodeAsString.hasPrefix("xmpp:"))
            {
                handleNewContactRequest(contactString: qrCodeAsString)
                return
            }
            else
            {
                // check if we have a json object
                // https://github.com/iNPUTmice/Conversations/issues/3796
                guard let qrCodeData = qrCodeAsString.data(using: .utf8)
                else
                {
                    handleQRCodeError()
                    return
                }
                let jsonDecoder = JSONDecoder()
                do
                {
                    let loginData = try jsonDecoder.decode(XMPPLoginQRCode.self, from: qrCodeData)
                    handleOmemoAccountLogin(loginData: loginData)
                    return
                } catch
                {
                    handleQRCodeError()
                    return
                }
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

    func handleOmemoAccountLogin(loginData: XMPPLoginQRCode)
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
                errorMsg(title: NSLocalizedString("Wrong menu", comment: "QR-Code-Scanner: account scan wrong menu"), msg: NSLocalizedString("The qrcode contains login credentials for a acount. Go to settings and rescan the qrcode", comment: "QR-Code-Scanner: account scan wrong menu"), startCaptureOnClose: true)
            }
        }
    }

    func handleNewContactRequest(contactString: String)
    {
        let XMPP_PREFIX : String = "xmpp:"
        let OMEMO_SID_PREFIX : String = "omemo-sid-"

        var omemoFingerprints = Dictionary<NSInteger, String>()
        var parsedJid : String
        // parse contact string
        if(contactString.hasPrefix(XMPP_PREFIX))
        {
            let shortendContactString = contactString.suffix(contactString.count - XMPP_PREFIX.count)
            let contactStringParts = shortendContactString.components(separatedBy: "?")
            if(contactStringParts.count >= 1 && contactStringParts.count <= 2)
            {
                // check if contactStringParts[0] is a valid jid
                let jidParts = contactStringParts[0].components(separatedBy: "@")
                if(jidParts.count == 2 && jidParts[0].count > 0 && jidParts[1].count > 0)
                {
                    parsedJid = contactStringParts[0]
                    // parse omemo fingerprints if present
                    if(contactStringParts.count == 2)
                    {
                        let omemoParts = contactStringParts[1].components(separatedBy: ";")
                        for omemoPart in omemoParts
                        {
                            let keyParts = omemoPart.components(separatedBy: "=")
                            if(keyParts.count == 2 && keyParts[0].hasPrefix(OMEMO_SID_PREFIX))
                            {
                                let sidStr = keyParts[0].suffix(keyParts[0].count - OMEMO_SID_PREFIX.count)
                                // parse string sid to int
                                let sid = Int(sidStr) ?? -1
                                if(sid > 0)
                                {
                                    // valid sid
                                    if(keyParts[1].count > 0)
                                    {
                                        // todo append
                                        omemoFingerprints[sid] = keyParts[1]
                                    }
                                }
                            }
                        }
                    }
                    // call handler
                    if(self.contactDelegate != nil)
                    {
						self.navigationController?.popViewController(animated: true)
						self.contactDelegate?.MLQRCodeContactScanned(jid: parsedJid, fingerprints: omemoFingerprints)
                        return
                    }
                    else
                    {
                        errorMsg(title: NSLocalizedString("Wrong menu", comment: "QR-Code-Scanner: jid scan wrong menu"), msg: NSLocalizedString("The qrcode contains a jid. Rescan the qrcode in the add user menu", comment: "QR-Code-Scanner: jid scan wrong menu"), startCaptureOnClose: true)
                        return
                    }
                }
            }
        }
        handleQRCodeError()
    }

    func handleQRCodeError()
    {
        errorMsg(title: NSLocalizedString("Invalid format", comment: "QR-Code-Scanner: invalid format"), msg: NSLocalizedString("We could not find a xmpp related QR-Code", comment: "QR-Code-Scanner: invalid format"), startCaptureOnClose: true)
    }
}
