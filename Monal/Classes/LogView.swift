//
//  LogView.swift
//  Monal
//
//  Created by Zain Ashraf on 3/23/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import monalxmpp

extension Binding where Value == Bool {
  static func mappedTo<Wrapped>(bindingToOptional: Binding<Wrapped?>) -> Binding<Bool> {
    Binding<Bool>(
      get: { bindingToOptional.wrappedValue != nil },
      set: { newValue in if !newValue { bindingToOptional.wrappedValue = nil } }
    )
  }
}

struct LogFilesView: View {
    @State private var sortedLogFileInfos: [DDLogFileInfo] = []
    @State private var dbFileURL: URL?
    @State private var showShareSheet:Bool = false
    @State private var fileURL: URL?
    
    var body: some View {
        List {
            Section(header: Text("Log Files")) {
                ForEach(sortedLogFileInfos, id: \.self) { logFileInfo in
                    Text(logFileInfo.fileName)
                        .onTapGesture {
                            fileURL=URL(fileURLWithPath: logFileInfo.filePath)
                        }
                }
            }
            Section(header: Text("Database File")) {
                if let dbFileURL = dbFileURL {
                    Text(dbFileURL.lastPathComponent)
                        .onTapGesture {
                            self.fileURL=dbFileURL
                        }
                }
            }
        }
        .onAppear {
            if let sortedLogFileInfos = HelperTools.fileLogger?.logFileManager.sortedLogFileInfos {
                self.sortedLogFileInfos=sortedLogFileInfos
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

class LogDefaultDB: ObservableObject {
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
    @ObservedObject var defaultDB: LogDefaultDB
    
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
            Button(action: {
                DispatchQueue.global(qos: .default).async(execute: {
                    HelperTools.flushLogs(withTimeout: 0.100)
                    let handler = MLHandler(delegate: self, handlerName: "IDontKnowThis", andBoundArguments: [:])
                    handler.call(withArguments: nil)
                })
            }, label: {
                Text("Try to call unknown handler method")
            })
            Button(action: {
                HelperTools.flushLogs(withTimeout: 0.100)
                let delegate: AnyClass? = NSClassFromString("MonalAppDelegate")
                print(delegate.unsafelyUnwrapped.audiovisualTypes())
                
            }, label: {
                Text("Bad Access Crash")
            })
            Button(action: {
                HelperTools.flushLogs(withTimeout: 0.100)
                assert(false)
            }, label: {
                Text("Assertion Crash")
            })
            Button(action: {
                HelperTools.flushLogs(withTimeout: 0.100)
                fatalError("fatalError_example")
            }, label: {
                Text("Fatal Error Crash")
            })
            Button(action: {
                HelperTools.flushLogs(withTimeout: 0.100)
                let crasher:Int? = nil
                print(crasher!)
            }, label: {
                Text("Nil Crash")
            })
            Spacer()
        }
        .foregroundColor(.red)
        .font(.title)
    }
}

struct LogView: View {
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
                    Text("UDP Config")
                }
            CrashTestingView()
                .tabItem {
                    Image(systemName: "bolt.fill")
                    Text("Crash Testing")
                }
        }
        .addLoadingOverlay(overlay)
        .onAppear(perform: {
            hideLoadingOverlay(overlay)
        })
        .onChange(of:isReconnecting) { _ in
            if isReconnecting{
                showLoadingOverlay(overlay, headline: "Reconnecting", description: "Will logout and reconnect any connected accounts.")
            }
            else{
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
        LogView()
    }
}
