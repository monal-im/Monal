import Security
import UIKit

class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
    func storeLoginInfo(email: String, password: String) {
        DispatchQueue.global().async {
            let service = "BioAppService"  // A service name for your app
            let account = "BioAccount"  // An account name
            let emailKey = email.data(using: .utf8)
            let passwordData = password.data(using: .utf8)
            if let emailKey = emailKey, let passwordData = passwordData {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                    kSecValueData as String: passwordData,
                    kSecAttrGeneric as String: emailKey
                ]
                SecItemDelete(query as CFDictionary)  // Delete any existing data
                let status = SecItemAdd(query as CFDictionary, nil)
                if status == errSecSuccess {
                    print("Login information securely stored.")
                } else {
                    print("Failed to store login information securely.")
                }
            }
        }
    }
    func retrieveLoginInfo(completion: @escaping (String?, String?, Error?) -> Void) {
        let service = "BioAppService"
        let account = "BioAccount"
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        // Use kSecReturnAttributes to retrieve attributes like email and username.
        query[kSecReturnAttributes as String] = true
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let retrievedData = dataTypeRef as? [String: Any],
           let passwordData = retrievedData[kSecValueData as String] as? Data,
           let emailData = retrievedData[kSecAttrGeneric as String] as? Data,
           let email = String(data: emailData, encoding: .utf8),
           let password = String(data: passwordData, encoding: .utf8) {
            // Successfully retrieved email and password
            completion(email, password, nil)
        } else if let error = SecCopyErrorMessageString(status, nil) as String? {
            // Handle the error
            completion(nil, nil, NSError(domain: "KeychainErrorDomain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: error]))
        } else {
            // Handle the case where retrieval fails
            completion(nil, nil, NSError(domain: "KeychainErrorDomain", code: Int(status), userInfo: nil))
        }
    }
}