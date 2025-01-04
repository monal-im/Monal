//
//  Settings.swift
//  Monal
//
//  Created by lissine on 30/11/2024.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

struct Settings: View {
    @State private var tappedVersionInfo = 0
    @State private var showDebugEntry = HelperTools.defaultsDB().bool(forKey: "showLogInSettings")
    var delegate: SheetDismisserProtocol
    var body: some View {
        Form {
            Section(header: Text("")) {
                AccountList()
#if !IS_QUICKSY
                NavigationLink(destination: LazyClosureView(WelcomeLogIn(delegate: delegate))) {
                    Text("Add Account")
                }
                NavigationLink(destination: LazyClosureView(WelcomeLogIn(advancedMode: true, delegate: delegate))) {
                    Text("Add Account (advanced)")
                }
#endif
            }
            Section(header: Text("App")) {
                NavigationLink(destination: LazyClosureView(GeneralSettings())) {
                    Text("General Settings")
                }
                NavigationLink(destination: LazyClosureView(SwiftuiInterface.SoundsSettings())) {
                    Text("Sounds")
                }
            }
            Section(header: Text("Support")) {
                Link("Email Support",
                    destination: URL(string: "mailto:info@monal-im.org")!)

                NavigationLink(destination: LazyClosureView(WebView(url: URL(string: "https://github.com/monal-im/Monal/issues")!))) {
                    Text("Submit A Bug")
                }

                NavigationLink(destination: LazyClosureView(WebView(url: URL(string: "https://github.com/monal-im/Monal/wiki/FAQ---Frequently-Asked-Questions")!))) {
                    Text("Frequently Asked Questions")
                }
            }
            .tint(Color.primary)
            Section(header: Text("About")) {
#if TARGET_OS_MACCATALYST
                Link("Rate Monal",
                    destination: URL(string: "itms-apps://itunes.apple.com/app/1637078500")!)
#elseif IS_QUICKSY
                Link("Rate Quicksy",
                    destination: URL(string: "itms-apps://itunes.apple.com/app/6538727270")!)
#else
                Link("Rate Monal",
                    destination: URL(string: "itms-apps://itunes.apple.com/app/317711500")!)
#endif

                let path = Bundle.main.path(forResource: "opensource", ofType: "html")
                NavigationLink(destination: LazyClosureView(WebView(url: URL(fileURLWithPath: path!)))) {
                    Text("Open Source")
                }

                NavigationLink(destination: LazyClosureView(WebView(url: URL(string: "https://monal-im.org/privacy")!))) {
                    Text("Privacy")
                }

                NavigationLink(destination: LazyClosureView(WebView(url: URL(string: "https://monal-im.org/about")!))) {
                    Text("About")
                }
#if DEBUG
                NavigationLink(destination: LazyClosureView(DebugView())) {
                    Text("Debug")
                }
#else
                if showDebugEntry {
                    NavigationLink(destination: LazyClosureView(DebugView())) {
                        Text("Debug")
                    }
                }
#endif

                // Version button
                Button(action: {
                    // Copy the version string to the clipboard
                    UIPasteboard.general.setValue(HelperTools.appBuildVersionInfo(for: MLVersionType.IQ), forPasteboardType: UTType.utf8PlainText.identifier)
#if !DEBUG
                    tappedVersionInfo += 1
                    if tappedVersionInfo > 16 {
                        HelperTools.defaultsDB().set(true, forKey: "showLogInSettings")
                        // Redraw the view
                        showDebugEntry = true
                    }
#endif
                }, label: {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(HelperTools.appBuildVersionInfo(for: MLVersionType.IQ))
                    }
                })
            }
            .tint(Color.primary)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
