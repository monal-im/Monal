//
//  ChatView.swift
//  Monal
//
//  Created by Thilo Molitor on 05.09.24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import FrameUp
import ExyteChat
typealias ExyteChatView = ExyteChat.ChatView


/*
struct MonalViewDefaults: ViewModifier {
    @Binding public var alertPrompt: AlertPrompt?
    
    public func body(content: Content) -> some View {
        content
            //TODO: modernize alert prompt usage in all other swiftui files to be in line with this implementation here
            //TODO: e.g. non-hardcoded dismiss button text and usage of optionalMappedToBool and dismissCallback
            .alert(isPresented: $alertPrompt.optionalMappedToBool()) {
                let callback = alertPrompt!.dismissCallback
                return Alert(title: alertPrompt!.title, message: alertPrompt!.message, dismissButton:.default(alertPrompt!.dismissLabel, action: {
                    if let callback = callback {
                        callback()
                    }
                }))
            }
    }
}

private struct AssociatedMonalViewKeys {
    static var AlertPromptKey = "ml_alertPromptKey"
}

extension View {
    func addMonalViewDefaults() -> some View {
        //see https://medium.com/@marcosantadev/stored-properties-in-swift-extensions-615d4c5a9a58
        modifier(MonalViewDefaults(alertPrompt:Binding(
            get: {
                print("Getter called...")
                return AlertPrompt(
                    title: Text("No OMEMO keys found"),
                    message: Text("This contact may not support OMEMO encrypted messages. Please try to enable encryption again in a few seconds, if you think this is wrong."),
                    dismissLabel: Text("Disable Encryption")
                )
//                 guard let value = objc_getAssociatedObject(self, &AssociatedMonalViewKeys.AlertPromptKey) as? AlertPrompt else {
//                     return nil
//                 }
//                 return value
            },
            set: {
                print("Setting: \(String(describing:$0))")
                if let value = $0 {
                    objc_setAssociatedObject(self, &AssociatedMonalViewKeys.AlertPromptKey, value, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                } else {
                    objc_setAssociatedObject(self, &AssociatedMonalViewKeys.AlertPromptKey, nil, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                }
            }
        )))
    }
}

protocol MonalView: View {
    associatedtype Content: View
    @ViewBuilder var content: Self.Content { get }
}

extension MonalView {
    var body: some View {
        content
            .addMonalViewDefaults()
    }
    
    func showAlert(_ prompt: AlertPrompt) {
        objc_setAssociatedObject(self, &AssociatedMonalViewKeys.AlertPromptKey, prompt, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        content.id(UUID())
    }
}
*/

class ChatViewDefaultsDB: ObservableObject {
    @defaultsDB("SendLastChatState")
    var sendLastChatState: Bool

    @defaultsDB("showKeyboardOnChatOpen")
    var showKeyboardOnChatOpen: Bool
}

struct ChatView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var chatViewDefaultsDB = ChatViewDefaultsDB()
    
    private var account: xmpp
    @StateObject var voipProcessor: ObservableKVOWrapper<MLVoIPProcessor>
    @StateObject var contact: ObservableKVOWrapper<MLContact>
    @State private var selectedContactForContactDetails: ObservableKVOWrapper<MLContact>?
    @State private var alertPrompt: AlertPrompt?
    @State private var confirmationPrompt: ConfirmationPrompt?
    @StateObject private var overlay = LoadingOverlayState()
    @State private var moderationReason = "Spam"
    @State private var isEditingReason = false
    @State private var blockOnModeration = true
    @State private var messageToModerate: MLMessage?
    // The initial value must not be nil. Otherwise background image rendering won't work correctly.
    // The actual initialization happens in onAppear. It can safely be nil then.
    @State private var backgroundImage: UIImage? = UIImage(systemName: "circle")
    @State var messages: [ChatViewMessage] = []
    @State var queuedNewMessages: [ChatViewMessage] = []
    @State private var voiceRequests: [[String: AnyObject]] = []
    @State private var isLoadingMamHistory = false
    @State private var isUploadingFile = false
    @State private var messageInsertionTimer: Timer?
    @State private var ownRole = kMucRoleNone
    @State private var inputText = ""
    @State private var oldInputText = ""
    @State private var isTyping = false
    @State private var typingTimer: Timer?

    init(contact: ObservableKVOWrapper<MLContact>) {
        _contact = StateObject(wrappedValue:contact)
        _voipProcessor = StateObject(wrappedValue:ObservableKVOWrapper((UIApplication.shared.delegate as! MonalAppDelegate).voipProcessor!))
        account = contact.obj.account!
    }

    enum MessageAction: MessageMenuAction {
        case copy, edit, retract, moderate, delete, resend

        func title() -> String {
            switch self {
                case .copy:
                    "Copy"
                case .edit:
                    "Edit"
                case .retract:
                    "Retract"
                case .moderate:
                    "Moderate"
                case .delete:
                    "Delete Locally"
                case .resend:
                    "Resend"
            }
        }

        func icon() -> Image {
            switch self {
                case .copy:
                    Image(systemName: "doc.on.doc")
                case .edit:
                    if #available(iOS 18.0, macCatalyst 18.0, *) {
                        Image(systemName: "bubble.and.pencil")
                    } else {
                        Image(systemName: "square.and.pencil")
                    }
                case .retract, .moderate:
                    Image(systemName: "arrow.uturn.backward.circle")
                case .delete:
                    Image(systemName: "trash")
                case .resend:
                    Image(systemName: "paperplane")
            }
        }

        static func menuItems(for message: ExyteChat.Message) -> [MessageAction] {
            let mlMessage = (message as! ChatViewMessage).innerMessage.obj
            let contact = mlMessage.chatContact
            let account = contact.account!
            if mlMessage.retracted {
                return [.delete]
            }
            if case .error = message.status {
                return [.resend, .delete]
            }
            var availableActions: [MessageAction] = []
            if message.hasText {
                availableActions.append(.copy)
            }

            if !mlMessage.inbound && DataLayer.sharedInstance().checkLMCEligible(mlMessage.messageDBId, encrypted: mlMessage.encrypted || contact.isEncrypted, historyBaseID: nil) {
                availableActions.append(.edit)
            }

            if !mlMessage.inbound && (!mlMessage.isMuc || mlMessage.stanzaId != nil) {
                availableActions.append(.retract)
            }
            else if mlMessage.isMuc && mlMessage.stanzaId != nil && kMucRoleModerator.isEqual(DataLayer.sharedInstance().getOwnRole(inGroupOrChannel: contact)) && account.mucProcessor.getRoomFeatures(forMuc: contact.contactJid).contains("urn:xmpp:message-moderate:1") {
                availableActions.append(.moderate)
            } else {
                availableActions.append(.delete)
            }

            return availableActions
        }
    }

    private func showCannotEncryptAlert(_ show: Bool) {
        if show {
            DDLogVerbose("Showing cannot encrypt alert...")
            alertPrompt = AlertPrompt(
                title: Text("Encryption Not Supported"),
                message: Text("This contact does not appear to have any devices that support encryption, please try again later if you think this is wrong."),
                dismissLabel: Text("Close")
            )
        } else {
            alertPrompt = nil
        }
    }
    
    private func showShouldDisableEncryptionConfirmation(_ show: Bool) {
        if show {
            DDLogVerbose("Showing should disable encryption confirmation...")
            confirmationPrompt = ConfirmationPrompt(
                title: Text("Disable encryption?"),
                message: Text("Do you really want to disable encryption for this contact?"),
                buttons: [
                    .cancel(
                        Text("No, keep encryption activated"),
                        action: { }
                    ),
                    .destructive(
                        Text("Yes, deactivate encryption"),
                        action: {
                            contact.obj.toggleEncryption(false)
                        }
                    )
                ]
            )
        } else {
            confirmationPrompt = nil
        }
    }
    
    private func checkOmemoSupport(withAlert showWarning: Bool) {
#if !DISABLE_OMEMO
        if DataLayer.sharedInstance().isAccountEnabled(contact.accountID) {
            var omemoDeviceForContactFound = false
            if !contact.isMuc {
                omemoDeviceForContactFound = account.omemo.knownDevices(forAddressName:contact.contactJid).count > 0
            } else {
                omemoDeviceForContactFound = false
                for participant in DataLayer.sharedInstance().getMembersAndParticipants(ofMuc:contact.contactJid, forAccountID:contact.accountID) {
                    if let participant_jid = participant["participant_jid"] as? String {
                        omemoDeviceForContactFound = omemoDeviceForContactFound || account.omemo.knownDevices(forAddressName:participant_jid).count > 0
                    } else if let participant_jid = participant["member_jid"] as? String {
                        omemoDeviceForContactFound = omemoDeviceForContactFound || account.omemo.knownDevices(forAddressName:participant_jid).count > 0
                    }
                    if omemoDeviceForContactFound {
                        break
                    }
                }
            }
            hideLoadingOverlay(overlay)
            if !omemoDeviceForContactFound && contact.isEncrypted {
                if HelperTools.isContactBlacklistedForEncryption(contact.obj) {
                    // this contact was blacklisted for encryption
                    // --> disable it
                    contact.obj.toggleEncryption(false)
                } else if contact.isMuc && contact.mucType != kMucTypeGroup {
                    // a channel type muc has OMEMO encryption enabled, but channels don't support encryption
                    // --> warn user about this
                    DDLogWarn("Showing alert because omemo is suddenly impossible since group changed to channel: \(self.contact)");
                    confirmationPrompt = ConfirmationPrompt(
                        title: Text("Group suddenly changed to public channel!"),
                        message: Text("This chat suddenly changed from an encrypted private group to an unencrypted public channel! Please contact the administrator of that group/channel if you think this is wrong."),
                        buttons: [
                            .default(
                                Text("Keep encryption enabled"),
                                //don't change anything, just close the alert
                                action: { }
                            ),
                            .destructive(
                                Text("Disable encryption. This is dangerous!"),
                                action: {
                                    contact.obj.toggleEncryption(false)
                                }
                            )
                        ]
                    )
                } else if !contact.isMuc || (contact.isMuc && contact.mucType == kMucTypeGroup) {
                    if showWarning {
                        DDLogWarn("Showing omemo not supported alert for: \(self.contact)")
                        alertPrompt = AlertPrompt(
                            title: Text("No OMEMO keys found"),
                            message: Text("This contact may not support OMEMO encrypted messages. Please try to enable encryption again in a few seconds, if you think this is wrong."),
                            dismissLabel: Text("Disable Encryption")
                        ) {
                            contact.obj.toggleEncryption(false)
                        }
                    } else {
                        DDLogInfo("Trying to fetch omemo keys for: \(self.contact)")

                        // we won't do this twice, because the user won't be able to change isEncrypted to YES,
                        // unless we have omemo devices for that contact
                        showPromisingLoadingOverlay(overlay, headlineView:Text("Loading OMEMO keys"), descriptionView:Text("")).done {
                            // request omemo devicelist
                            account.omemo.subscribeAndFetchDevicelistIfNoSessionExists(forJid:contact.contactJid)
                        }
                    }
                }
            }
        }
#endif
    }

    private func loadChatBackground() {
        var background: UIImage? = MLImageManager.sharedInstance().getBackgroundFor(self.contact.obj)
        // Use the default background if this contact does not have its own
        if background == nil {
            background = MLImageManager.sharedInstance().getBackgroundFor(nil)
        }
        self.backgroundImage = background
    }

    private func sendChatState(isTyping: Bool) {
        // Do not send when the user disabled the feature
        guard chatViewDefaultsDB.sendLastChatState else {
            return
        }

        // Changed state? --> send typing notification
        if isTyping != self.isTyping {
            DDLogVerbose("Sending chatstate isTyping=\(isTyping)")
            MLXMPPManager.sharedInstance().sendChatState(isTyping, to:self.contact.obj)
        }

        // Set internal state
        self.isTyping = isTyping

        // Cancel old timer if existing
        typingTimer?.invalidate()

        // Start new timer if we are currently typing
        if isTyping {
            typingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                // No typing interaction in 5 seconds? --> send out active chatstate (e.g. typing ended)
                if self.isTyping {
                    self.isTyping = false
                    DDLogVerbose("Sending chatstate isTyping=false");
                    MLXMPPManager.sharedInstance().sendChatState(false, to:self.contact.obj)
                }
            }
        }
    }

    private func findOldestStanzaId() -> String? {
        //not all messages in history db have a stanzaId (messages sent by this monal instance won't have one for example)
        //--> search for the oldest message having a stanzaId and use that one
        for msg in self.messages {
            if msg.innerMessage.obj.stanzaId != nil {
                DDLogVerbose("Found oldest stanzaId in currently displayed messages: \(String(describing:msg.innerMessage.obj.stanzaId))")
                return msg.innerMessage.stanzaId
            }
        }

        //history database for this contact is completely empty, use global last stanza id for this mam archive
        if self.contact.isMuc {
            return DataLayer.sharedInstance().lastStanzaId(forMuc:self.contact.contactJid, andAccount:self.account.accountID)
        }
        else {
            return DataLayer.sharedInstance().lastStanzaId(forAccount:self.account.accountID);
        }
    }

    private func loadHistory() {
        guard !self.isLoadingMamHistory else {
            DDLogDebug("Not going to load more history because a backscrolling mam query is ongoing for this chat")
            // Don't allow concurrent backscrolling mam fetches.
            // And don't allow loading history from the DB while an mam query is ongoing;
            // this prevents potential message duplication: if a DB history fetch is triggered after the mam query
            // has written some messages to the DB but before it has returned the results, those messages will be
            // inserted twice in the ChatView.
            return
        }
        var beforeId: NSNumber? = nil
        if !messages.isEmpty {
            beforeId = messages[0].innerMessage.messageDBId
        }
        let oldMessages: [ChatViewMessage] = (DataLayer.sharedInstance().messages(forContact:contact.contactJid, forAccount:contact.accountID, beforeMsgHistoryID:beforeId) as! [MLMessage]).map {ChatViewMessage($0)}
        //insert what we got from the db
        if !oldMessages.isEmpty {
            messages.insert(contentsOf: oldMessages, at:0)
        }

        // if we didn't get enough (or any) messages from the DB, try to get some from MAM
        if oldMessages.count < kMonalBackscrollingMsgCount && !contact.hasReachedMamArchiveTop {
            self.isLoadingMamHistory = true

            guard let oldestStanzaId = self.findOldestStanzaId() else {
                DDLogError("Couldn't find a stanzaId to perform a mam query with! (oldestStanzaId is nil)")
                return
            }
            // now try to load more (older) messages from mam
            DDLogVerbose("Loading more messages from mam before stanzaId \(oldestStanzaId)")
            firstly {
                self.account.setMAMQueryMostRecentFor(self.contact.obj, before: oldestStanzaId)
            }
            .done { returnedMessages in
                let returnedMessages = returnedMessages as! [MLMessage]
                if returnedMessages.isEmpty {
                    DDLogVerbose("Reached the top of the mam archive for \(self.contact.obj.contactJid)")
                    // Don't block the main thread while writing to the db
                    DispatchQueue.global(qos: .default).async {
                        contact.obj.markReachedMamArchiveTop()
                    }
                } else {
                    DDLogVerbose("Got backscrolling mam response: \(returnedMessages.count) messages: \(String(describing:returnedMessages))")
                    // When backscrolling in 1-1 chats, the oldest stanzaId may not correspond to the earliest
                    // message we have, because messages we send don't have a stanzaId => There's a risk of
                    // getting duplicate messages in the messages array => we need to deduplicate.
                    self.messages = OrderedSet(returnedMessages.map {ChatViewMessage($0)} + self.messages).elements
                }
            }
            .catch { error in
                alertPrompt = AlertPrompt(
                    title: Text("Could not fetch messages"),
                    message: Text(error.localizedDescription),
                    dismissLabel: Text("Close")
                )
            }
            .finally {
                self.isLoadingMamHistory = false
            }
        }
    }

    private func uploadAndSendFile(_ localFileURL: URL?) async {
        guard let localFileURL = localFileURL else {
            DDLogError("Couldn't get file location in order to upload it!")
            return
        }
        self.isUploadingFile = true
        do {
            let (url, mimeType, size) = try await MLFiletransfer.uploadFile(localFileURL, onAccount: self.account, withEncryption: self.contact.isEncrypted)
            await MainActor.run {
                guard let newMLMessage = MLXMPPManager.sharedInstance().sendMessageAndAddToHistory(message: url, havingType: kMessageTypeFiletransfer, toContact: self.contact.obj, isEncrypted: self.contact.isEncrypted, uploadInfo: ["mimeType": mimeType, "size": size]) else {
                    self.isUploadingFile = false
                    return
                }
                messages.append(ChatViewMessage(newMLMessage))
            }
        } catch {
            DDLogError("Couldn't upload file! error:  \(error.localizedDescription)")
            alertPrompt = AlertPrompt(
                title: Text("Could not upload file"),
                message: Text(error.localizedDescription),
                dismissLabel: Text("Close")
            )
        }
        self.isUploadingFile = false
    }

    var body: some View {
        ExyteChatView(messages: messages, chatType: .conversation, replyMode: .quote) { draft in
            if !draft.medias.isEmpty || draft.recording != nil {
                Task {
                    if draft.recording != nil {
                        await uploadAndSendFile(draft.recording!.url)
                    }
                    for media in draft.medias {
                        let localFileURL = await media.getURL()
                        await uploadAndSendFile(localFileURL)
                    }
                }
            }
            if !draft.text.isEmpty {
                guard let newMLMessage = MLXMPPManager.sharedInstance().sendMessageAndAddToHistory(message: draft.text, havingType: kMessageTypeText, toContact: self.contact.obj, isEncrypted: self.contact.isEncrypted, uploadInfo: nil) else {
                    return
                }
                messages.append(ChatViewMessage(newMLMessage))
                sendChatState(isTyping: false)
                // Clear the draft to show the newly sent message in active chats
                DataLayer.sharedInstance().saveMessageDraft(self.contact.contactJid, forAccount:self.account.accountID, withComment:"")
            }
        } messageMenuAction: { (action: MessageAction, defaultActionClosure, message) in
            let mlMessage = (message as! ChatViewMessage).innerMessage.obj
            let messageDBId = mlMessage.messageDBId
            switch action {
                case .copy:
                    defaultActionClosure(message, .copy)
                case .edit:
                    defaultActionClosure(message, .edit { editedText in
                        Task { @MainActor in
                            self.account.sendMessage(editedText,
                                                     to: self.contact.obj,
                                                     isEncrypted: self.contact.isEncrypted || mlMessage.encrypted,
                                                     isUpload: false,
                                                     andMessageId: UUID().uuidString,
                                                     withLMCId: mlMessage.messageId)

                            // Don't block the main thread while writing to the DB
                            await Task.detached(priority: .userInitiated) {
                                DataLayer.sharedInstance().updateMessageHistory(messageDBId, withText: editedText)
                            }.value

                            MLNotificationQueue.current().post(
                                name: Notification.Name(kMonalUpdatedMessageNotice),
                                object: self.account,
                                userInfo: [
                                    "message": mlMessage,
                                    "contact": self.contact.obj,
                                    "LMCReplaced": true,
                                    "correctedText": editedText,
                                    "reactionsUpdate": false
                                ]
                            )
                        }
                    })
                case .retract:
                    self.account.retractMessage(mlMessage)
                case .moderate:
                    messageToModerate = mlMessage
                case .delete:
                    Task { @MainActor in
                        await Task.detached(priority: .userInitiated) {
                            mlMessage.deleteLocally()
                        }.value

                        self.messages.removeAll(where: {$0.id == message.id})
                        // Update active chats if necessary
                        MLNotificationQueue.current().post(
                            name: Notification.Name(kMonalContactRefresh),
                            object: self.account,
                            userInfo: ["contact": self.contact.obj]
                        )
                    }
                case .resend:
                    // Explicitly schedule this on the main thread, to ensure the update to confirmationPrompt happens.
                    // This is needed for some reason, despite this code being already on the main thread.
                    Task { @MainActor in
                        self.confirmationPrompt = ConfirmationPrompt(
                            title: Text("Retry sending message?"),
                            message: Text("This message failed to send (\(mlMessage.errorType ?? "unknown error")): \(mlMessage.errorReason ?? "unknown reason")"),
                            buttons: [
                                .default(
                                    Text("Retry"),
                                    action: {
                                        Task { @MainActor in
                                            await Task.detached(priority: .userInitiated) {
                                                DataLayer.sharedInstance().clearError(ofMessageId: mlMessage.messageId)
                                            }.value

                                            mlMessage.errorType = ""
                                            mlMessage.errorReason = ""
                                            let isUpload = mlMessage.messageType == kMessageTypeFiletransfer
                                            let isEncrypted = mlMessage.encrypted || self.contact.isEncrypted
                                            self.account.sendMessage(mlMessage.messageText,
                                                                     to: self.contact.obj,
                                                                     isEncrypted: isEncrypted,
                                                                     isUpload: isUpload,
                                                                     andMessageId: mlMessage.messageId)
                                            MLNotificationQueue.current().post(
                                                name: Notification.Name(kMLMessageSentToContact),
                                                object: self.account,
                                                userInfo: ["contact": self.contact.obj]
                                            )
                                        }
                                    }
                                ),
                                .cancel(
                                    Text("Cancel"),
                                    action: { }
                                )
                            ]
                        )
                    }
            }
        }
        /*
        .swipeActions(edge: .leading, performsFirstActionWithFullSwipe: true, items: [
            SwipeAction(action: { (message, defaultActionClosure) in
                defaultActions(message, .reply)
            }, activeFor: { !$0.user.isCurrentUser }, background: .blue) {
                VStack {
                    Image(systemName: "arrowshape.turn.up.left")
                        .imageScale(.large)
                        .foregroundStyle(.white)
                        .frame(height: 30)
                    Text("Reply")
                        .foregroundStyle(.white)
                        .font(.footnote)
                }
            }
        ])
        */
        .onMessageReaction(didReactTo: { message, reaction in
            let mlMessage = (message as! ChatViewMessage).innerMessage.obj
            switch reaction.type {
                case .emoji(let emoji):
                    var currentReactions: NSMutableOrderedSet = []
                    for reactionsInfo in mlMessage.reactions {
                        if reactionsInfo.contact.isSelf {
                            currentReactions = NSMutableOrderedSet(orderedSet: reactionsInfo.reactions)
                        }
                    }
                    if currentReactions.contains(emoji) {
                        currentReactions.remove(emoji)
                    } else {
                        currentReactions.add(emoji)
                    }
                    self.account.sendReactions(currentReactions, for:mlMessage)
            }
        }, canReactTo: { message in
            //don't allow reactions in mucs without occupant-id support
            let mlMessage = (message as! ChatViewMessage).innerMessage.obj
            let retval = !mlMessage.isMuc || 
                (mlMessage.stanzaId != nil && self.account.mucProcessor.getRoomFeatures(forMuc:mlMessage.chatContact.contactJid).contains("urn:xmpp:occupant-id:0"))
            DDLogDebug("Checking if we can react to: \(String(describing:mlMessage)) --> \(String(describing:retval))")
            return retval
        })
        .autoFocusTextInputOnChatOpen(chatViewDefaultsDB.showKeyboardOnChatOpen)
        .showUsername(contact.isMuc)
        .tapAvatarClosure { user, _ in
            inputText += "\(user.name), "
        }
        .linkPreviewsEnabled(false) //disabled for now due to https://github.com/exyte/Chat/issues/208
        .inputViewText($inputText)
        .enableLoadMore(offset: 10) {
            loadHistory()
        }
        .chatTheme(
            ChatTheme(
                images: self.backgroundImage != nil ?
                    .init(background: ChatTheme.Images.Background(Image(uiImage: self.backgroundImage!))) :
                    .init()
            )
        )
        .sheet(item: $selectedContactForContactDetails) { selectedContact in
            AnyView(AddTopLevelNavigation(withDelegate:nil, to:ContactDetails(delegate:nil, contact:selectedContact)))
        }
        //TODO: modernize action sheet usage in all other swiftui files to be in line with this implementation here
        //TODO: e.g. same usage like alert prompt below
        .actionSheet(isPresented: $confirmationPrompt.optionalMappedToBool()) {
            ActionSheet(title: confirmationPrompt!.title, message: confirmationPrompt!.message, buttons: confirmationPrompt!.buttons)
        }
        //TODO: modernize alert prompt usage in all other swiftui files to be in line with this implementation here
        //TODO: e.g. non-hardcoded dismiss button text and usage of optionalMappedToBool and dismissCallback
        //somehow the order of alert modifiers is important: they have to come after all sheet modifiers
        .alert(isPresented: $alertPrompt.optionalMappedToBool()) {
            let callback = alertPrompt!.dismissCallback
            return Alert(title: alertPrompt!.title, message: alertPrompt!.message, dismissButton:.default(alertPrompt!.dismissLabel, action: {
                if let callback = callback {
                    callback()
                }
            }))
        }
        .richAlert(isPresented: $messageToModerate, title:Text("Moderating message")) { mlMessage in
            VStack(alignment: .leading) {
                Text("Enter the moderation reason:")
                TextField(NSLocalizedString("Spam", comment: "placeholder for the message moderation reason"), text: $moderationReason, onEditingChanged: { isEditingReason = $0 })
                .submitLabel(.continue)
                .addClearButton(isEditing: isEditingReason, text: $moderationReason)
                
                if let _ = mlMessage.participantJid {
                    Toggle(isOn: $blockOnModeration) {
                        Text("Block this user")
                    }
                }
            }.textFieldStyle(.roundedBorder)
        } buttons: { mlMessage in
            Button(action: {
                let promise = showPromisingLoadingOverlay(self.overlay, headline: "Retracting message", description: "") {
                    self.account.moderateMessage(mlMessage, withReason: moderationReason)
                    // Reset moderationReason to its default value only after the moderation was sent
                    // (`promise` executes after the rest of the `action` closure. So we don't want to
                    // reset moderationReason when the alert is dismissed like other State variables,
                    // because the moderation isn't sent yet at that point.)
                    moderationReason = "Spam"
                    return Guarantee.value(())
                }
                if blockOnModeration, let participantJid = mlMessage.participantJid {
                    let _ = promise.done { _ in
                        showPromisingLoadingOverlay(self.overlay, headlineView: Text("Blocking user"), descriptionView: Text("Blocking \(participantJid)")) {
                            DDLogVerbose("Changing affiliation of \(participantJid) to: \(String(describing:kMucAffiliationOutcast))...")
                            return account.mucProcessor.setAffiliation(kMucAffiliationOutcast, ofUser:participantJid, inMuc:contact.obj.contactJid).toTypedPromise()
                        }.catch { error in
                            alertPrompt = AlertPrompt(
                                title: Text("Error blocking user!"),
                                message: Text(error.localizedDescription),
                                dismissLabel: Text("Close")
                            )
                        }
                    }
                }
                // Reset the State variables (except moderationReason) to their default values, as the alert is dismissed
                messageToModerate = nil
                blockOnModeration = true
            }) {
                Text("Moderate")
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
            }
            
            Button(action: {
                messageToModerate = nil
                moderationReason = "Spam"
                blockOnModeration = true
            }) {
                Text("Cancel")
                    .foregroundColor(.accentColor)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                //make sure to take all space available, otherwise we'll get aligned to the center
                //of the navigation bar instead of the leading edge
                ZStack {
                    Color.clear
                    
                    HStack {
                        Button {
                            selectedContactForContactDetails = contact
                        } label: {
                            HStack {
                                Image(uiImage: contact.avatar)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 35, height: 35)

                                VStack(alignment: .leading, spacing: 0) {
                                    Text(contact.contactDisplayName as String)
                                        .fontWeight(.semibold)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    if (contact.isTyping as Bool) {
                                        Text("Typing...")
                                            .font(.footnote)
                                            .foregroundColor(Color(hex: "AFB3B8"))
                                    } else if let lastInteractionDate:Date = contact.lastInteractionTime {
                                        TimelineView(.periodic(from: lastInteractionDate, by: 60.0)) { _ in
                                            Text(HelperTools.formatLastInteraction(contact.lastInteractionTime))
                                                .font(.footnote)
                                                .foregroundColor(Color(hex: "AFB3B8"))
                                        }
                                    }
                                }
                            }
                        }
                        // When used in the toolbar, the default button style doesn't have any size constraints.
                        // => use a different button style to ensure the truncation of long contact names.
                        .buttonStyle(.borderless)
                        Spacer()
                    }
                }
            }
            
            ToolbarItemGroup(placement: .topBarTrailing) {
                ProgressView()
                    .opacity(isLoadingMamHistory || isUploadingFile ? 1 : 0)

                if ownRole == kMucRoleVisitor {
                    Button {
                        let _ = showPromisingLoadingOverlay(overlay, headline:"Requesting Voice") {
                            Guarantee { $0(contact.obj.account?.mucProcessor.requestVoice(inMuc:contact.obj.contactJid)) }
                        }
                    } label: {
                        Image(systemName: "lightbulb")
                    }
                }
                
                if contact.isMuc && ownRole == kMucRoleModerator && voiceRequests.count > 0 {
                    Button {
                        //TODO: open sheet with voice requests
                    } label: {
                        Image(systemName: "questionmark.bubble")
                    }
                }
                
                if !(contact.isMuc || contact.isSelf) {
                    Button {
                        let activeChats = (UIApplication.shared.delegate as! MonalAppDelegate).activeChats!
                        if voipProcessor.obj.getActiveCall(with:contact.obj) == nil && !DataLayer.sharedInstance().checkCap("urn:xmpp:jingle-message:0", forUser:contact.contactJid, onAccountID:contact.accountID) {
                            confirmationPrompt = ConfirmationPrompt(
                                title: Text("Missing Call Support"),
                                message: Text("Your contact may not support calls. Your call might never reach its destination."),
                                buttons: [
                                    .default(
                                        Text("Try nevertheless"),
                                        action: {
                                            activeChats.call(contact.obj, withUIKitSender:nil)
                                        }
                                    ),
                                    .cancel(
                                        Text("Cancel"),
                                        action: { }
                                    )
                                ]
                            )
                        } else {
                            activeChats.call(contact.obj, withUIKitSender:nil)
                        }
                    } label: {
                        if (voipProcessor.activeCalls as [MLCall]).contains(where:{ $0.isEqual(to:contact.obj) }) {
                            Image(systemName: "phone.connection.fill")
                        } else {
                            Image(systemName: "phone.fill")
                        }
                    }
                }
                
                Button {
                    guard !HelperTools.isContactBlacklistedForEncryption(contact.obj) else {
                        return
                    }
                    if contact.isEncrypted {
                        DDLogVerbose("Showing should disable encryption confirmation...")
                        showShouldDisableEncryptionConfirmation(true)
                    } else {
                        showCannotEncryptAlert(!contact.obj.toggleEncryption(true))
                    }
                } label: {
                    if contact.isEncrypted {
                        Label {
                            Text("Messages are encrypted")
                        } icon: {
                            Image(systemName: "lock.fill")
                        }
                    } else {
                        Label {
                            Text("Messages are NOT encrypted")
                        } icon: {
                            Image(systemName: "lock.open.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
                .disabled(
                    //disable encryption button on unsupported muc types
                    (contact.isMuc && contact.mucType != kMucTypeGroup) ||
                    //disable encryption button for special jids
                    HelperTools.isContactBlacklistedForEncryption(contact.obj)
                )
            }
        }
        .toolbarRole(.editor)       //make sure to never show the title of the previous view in the back bar button
        .canContainExternalLinks()
        .addLoadingOverlay(overlay)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            MLNotificationManager.sharedInstance().currentContact = self.contact.obj
            loadChatBackground()

            checkOmemoSupport(withAlert:false)
            let messageDraft = DataLayer.sharedInstance().loadMessageDraft(self.contact.contactJid, forAccount:self.account.accountID)
            if let messageDraft, !messageDraft.isEmpty {
                self.inputText = messageDraft
            }
            loadHistory()
            if self.contact.obj.isMuc {
                ownRole = DataLayer.sharedInstance().getOwnRole(inGroupOrChannel: contact.obj) ?? kMucRoleNone
                voiceRequests = DataLayer.sharedInstance().getVoiceRequests(forRoom:contact.obj) as! [[String: AnyObject]]
            }
            ChatViewHelpers.refreshCounter(for: self.contact.obj)
        }
        .onDisappear {
            // When the split view is active, selecting different chats results in the old
            // view's onDisappear executing after the new view's onAppear, thus erroneously
            // making currentContact always nil.
            // This if statement ensures currentContact has the correct value.
            if MLNotificationManager.sharedInstance().currentContact == self.contact.obj {
                MLNotificationManager.sharedInstance().currentContact = nil
            }
            messageInsertionTimer?.invalidate()
            sendChatState(isTyping: false)
            DataLayer.sharedInstance().saveMessageDraft(self.contact.contactJid, forAccount:self.account.accountID, withComment:self.inputText)
            // Update active chats to show the new draft
            MLNotificationQueue.current().post(
                name: Notification.Name(kMonalContactRefresh),
                object: self.account,
                userInfo: ["contact": self.contact.obj]
            )
        }
        .onChange(of: inputText) { newValue in
            //TODO: use the new .onChange instead of this workaround once the minimum version is iOS 17.0
            let oldValue = oldInputText
            oldInputText = newValue
            // Don't send a typing notification if the only change is deletion of characters from the end.
            // This results in better UX, and avoids sending a typing notification after the automatic
            // clearing of the input text when sending a message.
            if oldValue.count > newValue.count && oldValue.starts(with: newValue) {
                return
            }
            // Workaround to avoid sending a typing notification when inserting the draft on chat open.
            // Side-effect: if the user pastes from the clipboard while the input text is empty, a typing
            // notification won't be sent unless they type more characters.
            if oldValue.isEmpty && newValue.count > 1 {
                return
            }
            sendChatState(isTyping: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalOmemoFetchingStateUpdate)).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let notificationJid = notification.userInfo?["jid"] as? String {
                if xmppAccount.accountID == contact.accountID && notificationJid == contact.contactJid {
                    DDLogDebug("Got omemo fetching update: \(contact) --> \(String(describing:notification.userInfo))")
                    if let _ = (notification.userInfo?["isFetching"] as? Bool) {
                        //recheck support and show alert if needed
                        DDLogVerbose("Rechecking omemo support with alert, if needed...")
                        checkOmemoSupport(withAlert:true)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalNewMessageNotice)).receive(on: RunLoop.main)) { notification in
            DDLogVerbose("ChatView got new message notice \(String(describing:notification.userInfo))")

            guard let message = notification.userInfo?["message"] as? MLMessage else {
                unreachable("kMonalNewMessageNotice notification without message!")
            }
            if message.isEqual(self.contact.obj) {
                // Don't insert based on delay timestamp because that would make it possible to fake history entries.
                // Insert new messages in batches to work around https://github.com/exyte/Chat/issues/223
                queuedNewMessages.append(ChatViewMessage(message))
                if messageInsertionTimer == nil {
                    messageInsertionTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
                        messages.append(contentsOf: queuedNewMessages)
                        queuedNewMessages.removeAll(keepingCapacity: true)
                        messageInsertionTimer = nil
                    }
                    messageInsertionTimer?.tolerance = 0.04
                }
            }
            ChatViewHelpers.refreshCounter(for: self.contact.obj)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalRefresh)).receive(on: RunLoop.main)) { notification in
            ChatViewHelpers.refreshCounter(for: self.contact.obj)
            voiceRequests = DataLayer.sharedInstance().getVoiceRequests(forRoom:contact.obj) as! [[String: AnyObject]]
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalMucOwnAffiliationOrRoleChanged)).receive(on: RunLoop.main)) { notification in
            guard let mucContact = notification.userInfo?["contact"] as? MLContact else {
                unreachable("kMonalMucOwnAffiliationOrRoleChanged notification without contact!")
            }
            if self.contact.obj.isMuc && mucContact.isEqual(self.contact.obj) {
                voiceRequests = DataLayer.sharedInstance().getVoiceRequests(forRoom:contact.obj) as! [[String: AnyObject]]
                ownRole = DataLayer.sharedInstance().getOwnRole(inGroupOrChannel: contact.obj) ?? kMucRoleNone
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalMucVoiceRequestsUpdated)).receive(on: RunLoop.main)) { notification in
            guard let mucContact = notification.userInfo?["contact"] as? MLContact else {
                unreachable("kMonalMucVoiceRequestsUpdated notification without contact!")
            }
            if mucContact.isEqual(self.contact.obj) {
                voiceRequests = DataLayer.sharedInstance().getVoiceRequests(forRoom:contact.obj) as! [[String: AnyObject]]
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalContactHistoryCleared)).receive(on: RunLoop.main)) { notification in
            DDLogVerbose("ChatView got history cleared notice \(String(describing:notification.userInfo))")
            guard let contact = notification.userInfo?["contact"] as? MLContact else {
                unreachable("Notification without contact")
            }
            if contact.isEqual(self.contact.obj) {
                self.messages = []
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalBackgroundChanged)).receive(on: RunLoop.main)) { notification in
            loadChatBackground()
        }
        .onReceive(Publishers.Merge(
            NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification).receive(on: RunLoop.main),
            NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification).receive(on: RunLoop.main)
        )) { notification in
            DDLogVerbose("ChatView of chat \(contact.obj.contactJid) received \(notification.name.rawValue)")
            sendChatState(isTyping: false)
            DataLayer.sharedInstance().saveMessageDraft(self.contact.contactJid, forAccount:self.account.accountID, withComment:self.inputText)
            // Update active chats to show the new draft
            MLNotificationQueue.current().post(
                name: Notification.Name(kMonalContactRefresh),
                object: self.account,
                userInfo: ["contact": self.contact.obj]
            )
        }
    }
}

class ChatViewMessage: ExyteChat.Message {
    let innerMessage: ObservableKVOWrapper<MLMessage>
    let fileInfo: ObservableKVOWrapper<MLFiletransferInfo>?
    private var subscriptions: Set<AnyCancellable> = Set()
    var text: String {
        if innerMessage.messageType == kMessageTypeFiletransfer, let fileInfo = fileInfo {
            switch(fileInfo.downloadState as DownloadState.RawValue) {
                case DownloadState.complete.rawValue:
                    let mimeType = fileInfo.mimeType as String
                    if mimeType.starts(with: "audio/") || mimeType.starts(with: "image/") || mimeType.starts(with: "video/") {
                        return ""
                    } else {
                        return """
                            [File transfer with a file type that's not yet supported for displaying]
                            \(innerMessage.obj.encrypted ? "" : "Link: \(innerMessage.messageText as String)")
                        """
                    }
                case DownloadState.headers.rawValue:
                    let humanReadableSize = (fileInfo.size as NSNumber).int64Value.formatted(.byteCount(style: .file))
                    return """
                    [File transfer; auto-downloading if the settings allow it...]
                    Size: \(humanReadableSize)
                    MimeType: \(fileInfo.mimeType as String)
                    \(innerMessage.encrypted ? "" : "Link: \(fileInfo.downloadURL as String)")
                    """
                case DownloadState.none.rawValue:
                    return "[File transfer; checking the size...]"
                default:
                    // .invalid case
                    unreachable()
            }
        }
        return innerMessage.retracted ? NSLocalizedString("This message got retracted", comment: "") : innerMessage.messageText
    }
    override var hasText: Bool {
        return !text.isEmpty
    }
    override var attributedText: AttributedString {
        get {
            // Keep outgoing links in the same color as outgoing text (white) for readability
            let linkColor: Color = self.user.isCurrentUser ? .white : .accentColor
            return text.linkify(linkColor: linkColor)
        }
        set {}
    }
    override var status: Status? {
        get {
            // Incoming messages shouldn't have a status
            if innerMessage.inbound {
                return nil
            }
            let errorType = innerMessage.errorType as String?
            let isError = errorType != nil && !errorType!.isEmpty
            switch(innerMessage) {
                case let message where isError && !message.hasBeenReceived:
                    return .error(DraftMessage(id: id, text: text, medias: [], recording: recording, replyMessage: replyMessage, createdAt: createdAt))
                case let message where message.hasBeenDisplayed:
                    return .read
                case let message where message.hasBeenReceived:
                    return .received
                case let message where message.hasBeenSent:
                    return .sent
                default:
                    return .sending
            }
        }
        set {}
    }
    override var createdAt: Date {
        get {
            return innerMessage.timestamp
        }
        set {}
    }
    override var reactions: [Reaction] {
        get {
            //TODO: create new wrapper class ChatViewReaction just like we've already done for User and Contact
            var retval: [Reaction] = []
            let reactions: [MLReactionsEntry] = (innerMessage.reactions as [MLReactionsEntry]).sorted(by: { $0.user < $1.user })
            for reactionsInfo in reactions {
                for reaction in reactionsInfo.reactions {
                    retval.append(Reaction(
                        user: ChatViewUser(reactionsInfo.contact as! NSObject&MLContactProtocol),
                        createdAt: reactionsInfo.timestamp,
                        type: .emoji(reaction as! String),
                        status: .sent
                    ))
                }
            }
            return retval
        }
        set {}
    }
    override var attachments: [Attachment] {
        get {
            guard innerMessage.messageType == kMessageTypeFiletransfer, let fileInfo = fileInfo else {
                return []
            }

            guard (fileInfo.downloadState as DownloadState.RawValue) == DownloadState.complete.rawValue else {
                // TODO: show a proper button for mime type checks instead of doing this automatically
                MLFiletransfer.checkMimeTypeAndSize(forHistoryID: innerMessage.messageDBId)
                return []
            }
            let fileURL = fileInfo.fileURL as URL
            let cacheId = fileInfo.cacheId as String
            let attachmentUUID = HelperTools.stringToUUID(cacheId).uuidString
            switch fileInfo.mimeType as String {
                case let mimeType where mimeType.starts(with: "image/"):
                    let attachment = Attachment(id: attachmentUUID, url: fileURL, type: .image)
                    return [attachment]
                case let mimeType where mimeType.starts(with: "video/"):
                    let thumbnail = fileInfo.thumbnailURL as URL? ?? URL(string: "about:blank")!
                    let attachment = Attachment(id: attachmentUUID, thumbnail: thumbnail, full: fileURL, type: .video, mimeType: mimeType)
                    return [attachment]
                default:
                    return []
            }
        }
        set {}
    }
    override var recording: Recording? {
        get {
            guard innerMessage.messageType == kMessageTypeFiletransfer, let fileInfo = fileInfo else {
                return nil
            }

            guard (fileInfo.downloadState as DownloadState.RawValue) == DownloadState.complete.rawValue else {
                return nil
            }
            guard (fileInfo.mimeType as String).starts(with: "audio/") else {
                return nil
            }
            let fileURL = fileInfo.fileURL as URL
            return Recording(duration: fileInfo.mediaDuration, url: fileURL, mimeType: fileInfo.mimeType)
        }
        set {}
    }

    init(_ message: MLMessage) {
//         DDLogVerbode("Creating new ChatViewMessage for MLMessage: \(String(describing:message)): \(Thread.callStackSymbols)")
        self.innerMessage = ObservableKVOWrapper(message)
        if innerMessage.obj.messageType == kMessageTypeFiletransfer {
            self.fileInfo = ObservableKVOWrapper(innerMessage.obj.fileInfo)
        } else {
            self.fileInfo = nil
        }
        let user = ChatViewUser(message.contact as! NSObject&MLContactProtocol)
        // We don't need to properly initialize the properties that we overrode with computed properties
        super.init(id: message.id, user: user, createdAt: Date(), text: "")

        // Forward innerMessage changes as ChatViewMessage changes
        innerMessage.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)

        // Forward fileInfo changes as ChatViewMessage changes
        fileInfo?.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)
    }
    public var description: String {
        return "ChatViewMessage<\(String(describing:self.innerMessage))>"
    }
}

class ChatViewUser: ExyteChat.User {
    let innerContact: ObservableKVOWrapper<NSObject&MLContactProtocol>
    private var subscriptions: Set<AnyCancellable> = Set()
    override var name: String {
        get {
            return innerContact.contactDisplayName ?? ""
        }
        set {}
    }
    override var avatarImage: UIImage? {
        get {
            return innerContact.avatar as UIImage?
        }
        set {}
    }
    init(_ contact: NSObject&MLContactProtocol) {
//         DDLogVerbose("Creating new ChatViewUser for MLContactProtocol: \(String(describing:contact)): \(Thread.callStackSymbols)")
        self.innerContact = ObservableKVOWrapper(contact)
        // We don't need to initialize the properties that we overrode with computed properties
        super.init(id: contact.id, name: "", isCurrentUser: contact.isSelf)

        // Forward innerContact changes as ChatViewUser changes
        innerContact.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)
    }
    //our parent class forces us to implement this, but it should never be called!
    required init(from decoder: Decoder) throws {
        unreachable("ChatViewUser should never be deserialized!")
    }
    public var description: String {
        return "ChatViewUser<\(String(describing:self.innerContact))>"
    }
}
