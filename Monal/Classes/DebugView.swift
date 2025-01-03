//
//  LogView.swift
//  Monal
//
//  Created by Zain Ashraf on 3/23/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

class DebugDefaultDB: ObservableObject {
    @defaultsDB("udpLoggerEnabled")
    var udpLoggerEnabled: Bool
    
    @defaultsDB("udpLoggerPort")
    var udpLoggerPort: String
    
    @defaultsDB("udpLoggerHostname")
    var udpLoggerHostname: String
    
    @defaultsDB("udpLoggerKey")
    var udpLoggerKey: String
    
    @defaultsDB("hasCompletedOnboarding")
    var hasCompletedOnboarding: Bool
    
    @defaultsDB("showNewChatView")
    var showNewChatView: Bool
}

struct LogFilesView: View {
    @State private var sortedLogFileInfos: [DDLogFileInfo] = []
    @State private var showShareSheet:Bool = false
    @State private var fileURL: URL?
    @State private var showingDBExportFailedAlert = false
    
    func refreshSortedLogfiles() {
        if let sortedLogFileInfos = HelperTools.fileLogger?.logFileManager.sortedLogFileInfos {
            self.sortedLogFileInfos = sortedLogFileInfos
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            refreshSortedLogfiles()
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("This can be used to export logfiles.\n[Learn how to read them](https://github.com/monal-im/Monal/wiki/Introduction-to-Monal-Logging#view-the-log).")
            List {
                Section(header: Text("Logfiles")) {
                    ForEach(sortedLogFileInfos, id: \.self) { logFileInfo in
                        Button(logFileInfo.fileName) {
                            fileURL = URL(fileURLWithPath: logFileInfo.filePath)
                        }
                    }
                }
                Section(header: Text("Database Files")) {
                    Button("Main Database") {
                        if let dbFile = DataLayer.sharedInstance().exportDB() {
                            self.fileURL = URL(fileURLWithPath: dbFile)
                        } else {
                            showingDBExportFailedAlert = true
                        }
                    }
                    Button("IPC Database") {
                        if let dbFile = HelperTools.exportIPCDatabase() {
                            self.fileURL = URL(fileURLWithPath: dbFile)
                        } else {
                            showingDBExportFailedAlert = true
                        }
                    }
                }
            }
            .listStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.interpolatedWindowBackground)
        .alert(isPresented: $showingDBExportFailedAlert) {
            Alert(title: Text("Database Export Failed"), message: Text("Failed to export the database, please check the logfile for errors and try again."), dismissButton: .default(Text("Close")))
        }
        .sheet(isPresented:$fileURL.optionalMappedToBool()) {
            if let fileURL = fileURL {
                ActivityViewController(activityItems: [fileURL])
            }
        }
        .onAppear {
            refreshSortedLogfiles()
        }
    }
}

struct UDPConfigView: View {
    @ObservedObject var defaultDB = DebugDefaultDB()
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("The UDP logger allows you to livestream the log to the configured IP. Please use a secure key when streaming over the internet!\n[Learn how to receive the log stream](https://github.com/monal-im/Monal/wiki/Introduction-to-Monal-Logging#stream-the-log).")
            Form {
                Section(header: Text("UDP Logger Configuration")) {
                    Toggle(isOn: $defaultDB.udpLoggerEnabled) {
                        Text("Enable")
                    }
                    LabeledContent("Logserver IP:") {
                        TextField("Logserver IP", text: $defaultDB.udpLoggerHostname, prompt: Text("Required"))
                    }
                    LabeledContent("Logserver Port:") {
                        TextField("Logserver Port", text: $defaultDB.udpLoggerPort, prompt: Text("Required"))
                    }.keyboardType(.numberPad)
                    LabeledContent("AES Encryption Key:") {
                        TextField("AES Encryption Key", text: $defaultDB.udpLoggerKey, prompt: Text("Required"))
                    }
                }
            }
            .padding(0)
            .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.interpolatedWindowBackground)
    }
}

struct CrashTestingView: View {
    @ObservedObject var defaultDB = DebugDefaultDB()
    
    var body: some View {
            VStack(alignment:.leading, spacing: 25) {
                Section(header: Text("Some debug settings.")) {
                    Toggle(isOn: $defaultDB.hasCompletedOnboarding) {
                        Text("Don't show onboarding")
                    }
                    
                    Toggle(isOn: $defaultDB.showNewChatView) {
                        Text("Show new SwiftUI ChatView")
                    }
                }
                
                Text("The following buttons allow you to forcefully crash the app using several different methods to test the crash handling.")
                
                Group {
                    Button("Try to call unknown handler method") {
                        DispatchQueue.global(qos: .default).async(execute: {
                            HelperTools.flushLogs(withTimeout: 0.100)
                            let handler = MLHandler(delegate: self, handlerName: "IDontKnowThis", andBoundArguments: [:])
                            handler.call(withArguments: nil)
                        })
                    }
                    Button("Bad Access Crash") {
                        HelperTools.flushLogs(withTimeout: 0.100)
                        let delegate: AnyClass? = NSClassFromString("MonalAppDelegate")
                        print(delegate.unsafelyUnwrapped.audiovisualTypes())
                        
                    }
                    Button("MLAssert Crash") {
                        HelperTools.flushLogs(withTimeout: 0.100)
                        MLAssert(false, "MLAssert_example1")
                    }
                    Button("MLAssert Crash without flush") {
                        MLAssert(false, "MLAssert_example2")
                    }
                    Button("Assertion Crash") {
                        HelperTools.flushLogs(withTimeout: 0.100)
                        assert(false)
                    }
                    Button("Fatal Error Crash") {
                        HelperTools.flushLogs(withTimeout: 0.100)
                        fatalError("fatalError_example")
                    }
                    Button("Nil Crash") {
                        HelperTools.flushLogs(withTimeout: 0.100)
                        let crasher:Int? = nil
                        print(crasher!)
                    }
                }.foregroundColor(.red)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.interpolatedWindowBackground)
    }
}

struct DebugView: View {
    @StateObject private var overlay = LoadingOverlayState()
    
    var body: some View {
        TabView {
            LogFilesView()
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Logs")
                }
            UDPConfigView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("UDP Logger")
                }
            CrashTestingView()
                .tabItem {
                    Image(systemName: "bolt.fill")
                    Text("Crash Testing")
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .addLoadingOverlay(overlay)
        .navigationBarItems(trailing:Button("Reconnect All") {
            showLoadingOverlay(overlay, headline: "Reconnecting", description: "Will log out and reconnect all (connected) accounts.") {
                MLXMPPManager.sharedInstance().reconnectAll()
                return after(seconds:3.0)
            }
        })
    }
}

#Preview {
    NavigationStack {
        DebugView()
    }
}
