//
//  BackgroundSettings.swift
//  Monal
//
//  Created by Thilo Molitor on 14.11.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

@ViewBuilder
func title(contact: ObservableKVOWrapper<MLContact>?) -> some View {
    if let contact = contact {
        Text("Select a background to display behind conversations with \(contact.contactDisplayName as String)")
    } else {
        Text("Select a default background to display behind conversations.")
    }
}

struct BackgroundSettings: View {
    //>= ios 16
    /*
    @State private var selectedItem: PhotosPickerItem? = nil
    */
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
                        Button(action: {
#if targetEnvironment(macCatalyst)
                            let picker = DocumentPickerViewController(
                                supportedTypes: [UTType.image], 
                                onPick: { url in
                                    if let imageData = try? Data(contentsOf: url) {
                                        if let loadedImage = UIImage(data: imageData) {
                                                self.inputImage = loadedImage
                                        }
                                    }
                                },
                                onDismiss: {
                                    //do nothing on dismiss
                                }
                            )
                            UIApplication.shared.windows.first?.rootViewController?.present(picker, animated: true)
#else
                            showingImagePicker = true
#endif
                        }) {
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
                                            .applyClosure { view in
                                                if #available(iOS 15, *) {
                                                    view
                                                        .symbolRenderingMode(.palette)
                                                        .foregroundStyle(.white, .red)
                                                } else {
                                                    view.foregroundColor(.red)
                                                }
                                            }
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
                        .sheet(isPresented:$showingImagePicker) {
                            ImagePicker(image:$inputImage)
                        }
                        
                        //>= ios 16
                        /*
                        PhotosPicker(selection:$selectedItem, matching:.images, photoLibrary:.shared()) {
                            if let inputImage = inputImage {
                                ZStack(alignment: .topLeading) {
                                    HStack(alignment: .center) {
                                        Image(uiImage:inputImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                    Button(action: {
                                        self.inputImage = nil
                                    }, label: {
                                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                                    })
                                    .buttonStyle(.borderless)
                                    .offset(x: -7, y: -7)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                Text("Select background image")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .onChange(of:selectedItem) { newItem in
                            Task {
                                // Retrive selected asset in the form of Data
                                if let data = try? await newItem?.loadTransferable(type:Data.self) {
                                    MLImageManager.sharedInstance().saveBackgroundImageData(data, forContact:nil)
                                }
                            }
                        }
                        */
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
