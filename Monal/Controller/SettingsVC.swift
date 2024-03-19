//
//  SettingsVC.swift
//  BiometricAuthentication
//
//  Created by SjxSubham 
//

import UIKit
import UniformTypeIdentifiers
import monalxmpp

class SettingsVC: UIViewController {

    @IBOutlet weak var biometricView: UIView!
    @IBOutlet weak var biometricLabel: UILabel!
    @IBOutlet weak var biometricImage: UIImageView!
    @IBOutlet weak var biometricSwtich: UISwitch!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
        setUpBiometricImage()
        if BiometricAuthManager.shared.canUseBiometricAuthentication() {
            biometricSwtich.setOn(BiometricAuthManager.shared.isBiometricSwitchOn(), animated: false)
        } else {
            biometricNotAvailable()
        }
    }
    
    func setUpBiometricImage() {
        weak var weakSelf = self
        if BiometricAuthManager.shared.canUseBiometricAuthentication() {
            // Biometric authentication is available, you can enable a switch or a button to let the user turn it on.
            switch BiometricAuthManager.shared.getBiometricType() {
            case .faceID:
                weakSelf?.biometricImage.image = UIImage(systemName: "faceid")
                weakSelf?.biometricLabel.text = "Enable Face ID"
            case .touchID:
                weakSelf?.biometricImage.image = UIImage(systemName: "touchid")
                weakSelf?.biometricLabel.text = "Enable Touch ID"
            case .opticID:
                weakSelf?.biometricImage.image = UIImage(systemName: "opticid")
                weakSelf?.biometricLabel.text = "Enable Optical ID"
            default:
                weakSelf?.biometricNotAvailable()
            }
        } else {
            weakSelf?.biometricNotAvailable()
        }
    }
    
    func biometricNotAvailable() {
        biometricView.alpha = 0.5
        biometricView.isUserInteractionEnabled = false
        biometricLabel.text = "Enable Biometric (Biometric Not Available)"
    }
    
    @IBAction func biometricSwitchTap(_ sender: UISwitch) {
        BiometricAuthManager.shared.setBiometricSwitchState(isOn: sender.isOn)
    }
    
    @IBAction func logoutBtnTapped(_ sender: Any) {
        if let vc = storyboard?.instantiateViewController(withIdentifier: "LoginVC") as? LoginVC {
            self.navigationController?.pushViewController(vc,animated: true)
        }
    }

}