//
//  LogView.swift
//  Monal
//
//  Created by Zain Ashraf on 3/23/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//



struct LogFilesView: View {
    @State private var sortedLogFileInfos: [DDLogFileInfo] = []
    @State private var dbFileURL: URL?
    @State private var showShareSheet:Bool = false
    @State private var fileURL: URL?
    
    var body: some View {
        List {
            Section(header: Text("Log Files")) {
                ForEach(sortedLogFileInfos, id: \.self) { logFileInfo in
                    Button(logFileInfo.fileName) {
                        fileURL = URL(fileURLWithPath: logFileInfo.filePath)
                    }
                }
            }
            Section(header: Text("Database File")) {
                if let dbFileURL = dbFileURL {
                    Button(dbFileURL.lastPathComponent) {
                        self.fileURL=dbFileURL
                    }
                }
            }
        }
        .onAppear {
            if let sortedLogFileInfos = HelperTools.fileLogger?.logFileManager.sortedLogFileInfos {
                self.sortedLogFileInfos = sortedLogFileInfos
            }
            if let dbFile = DataLayer.sharedInstance().exportDB() {
                dbFileURL = URL(fileURLWithPath: dbFile)
            }
        }
        .sheet(isPresented:Binding.mappedTo(bindingToOptional: $fileURL)) {
            if let fileURL = fileURL {
                ActivityViewController(activityItems: [fileURL])
            }
        }
    }
}

class DebugDefaultDB: ObservableObject {
    @defaultsDB("udpLoggerEnabled")
    var udpLoggerEnabled:Bool
    
    @defaultsDB("udpLoggerPort")
    var udpLoggerPort: String
    
    @defaultsDB("udpLoggerHostname")
    var udpLoggerHostname: String
    
    @defaultsDB("udpLoggerKey")
    var udpLoggerKey: String
}

struct UDPConfigView: View {
    @ObservedObject var defaultDB: DebugDefaultDB
    
    var body: some View {
        Form {
            TextField("Hostname/IP", text: $defaultDB.udpLoggerHostname)
                .textFieldStyle(.roundedBorder)
            TextField("Port", text: $defaultDB.udpLoggerPort)
                .textFieldStyle(.roundedBorder)
            TextField("AES Encryption Key", text: $defaultDB.udpLoggerKey)
                .textFieldStyle(.roundedBorder)
            Toggle("Enable UDP Logger", isOn: $defaultDB.udpLoggerEnabled)
        }
    }
}

struct CrashTestingView: View {
    var body: some View {
        VStack(spacing: 25){
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
            Spacer()
        }
        .foregroundColor(.red)
        .font(.title)
    }
}

struct DebugView: View {
    @State private var isReconnecting: Bool = false
    @StateObject private var overlay = LoadingOverlayState()
    var body: some View {
        TabView {
            LogFilesView()
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Logs")
                }
            UDPConfigView(defaultDB: LogDefaultDB())
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
        .addLoadingOverlay(overlay)
        .onChange(of: isReconnecting) { _ in
            if isReconnecting{
                showLoadingOverlay(overlay, headline: "Reconnecting", description: "Will log out and reconnect all (connected) accounts.")
            } else {
                hideLoadingOverlay(overlay)
            }
        }
        .navigationBarItems(trailing:
                                Button("Reconnect All"){
            isReconnecting = true
            MLXMPPManager.sharedInstance().reconnectAll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                isReconnecting = false
            }
        }
        )
    }
}

#Preview {
    NavigationView {
        DebugView()
    }
}
