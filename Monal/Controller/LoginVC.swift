import UIKit
import LocalAuthentication
import Security

class LoginVC: UIViewController {
    
    @IBOutlet weak var emailField: UITextField!
    @IBOutlet weak var passwordField: UITextField!
    @IBOutlet weak var errorLabel: UILabel!
    @IBOutlet weak var biometricView: UIView!
    @IBOutlet weak var biometricBtnImage: UIImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        if BiometricAuthManager.shared.isBiometricSwitchOn() {
            setUpBiometricImage()
        } else {
            biometricView.isHidden = true
        }
    }
    func setUpBiometricImage() {
        weak var weakSelf = self
        if BiometricAuthManager.shared.canUseBiometricAuthentication() {
            // Biometric authentication is available, you can enable a switch or a button to let the user turn it on.
            switch BiometricAuthManager.shared.getBiometricType() {
            case .faceID:
                weakSelf?.biometricBtnImage.image = UIImage(systemName: "faceid")
            case .touchID:
                weakSelf?.biometricBtnImage.image = UIImage(systemName: "touchid")
            case .opticID:
                weakSelf?.biometricBtnImage.image = UIImage(systemName: "opticid")
            default:
                weakSelf?.biometricView.isHidden = true
            }
        } else {
            weakSelf?.biometricView.isHidden = true
        }
        
    }
    @IBAction func loginBtnTapped(_ sender: Any) {
        guard let email = emailField.text,
              let password = passwordField.text else {
            return
        }
        if emailField.text?.isEmpty == true || passwordField.text?.isEmpty == true {
            errorLabel.isHidden = false
            errorLabel.text = "Fields Cannot be empty"
            return
        }
        errorLabel.isHidden = true
        checkLogin(email: email, password: password, fromBio: false)
    }
    @IBAction func touchOrFaceTapped(_ sender: Any) {
        weak var weakSelf = self
        if BiometricAuthManager.shared.canUseBiometricAuthentication() {
            BiometricAuthManager.shared.authenticateWithBiometrics { success, error in
                if success {
                    // Biometric authentication was successful, proceed to login or reveal protected information.
                    KeychainManager.shared.retrieveLoginInfo { email, password, error in
                        if let email = email, let password = password {
                            // Successfully retrieved email and password
                            weakSelf?.emailField.text = email
                            weakSelf?.passwordField.text = password
                            weakSelf?.checkLogin(email: email, password: password, fromBio: true)
                        } else if let error = error {
                            // Handle the error
                            weakSelf?.errorLabel.isHidden = false
                            weakSelf?.errorLabel.text = "Login failed. Please try again."
                            print("Error: \(error.localizedDescription)")
                        }
                    }
                } else {
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
            // Biometric authentication is not available; guide the user to the device settings.
            BiometricAuthManager.shared.showBiometricsSettingsAlert(self)
        }
    }
    func checkLogin(email: String, password: String, fromBio: Bool) {
        if verifyLogin(email: email, password: password) {
            errorLabel.isHidden = true
            if !fromBio {
                KeychainManager.shared.storeLoginInfo(email: email, password: password)
            }
            goToBalanceView()
        } else {
            errorLabel.isHidden = false
            errorLabel.text = "Login failed. Please try again."
        }
    }
    func verifyLogin(email: String, password: String) -> Bool {
        if email == "admin@me.com" && password == "test" {
            return true
        }
        return false
    }
    func goToBalanceView() {
        if let vc = storyboard?.instantiateViewController(withIdentifier: "BalanceVC") as? BalanceVC {
            self.navigationController?.pushViewController(vc,animated: true)
        }
    }
}
extension LoginVC : UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        if textField == emailField {
            passwordField.becomeFirstResponder()
        }
        return true
    }
}