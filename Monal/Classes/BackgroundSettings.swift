//
//  BackgroundSettings.swift
//  Monal
//
//  Created by Thilo Molitor on 14.11.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

//swiftui is somehow needed to let the PhotosUI import succeed, even if it's already imported by SwiftuiHelpers.swift using @_exported
import SwiftUI
import PhotosUI

@ViewBuilder
func title(contact: ObservableKVOWrapper<MLContact>?) -> some View {
    if let contact = contact {
        Text("Select a background to display behind conversations with \(contact.contactDisplayName as String)")
    } else {
        Text("Select a default background to display behind conversations.")
    }
}

struct BackgroundSettings: View {
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var showingImagePicker = false
    @State private var inputImage: UIImage?
    let contact: ObservableKVOWrapper<MLContact>?
    
    init(contact: ObservableKVOWrapper<MLContact>?) {
        self.contact = contact
        _inputImage = State(initialValue:MLImageManager.sharedInstance().getBackgroundFor(self.contact?.obj))
        
    }
    
    var body: some View {
        VStack {
            Form {
                Section(header:title(contact:contact)) {
                    VStack(spacing: 20) {
                        Spacer().frame(height: 0)
                        
                        PhotosPicker(selection:$selectedItem, matching:.images, photoLibrary:.shared()) {
                            if let inputImage = inputImage {
                                HStack(alignment: .center) {
                                    Image(uiImage:inputImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .addTopRight {
                                    Button(action: {
                                        self.inputImage = nil
                                    }, label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .resizable()
                                            .frame(width: 32.0, height: 32.0)
                                            .accessibilityLabel(Text("Remove Background Image"))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .red)
                                    })
                                    .buttonStyle(.borderless)
                                    .offset(x: 12, y: -12)
                                }
                            } else {
                                Text("Select background image")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .accessibilityLabel(Text("Change Background Image"))
                        .onChange(of:selectedItem) { newItem in
                            Task {
                                // Retrive selected asset in the form of Data
                                if let data = try? await newItem?.loadTransferable(type:Data.self) {
                                    if let loadedImage = UIImage(data: data) {
                                        self.inputImage = loadedImage
                                    } else {
                                        self.inputImage = nil
                                    }
                                }
                            }
                        }
                        
                        Spacer().frame(height: 0)
                    }
                }
            }
        }
        .navigationBarTitle(contact != nil ? Text("Chat Background") : Text("Default Background"))
        .onChange(of:inputImage) { _ in
            MLImageManager.sharedInstance().saveBackgroundImageData(inputImage?.pngData(), for:self.contact?.obj)
        }
    }
}

struct BackgroundSettings_Previews: PreviewProvider {
    static var previews: some View {
        BackgroundSettings(contact:nil)
    }
}
