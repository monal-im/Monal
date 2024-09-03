//
//  ServerDetails.swift
//  Monal
//
//  Created by lissine on 3/9/2024.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

private enum Status {
    case success, normal, warning, error
}

private class EntryData: Identifiable, ObservableObject {
    let id = UUID()
    let title: String
    let description: String
    let status: Status

    init(title: String, description: String, status: Status) {
        self.title = title
        self.description = description
        self.status = status
    }

    var color: Color {
        switch status {
            case .success:
                return Color(.serverDetailsEntrySuccess)
            case .normal:
                return .clear
            case .warning:
                return Color(.serverDetailsEntryWarning)
            case .error:
                return Color(.serverDetailsEntryError)
        }
    }
}

private struct ServerDetailsEntry: View {
    @ObservedObject var entryData: EntryData

    init(_ entryData: EntryData) {
        self.entryData = entryData
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(LocalizedStringKey(entryData.title))
                .font(.headline)
            Text(LocalizedStringKey(entryData.description))
                .font(.caption)
        }
        .listRowBackground(entryData.color)
    }
}

struct ServerDetails: View {
    let  xmppAccount: xmpp

    private func showServerVersionInfoView(connection: MLXMPPConnection) -> some View {
        let serverVersion = connection.serverVersion
        let serverName = serverVersion?.appName ?? NSLocalizedString("<unknown server>", comment: "server details")
        let serverVersionString = serverVersion?.appVersion ?? NSLocalizedString("<unknown version>", comment: "server details")
        let serverPlatform = serverVersion?.platformOs != nil ? String(format: NSLocalizedString(" running on %@", comment: "server details"), serverVersion!.platformOs!) : ""
        let description = String(format: NSLocalizedString("version %@%@", comment: "server details"), serverVersionString, serverPlatform)
        let linkText = NSLocalizedString("Considerations for Server Administrators", comment: "server details")
        let link = "[\(linkText)](https://github.com/monal-im/Monal/wiki/Considerations-for-XMPP-server-admins)"
        return ServerDetailsEntry(
            EntryData(
                title: serverName,
                description: "\(description)\n\n\(link)",
                status: .normal
            )
        )
    }

    private func getXEPEntryData(connection: MLXMPPConnection) -> [EntryData] {
        let maxFileUploadSize = HelperTools.bytes(toHuman: Int64(connection.uploadSize))
        let result: [EntryData] = [
            EntryData(
                title: NSLocalizedString("XEP-0163 Personal Eventing Protocol", comment: ""),
                description: NSLocalizedString("This specification defines semantics for using the XMPP publish-subscribe protocol to broadcast state change events associated with an instant messaging and presence account.", comment: ""),
                status: connection.supportsPubSub ? (connection.supportsModernPubSub ? .success : .warning) : .error
            ),

            EntryData(
                title: NSLocalizedString("XEP-0191: Blocking Command", comment: ""),
                description: NSLocalizedString("XMPP protocol extension for communications blocking.", comment: ""),
                status: connection.serverDiscoFeatures.contains("urn:xmpp:blocking") ? .success : .error
            ),

            EntryData(
                title: NSLocalizedString("XEP-0198: Stream Management", comment: ""),
                description: NSLocalizedString("Resume a stream when disconnected. Results in faster reconnect and saves battery life.", comment: ""),
                status: connection.supportsSM3 ? .success : .error
            ),

            EntryData(
                title: NSLocalizedString("XEP-0199: XMPP Ping", comment: ""),
                description: NSLocalizedString("XMPP protocol extension for sending application-level pings over XML streams.", comment: ""),
                status: connection.serverDiscoFeatures.contains("urn:xmpp:ping") ? .success : .error
            ),

            EntryData(
                title: NSLocalizedString("XEP-0215: External Service Discovery", comment: ""),
                description: NSLocalizedString("XMPP protocol extension for discovering services external to the XMPP network, like STUN or TURN servers needed for A/V calls.", comment: ""),
                status: connection.serverDiscoFeatures.contains("urn:xmpp:extdisco:2") ? .success : .error
            ),

            EntryData(
                title: NSLocalizedString("XEP-0237: Roster Versioning", comment: ""),
                description: NSLocalizedString("Defines a proposed modification to the XMPP roster protocol that enables versioning of rosters such that the server will not send the roster to the client if the roster has not been modified.", comment: ""),
                status: connection.supportsRosterVersioning ? .success : .error
            ),

            EntryData(
                title: NSLocalizedString("XEP-0280: Message Carbons", comment: ""),
                description: NSLocalizedString("Synchronize your messages on all loggedin devices.", comment: ""),
                status: connection.usingCarbons2 ? .success : .error
            ),

            EntryData(
                title: NSLocalizedString("XEP-0313: Message Archive Management", comment: ""),
                description: NSLocalizedString("Access message archives on the server.", comment: ""),
                status: connection.accountDiscoFeatures.contains("urn:xmpp:mam:2") ? .success : .error
            ),

            EntryData(
                title: NSLocalizedString("XEP-0352: Client State Indication", comment: ""),
                description: NSLocalizedString("Indicate when a particular device is active or inactive. Saves battery.", comment: ""),
                status: connection.supportsClientState ? .success : .error
            ),

            EntryData(
                title: NSLocalizedString("XEP-0357: Push Notifications", comment: ""),
                description: NSLocalizedString("Receive push notifications via Apple even when disconnected. Vastly improves reliability.", comment: ""),
                status: connection.accountDiscoFeatures.contains("urn:xmpp:push:0") ? (connection.pushEnabled ? .success : .warning) : .error
            ),

            EntryData(
                title: NSLocalizedString("XEP-0363: HTTP File Upload", comment: ""),
                description: String(format: NSLocalizedString("Upload files to the server to share with others. (Maximum allowed size of files reported by the server: %@)", comment: ""), maxFileUploadSize),
                status: connection.supportsHTTPUpload ? .success : .error
            ),

            EntryData(
                title: NSLocalizedString("XEP-0379: Pre-Authenticated Roster Subscription", comment: ""),
                description: NSLocalizedString("Defines a protocol and URI scheme for pre-authenticated roster links that allow a third party to automatically obtain the user's presence subscription.", comment: ""),
                status: connection.supportsRosterPreApproval ? .success : .error
            ),

            EntryData(
                title: NSLocalizedString("XEP-0474: SASL SCRAM Downgrade Protection", comment: ""),
                description: NSLocalizedString("This specification provides a way to secure the SASL and SASL2 handshakes against method and channel-binding downgrades.", comment: ""),
                status: connection.supportsSSDP ? .success : .error
            ),
        ]
        return result
    }

    private func getMUCEntryData(connection: MLXMPPConnection) -> [EntryData] {
        let conferenceServers = connection.conferenceServerIdentities as! [[String: String]]
        guard conferenceServers.count > 0 else {
            return [
                EntryData(
                    title: NSLocalizedString("None", comment: ""),
                    description: NSLocalizedString("This server does not provide any MUC servers.", comment: ""),
                    status: .error
                )
            ]
        }

        var result: [EntryData] = []
        for entry in conferenceServers {
            result.append(
                EntryData(
                    title: String(format: NSLocalizedString("Server: %@", comment: ""), entry["jid"] ?? "error"),
                    description: String(format: NSLocalizedString("%@ (type '%@', category '%@')", comment: ""), entry["name"]!, entry["type"]!, entry["category"]!),
                    status: entry["type"] == "text" ? .success : .normal
                )
            )
        }
        return result
    }

    private func getStunTurnEntryData(connection: MLXMPPConnection) -> [EntryData] {
        var result: [EntryData] = []

        let stunTurnServers = connection.discoveredStunTurnServers as! [[String: String]]
        for service in stunTurnServers {
            var status = Status.normal
            switch(service["type"]) {
                case "stun", "turn", "stuns", "turns":
                    status = .success
                default:
                    status = .error
            }
            result.append(
                EntryData(
                    title: service["type"] ?? "error",
                    description: "\(service["host"]!):\(service["port"]!)",
                    status: status
                )
            )
        }

        if result.isEmpty {
            result.append(
                EntryData(
                    title: NSLocalizedString("None", comment: ""),
                    description: NSLocalizedString("This server does not provide any STUN / TURN services.", comment: ""),
                    status: .error
                )
            )
        }

        return result
    }

    private func getSRVEntryData(xmppAccount: xmpp) -> [EntryData] {
        guard xmppAccount.discoveredServersList.count > 0 else {
            return [
                EntryData(
                    title: NSLocalizedString("None", comment: ""),
                    description: NSLocalizedString("This server does not have any SRV records in DNS.", comment: ""),
                    status: .error
                )
            ]
        }

        var result: [EntryData] = []
        var foundCurrentConn: Bool = false
        for srvEntry in (xmppAccount.discoveredServersList as! [[String: Any]]) {
            let hostname = srvEntry["server"] as! String
            let port = srvEntry["port"] as! NSNumber
            let isSecure = srvEntry["isSecure"] as! Bool
            let prio = srvEntry["priority"] as! NSNumber

            var entryStatus = Status.normal

            // 'connectServer()' has been renamed to 'connect()'
            if (xmppAccount.connectionProperties.server.connect() == hostname &&
                xmppAccount.connectionProperties.server.connectPort() == port &&
                xmppAccount.connectionProperties.server.isDirectTLS() == isSecure
            ) {
                entryStatus = .success
                foundCurrentConn = true
            } else if !foundCurrentConn {
                // Set the status of all connections entries that failed to error
                // discoveredServersList is sorted. Therfore all entries before foundCurrentConn == true have failed
                entryStatus = .error
            }
            result.append(
                EntryData(
                    title: String(format: NSLocalizedString("Server: %@", comment: ""), hostname),
                    description: String(format: NSLocalizedString("Port: %@, Direct TLS: %@, Priority: %@", comment: ""), port, (isSecure ? NSLocalizedString("Yes", comment: "") : NSLocalizedString("No", comment: "")), prio),
                    status: entryStatus
                )
            )

        }
        return result
    }

    private func getTLSEntryData(connection: MLXMPPConnection) -> [EntryData] {
        return [
            EntryData(
                title: NSLocalizedString("TLS 1.2", comment: ""),
                description: NSLocalizedString("Older, slower, but still secure TLS version", comment: ""),
                status: connection.tlsVersion == "1.2" ? .success : .normal
            ),
            EntryData(
                title: NSLocalizedString("TLS 1.3", comment: ""),
                description: NSLocalizedString("Newest TLS version which is faster than TLS 1.2", comment: ""),
                status: connection.tlsVersion == "1.3" ? .success : .normal
            ),
        ]
    }

    private func getSASLEntryData(connection: MLXMPPConnection) -> [EntryData] {
        guard connection.saslMethods.count > 0 else {
            return [
                EntryData(
                    title: NSLocalizedString("None", comment: ""),
                    description: NSLocalizedString("This server does not support modern SASL2 authentication.", comment: ""),
                    status: .error
                )
            ]
        }

        var result: [EntryData] = []
        let saslMethods = connection.saslMethods as! [String: Bool]
        for method in saslMethods.keys.sorted() {
            let used = saslMethods[method]!
            let supported = (SCRAM.supportedMechanisms(includingChannelBinding: true) as! [String]).contains(method)
            var description: String
            switch method {
                case "PLAIN":
                    description = NSLocalizedString("Sends password in cleartext (only encrypted by TLS), not very secure", comment: "")
                case "EXTERNAL":
                    description = NSLocalizedString("Uses TLS client certificates for authentication", comment: "")
                case let method where (method.hasPrefix("SCRAM-") && method.hasSuffix("-PLUS")):
                    description = NSLocalizedString("Salted Challenge Response Authentication Mechanism using the given Hash Method additionally secured by Channel-Binding", comment: "")
                case let method where method.hasPrefix("SCRAM-"):
                    description = NSLocalizedString("Salted Challenge Response Authentication Mechanism using the given Hash Method", comment: "")
                default:
                    description = NSLocalizedString("Unknown authentication method", comment: "")
            }
            result.append(
                EntryData(
                    title: String(format: NSLocalizedString("Method: %@", comment: ""), method),
                    description: description,
                    status: used ? .success : (!supported ? .warning : .normal)
                )
            )
        }
        return result
    }

    private func getChannelBindingEntryData(xmppAccount: xmpp, connection: MLXMPPConnection) -> [EntryData] {
        guard connection.channelBindingTypes.count > 0 else {
            return [
                EntryData(
                    title: NSLocalizedString("None", comment: ""),
                    description: NSLocalizedString("This server does not support any modern channel-binding to secure against MITM attacks on the TLS layer.", comment: ""),
                    status: .error
                )
            ]
        }

        var result: [EntryData] = []
        let channelBindingTypes = connection.channelBindingTypes as! [String: Bool]
        let supportedChannelBindingTypes = xmppAccount.supportedChannelBindingTypes as! [String]
        for type in channelBindingTypes.keys.sorted() {
            let used = channelBindingTypes[type]!
            let supported = supportedChannelBindingTypes.contains(type)
            var description: String

            switch type {
                case "tls-exporter":
                    description = NSLocalizedString("Secure channel-binding defined for TLS1.3 and some TLS1.2 connections.", comment: "")
                case "tls-server-end-point":
                    description = NSLocalizedString("Weakest channel-binding type, not securing against stolen certs/keys, but detects wrongly issued certs.", comment: "")
                default:
                    description = NSLocalizedString("Unknown channel-binding type", comment: "")
            }
            result.append(
                EntryData(
                    title: String(format: NSLocalizedString("Type: %@", comment: ""), type),
                    description: description,
                    status: used ? .success : (!supported ? .warning : .normal)
                )
            )

        }
        return result
    }

    var body: some View {
        let connection = xmppAccount.connectionProperties

        List {
            Section(header: Text("This is the software running on your server.")) {
                showServerVersionInfoView(connection: connection)
            }

            Section(header: Text("These are the modern XMPP capabilities Monal detected on your server after you have logged in.")) {
                ForEach(getXEPEntryData(connection: connection)) { entryData in
                    ServerDetailsEntry(entryData)
                }
            }

            Section(header: Text("These are the MUC servers detected by Monal (blue entry used by Monal).")) {
                ForEach(getMUCEntryData(connection: connection)) { entryData in
                    ServerDetailsEntry(entryData)
                }
            }

            Section(header: Text("These are STUN and TURN services announced by your server (blue entries are used by Monal).")) {
                ForEach(getStunTurnEntryData(connection: connection)) { entryData in
                    ServerDetailsEntry(entryData)
                }
            }

            Section(header: Text("These are SRV resource records found for your domain.")) {
                ForEach(getSRVEntryData(xmppAccount: xmppAccount)) { entryData in
                    ServerDetailsEntry(entryData)
                }
            }

            Section(header: Text("These are the TLS versions supported by Monal, the one used to connect to your server will be green.")) {
                ForEach(getTLSEntryData(connection: connection)) { entryData in
                    ServerDetailsEntry(entryData)
                }
            }

            Section(header: Text("These are the SASL2 methods your server supports (used one in blue, orange ones unsupported by Monal).")) {
                ForEach(getSASLEntryData(connection: connection)) { entryData in
                    ServerDetailsEntry(entryData)
                }
            }

            Section(header: Text("These are the channel-binding types your server supports to detect attacks on the TLS layer (used one in blue, orange ones unsupported by Monal).")) {
                ForEach(getChannelBindingEntryData(xmppAccount: xmppAccount, connection: connection)) { entryData in
                    ServerDetailsEntry(entryData)
                }
            }

        }
        .navigationTitle(connection.identity.domain)
        .listStyle(.grouped)
    }
}
