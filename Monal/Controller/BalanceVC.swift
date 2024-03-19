import UIKit
import LocalAuthentication

class BalanceVC: UIViewController {
    
    @IBOutlet weak var balanceLabel: UILabel!
    @IBOutlet weak var biometricBtn: UIButton!
    @IBOutlet weak var hideBalanceBtn: UIButton!
    @IBOutlet weak var biometricView: UIView!
    @IBOutlet weak var biometricLabel: UILabel!
    @IBOutlet weak var biometricBtnImage: UIImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.setUpBiometricImage()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationItem.hidesBackButton = true
        navigationController?.setNavigationBarHidden(false, animated: false)
        if BiometricAuthManager.shared.isBiometricSwitchOn() {
            setUpBiometricImage()
        } else {
            biometricNotAvailable()
        }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        hideBalance()
    }
    func setUpBiometricImage() {
        weak var weakSelf = self
        biometricView.alpha = 1.0
        biometricView.isUserInteractionEnabled = true
        if BiometricAuthManager.shared.canUseBiometricAuthentication() {
            // Biometric authentication is available, you can enable a switch or a button to let the user turn it on.
            switch BiometricAuthManager.shared.getBiometricType() {
            case .faceID:
                weakSelf?.biometricBtnImage.image = UIImage(systemName: "faceid")
                weakSelf?.biometricLabel.text = "View Balance using"
            case .touchID:
                weakSelf?.biometricBtnImage.image = UIImage(systemName: "touchid")
                weakSelf?.biometricLabel.text = "View Balance using"
            case .opticID:
                weakSelf?.biometricBtnImage.image = UIImage(systemName: "opticid")
                weakSelf?.biometricLabel.text = "View Balance using"
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
        biometricLabel.text = "View Balance (Biometric Not Available)"
    }
    @IBAction func hideBalanceBtn(_ sender: Any) {
        hideBalance()
    }
    func hideBalance() {
        balanceLabel.text = "**********"
        biometricView.isHidden = false
        hideBalanceBtn.isHidden = true
    }
    @IBAction func showBalanceBtn(_ sender: Any) {
        weak var weakSelf = self
        if BiometricAuthManager.shared.canUseBiometricAuthentication() {
            BiometricAuthManager.shared.authenticateWithBiometrics { success, error in
                if success {
                    weakSelf?.balanceLabel.text = "123123123"
                    weakSelf?.biometricView.isHidden = true
                    weakSelf?.hideBalanceBtn.isHidden = false
                } else {
                    weakSelf?.balanceLabel.text = "**********"
                    if let error = error as? LAError {
                        // Handle the authentication error
                        switch error.code {
                        case .userCancel, .systemCancel: break
                            // The user canceled the authentication
                        case .userFallback: break
                            // The user chose to enter a password
                        default:
                            // Handle other authentication errors
                            print("Authentication failed: \(error.localizedDescription)")
                        }
                    }
                }
            }
        } else {
            weakSelf?.balanceLabel.text = "**********"
            // Biometric authentication is not available; guide the user to the device settings.
            BiometricAuthManager.shared.showBiometricsSettingsAlert(self)
        }
    }
    
    @IBAction func showSettingsBtn(_ sender: Any) {
        if let vc = storyboard?.instantiateViewController(withIdentifier: "SettingsVC") as? SettingsVC {
            self.navigationController?.pushViewController(vc,animated: true)
        }
    }
}