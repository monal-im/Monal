//
//  MLOmemoQrCodeView.swift
//  Monal
//
//  Created by Friedrich Altheide on 20.02.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import CoreImage.CIFilterBuiltins

func createQrCode(value: String) -> UIImage
{
    let qrCodeFilter = CIFilter.qrCodeGenerator()
    // set qrcode value
    qrCodeFilter.message = Data(value.utf8)

    if let qrCodeImage = qrCodeFilter.outputImage {
        if let t = CIContext().createCGImage(qrCodeImage, from: qrCodeImage.extent) {
            return UIImage(cgImage: t)
        }
    }

    return UIImage()
}

struct OmemoQrCodeView: View {
    let jid: String
    @State private var qrCodeImage: UIImage

    init(contact: ObservableKVOWrapper<MLContact>)
    {
        self.jid = contact.obj.contactJid
        if let account = contact.obj.account {
            let devices = Array(account.omemo.knownDevices(forAddressName: self.jid))
            var keyList = ""
            var prefix = "?"
            for device in devices {
                let address = SignalAddress.init(name: self.jid, deviceId: device.int32Value)
                let identity = account.omemo.getIdentityFor(address)

                if(account.omemo.isTrustedIdentity(address, identityKey: identity)) {
                    let hexIdentity = String(HelperTools.signalHexKey(with: identity))
                    let keyString = String(format: "%@omemo-sid-%@=%@", prefix, device, hexIdentity)
                    keyList += keyString
                    prefix = ";"
                }
            }
            self.qrCodeImage = createQrCode(value: String(format:"xmpp:%@%@", jid, keyList))
        } else {
            self.qrCodeImage = UIImage()
        }
    }

    var body: some View {
        Image(uiImage: qrCodeImage)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .aspectRatio(1, contentMode: .fit)
            .navigationBarTitle(Text("Keys of \(self.jid)"), displayMode: .inline)
    }
}

struct OmemoQrCodeView_Previews: PreviewProvider {
    static var previews: some View {
        OmemoQrCodeView(contact: ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(0)))
    }
}
