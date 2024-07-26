//
//  MLNotificationManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/20/13.
//
//

#import "HelperTools.h"
#import "MLNotificationManager.h"
#import "MLImageManager.h"
#import "MLMessage.h"
#import "MLXEPSlashMeHandler.h"
#import "MLConstants.h"
#import "xmpp.h"
#import "MLFiletransfer.h"
#import "MLNotificationQueue.h"
#import "MLXMPPManager.h"
#import <monalxmpp/monalxmpp-Swift.h>

@import UserNotifications;
@import CoreServices;
@import Intents;
@import AVFoundation;
@import UniformTypeIdentifiers;

typedef NS_ENUM(NSUInteger, MLNotificationState) {
    MLNotificationStateNone,
    MLNotificationStatePending,
    MLNotificationStateDelivered,
};

@interface MLNotificationManager ()
@property (nonatomic, readonly) NotificationPrivacySettingOption notificationPrivacySetting;
@end

@implementation MLNotificationManager

+(MLNotificationManager*) sharedInstance
{
    static dispatch_once_t once;
    static MLNotificationManager* sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [MLNotificationManager new] ;
    });
    return sharedInstance;
}

-(id) init
{
    self = [super init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleFiletransferUpdate:) name:kMonalMessageFiletransferUpdateNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleDeletedMessage:) name:kMonalDeletedMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleDisplayedMessages:) name:kMonalDisplayedMessagesNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleXMPPError:) name:kXMPPError object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleContactRefresh:) name:kMonalContactRefresh object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleContactRefresh:) name:kMonalContactRemoved object:nil];
    return self;
}

-(NotificationPrivacySettingOption) notificationPrivacySetting
{
    NotificationPrivacySettingOption value = (NotificationPrivacySettingOption)[[HelperTools defaultsDB] integerForKey:@"NotificationPrivacySetting"];
    DDLogVerbose(@"Current NotificationPrivacySettingOption: %d", (int)value);
    return value;
}

-(void) handleContactRefresh:(NSNotification*) notification
{
    //these will not survive process switches, but that's enough for now
    static NSMutableSet* displayed;
    static NSMutableSet* removed;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        displayed = [NSMutableSet new];
        removed = [NSMutableSet new];
    });
    xmpp* xmppAccount = notification.object;
    MLContact* contact = notification.userInfo[@"contact"];
    NSString* idval = [NSString stringWithFormat:@"subscription(%@, %@)", contact.accountId, contact.contactJid];
    
    //remove contact requests notification once the contact request has been accepted
    if(!contact.hasIncomingContactRequest)
    {
        monal_void_block_t block = ^{
            [[UNUserNotificationCenter currentNotificationCenter] getPendingNotificationRequestsWithCompletionHandler:^(NSArray* requests) {
                for(UNNotificationRequest* request in requests)
                    if([request.identifier isEqualToString:idval])
                    {
                        DDLogVerbose(@"Removing pending handled subscription request notification with identifier '%@'...", idval);
                        [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[idval]];
                    }
            }];
            [[UNUserNotificationCenter currentNotificationCenter] getDeliveredNotificationsWithCompletionHandler:^(NSArray* notifications) {
                for(UNNotification* notification in notifications)
                    if([notification.request.identifier isEqualToString:idval])
                    {
                        DDLogVerbose(@"Removing delivered handled subscription request notification with identifier '%@'...", idval);
                        [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[idval]];
                    }
            }];
            @synchronized(removed) {
                [removed addObject:idval];
            }
        };
        
        //only try to remove once
        BOOL isContained = NO;
        @synchronized(removed) {
            isContained = [removed containsObject:idval];
        }
        if(!isContained)
        {
            //do this in its own thread because we don't want to block the main thread or other threads here (the removal can take ~50ms)
            //but DON'T do this in the appex because this can try to mess with notifications after the parse queue was frozen (see appex code for explanation what this means)
            if([HelperTools isAppExtension])
                block();
            else
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), block);
        }
        
        //return because we don't want to display any contact request notification
        return;
    }
    
    //don't alert twice
    @synchronized(displayed) {
        if([displayed containsObject:idval])
            return;
    }
    
    UNMutableNotificationContent* content = [UNMutableNotificationContent new];
    content.title = xmppAccount.connectionProperties.identity.jid;
    content.body = [NSString stringWithFormat:NSLocalizedString(@"The user %@ (%@) wants to add you to their contact list", @""), contact.contactDisplayName, contact.contactJid];
    content.threadIdentifier = [self threadIdentifierWithContact:contact];
    content.categoryIdentifier = @"subscription";
    //don't simply use contact directly to make sure we always use a freshly created up to date contact when unpacking the userInfo dict
    content.userInfo = @{
        @"fromContactJid": contact.contactJid,
        @"fromContactAccountId": contact.accountId,
    };
    
    DDLogDebug(@"Publishing notification with id %@", idval);
    [self publishNotificationContent:content withID:idval];
    @synchronized(displayed) {
        [displayed addObject:idval];
    }
}

-(void) handleXMPPError:(NSNotification*) notification
{
    //severe errors will be shown as notification (in addition to the banner shown if the app is in foreground)
    if([notification.userInfo[@"isSevere"] boolValue])
    {
        xmpp* xmppAccount = notification.object;
        DDLogError(@"SEVERE XMPP Error(%@): %@", xmppAccount.connectionProperties.identity.jid, notification.userInfo[@"message"]);
#ifdef IS_ALPHA
        NSString* idval = [[NSUUID UUID] UUIDString];
#else
        NSString* idval = xmppAccount.connectionProperties.identity.jid;        //use this to only show the newest error notification per account
#endif
        UNMutableNotificationContent* content = [UNMutableNotificationContent new];
        content.title = xmppAccount.connectionProperties.identity.jid;
        content.body = notification.userInfo[@"message"];
        content.sound = [UNNotificationSound defaultSound];
        UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:idval content:content trigger:nil];
        NSError* error = [HelperTools postUserNotificationRequest:request];
        if(error)
            DDLogError(@"Error posting xmppError notification: %@", error);
    }
}

#pragma mark message signals

-(AnyPromise*) notificationStateForMessage:(MLMessage*) message
{
    NSString* idval = [self identifierWithMessage:message];
    NSMutableArray* promises = [NSMutableArray new];
    
    [promises addObject:[AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        DDLogVerbose(@"Checking for 'pending' notification state for '%@'...", idval);
        [[UNUserNotificationCenter currentNotificationCenter] getPendingNotificationRequestsWithCompletionHandler:^(NSArray* requests) {
            for(UNNotificationRequest* request in requests)
                if([request.identifier isEqualToString:idval])
                {
                    DDLogDebug(@"Notification state 'pending' for: %@", idval);
                    resolve(@(MLNotificationStatePending));
                    return;
                }
                resolve(@(MLNotificationStateNone));
        }];
    }]];
    
    [promises addObject:[AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        DDLogVerbose(@"Checking for 'delivered' notification state for '%@'...", idval);
        [[UNUserNotificationCenter currentNotificationCenter] getDeliveredNotificationsWithCompletionHandler:^(NSArray* notifications) {
            for(UNNotification* notification in notifications)
                if([notification.request.identifier isEqualToString:idval])
                {
                    DDLogDebug(@"Notification state 'delivered' for: %@", idval);
                    resolve(@(MLNotificationStateDelivered));
                    return;
                }
                resolve(@(MLNotificationStateNone));
        }];
    }]];
    
    
    return PMKWhen(promises).then(^(NSArray* results) {
        DDLogVerbose(@"Notification state check for '%@' completed...", idval);
        for(NSNumber* entry in results)
            if(entry.integerValue != MLNotificationStateNone)
                return entry;
        return @(MLNotificationStateNone);
    });
}

-(void) handleFiletransferUpdate:(NSNotification*) notification
{
    xmpp* xmppAccount = notification.object;
    MLMessage* message = [notification.userInfo objectForKey:@"message"];
    NSString* idval = [self identifierWithMessage:message];
    //do this asynchronously on a background thread
    [self notificationStateForMessage:message].thenInBackground(^(NSNumber* _state) {
        MLNotificationState state = _state.integerValue;
        if(state == MLNotificationStatePending || state == MLNotificationStateNone)
        {
            DDLogDebug(@"Already pending or unknown notification '%@', updating/posting it...", idval);
            [self internalMessageHandlerWithMessage:message andAccount:xmppAccount showAlert:YES andSound:YES andLMCReplaced:NO];
        }
        else if(state == MLNotificationStateDelivered)
        {
            DDLogDebug(@"Already displayed notification '%@', updating it...", idval);
            [self internalMessageHandlerWithMessage:message andAccount:xmppAccount showAlert:YES andSound:NO andLMCReplaced:NO];
        }
        else
            unreachable(@"Unknown MLNotificationState!", @{@"state": @(state)});
    });
}

-(void) handleNewMessage:(NSNotification*) notification
{
    xmpp* xmppAccount = notification.object;
    MLMessage* message = [notification.userInfo objectForKey:@"message"];
    BOOL showAlert = notification.userInfo[@"showAlert"] ? [notification.userInfo[@"showAlert"] boolValue] : NO;
    BOOL LMCReplaced = notification.userInfo[@"LMCReplaced"] ? [notification.userInfo[@"LMCReplaced"] boolValue] : NO;
    [self internalMessageHandlerWithMessage:message andAccount:xmppAccount showAlert:showAlert andSound:YES andLMCReplaced:LMCReplaced];
}

-(void) internalMessageHandlerWithMessage:(MLMessage*) message andAccount:(xmpp*) xmppAccount showAlert:(BOOL) showAlert andSound:(BOOL) sound andLMCReplaced:(BOOL) LMCReplaced
{
    if([message.messageType isEqualToString:kMessageTypeStatus])
        return;
    DDLogVerbose(@"notification manager should show notification for: %@", message.messageText);
    if(!showAlert)
    {
        DDLogDebug(@"not showing notification: showAlert is NO");
        return;
    }
    
    BOOL muted = [[DataLayer sharedInstance] isMutedJid:message.buddyName onAccount:message.accountId];
    if(!muted && message.isMuc == YES && [[DataLayer sharedInstance] isMucAlertOnMentionOnly:message.buddyName onAccount:message.accountId])
    {
        NSString* displayName = [MLContact ownDisplayNameForAccount:xmppAccount];
        NSString* ownJid = xmppAccount.connectionProperties.identity.jid;
        NSString* userPart = [HelperTools splitJid:ownJid][@"user"];
        NSString* nick = [[DataLayer sharedInstance] ownNickNameforMuc:message.buddyName forAccount:message.accountId];
        if(!(
            [message.messageText localizedCaseInsensitiveContainsString:nick] ||
            [message.messageText localizedCaseInsensitiveContainsString:displayName] ||
            [message.messageText localizedCaseInsensitiveContainsString:userPart] ||
            [message.messageText localizedCaseInsensitiveContainsString:ownJid]
        ))
            muted = YES;
    }
    if(muted)
    {
        DDLogDebug(@"not showing notification: this contact got muted");
        return;
    }
    
    //check if we need to replace the still displayed notification or ignore this LMC
    if(LMCReplaced)
    {
        NSString* idval = [self identifierWithMessage:message];
        //wait synchronous for completion (needed for appex)
        MLNotificationState state = PMKHangEnum([self notificationStateForMessage:message]);
        DDLogVerbose(@"Notification state for '%@': %@", idval, @(state));
        if(state == MLNotificationStateNone)
        {
            DDLogDebug(@"not showing notification for LMC: this notification was already removed earlier");
            return;
        }
    }
    
    if([HelperTools isNotInFocus])
    {
        DDLogVerbose(@"notification manager should show notification in background: %@", message.messageText);
        [self showNotificationForMessage:message withSound:sound andAccount:xmppAccount];
    }
    else
    {
        //don't show notifications for open chats
        if(![message isEqualToContact:self.currentContact])
        {
            DDLogVerbose(@"notification manager should show notification in foreground: %@", message.messageText);
            [self showNotificationForMessage:message withSound:sound andAccount:xmppAccount];
        }
        else
        {
            DDLogDebug(@"not showing notification and only playing sound: chat is open");
            [self playNotificationSoundForMessage:message withSound:sound andAccount:xmppAccount];
        }
    }
}

-(void) handleDisplayedMessages:(NSNotification*) notification
{
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    NSArray<MLMessage*>* messages = [notification.userInfo objectForKey:@"messagesArray"];
    DDLogVerbose(@"notification manager got displayed messages notice with %lu entries", [messages count]);
    
    monal_void_block_t block = ^{
        for(MLMessage* msg in messages)
        {
            if([msg.messageType isEqualToString:kMessageTypeStatus])
                return;
            
            NSString* idval = [self identifierWithMessage:msg];
            
            DDLogVerbose(@"Removing pending/delivered notification for message '%@' with identifier '%@'...", msg.messageId, idval);
            [center removePendingNotificationRequestsWithIdentifiers:@[idval]];
            [center removeDeliveredNotificationsWithIdentifiers:@[idval]];
        }
    };
    
    //do this in its own thread because we don't want to block the main thread or other threads here (the removal can take ~50ms)
    //but DON'T do this in the appex because this can try to mess with notifications after the parse queue was frozen (see appex code for explanation what this means)
    if([HelperTools isAppExtension])
        block();
    else
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), block);
    
    //update app badge
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalUpdateUnread object:nil];
    
}

-(void) handleDeletedMessage:(NSNotification*) notification
{
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    MLMessage* message = [notification.userInfo objectForKey:@"message"];
    
    if([message.messageType isEqualToString:kMessageTypeStatus])
        return;
    
    NSString* idval = [self identifierWithMessage:message];
    
    DDLogVerbose(@"notification manager got deleted message notice: %@", message.messageId);
    [center removePendingNotificationRequestsWithIdentifiers:@[idval]];
    [center removeDeliveredNotificationsWithIdentifiers:@[idval]];
    
    //update app badge
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalUpdateUnread object:nil];
}

-(NSString*) identifierWithMessage:(MLMessage*) message
{
    return [NSString stringWithFormat:@"message(%@, %@)", [self threadIdentifierWithMessage:message], message.messageId];
}

-(NSString*) threadIdentifierWithMessage:(MLMessage*) message
{
    return [NSString stringWithFormat:@"thread(%@, %@)", message.accountId, message.buddyName];
}

-(NSString*) threadIdentifierWithContact:(MLContact*) contact
{
    return [NSString stringWithFormat:@"thread(%@, %@)", contact.accountId, contact.contactJid];
}

-(UNMutableNotificationContent*) updateBadgeForContent:(UNMutableNotificationContent*) content
{
    NSNumber* unreadMsgCnt = [[DataLayer sharedInstance] countUnreadMessages];
    DDLogVerbose(@"Raw badge value: %@", unreadMsgCnt);
    content.badge = unreadMsgCnt;
    return content;
}

-(void) publishNotificationContent:(UNNotificationContent*) content withID:(NSString*) idval
{
    //scheduling the notification in 2 seconds will make it possible to be deleted by XEP-0333 chat-markers received directly after the message
    //this is useful in catchup scenarios
    DDLogVerbose(@"notification manager: publishing notification in 2 seconds: %@", content);
    UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:idval content:content trigger:[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:2 repeats: NO]];
    NSError* error = [HelperTools postUserNotificationRequest:request];
    if(error)
        DDLogError(@"Error posting local notification: %@", error);
}

-(void) playNotificationSoundForMessage:(MLMessage*) message withSound:(BOOL) sound andAccount:(xmpp*) account
{
    UNMutableNotificationContent* content = [UNMutableNotificationContent new];
    NSString* idval = [self identifierWithMessage:message];
    
    if(sound && [[HelperTools defaultsDB] boolForKey:@"Sound"])
    {
        NSString* filename = [[HelperTools defaultsDB] objectForKey:@"AlertSoundFile"];
        if(filename)
        {
            content.sound = [UNNotificationSound soundNamed:[NSString stringWithFormat:@"AlertSounds/%@.aif", filename]];
            DDLogDebug(@"Using user configured alert sound: %@", content.sound);
        }
        else
        {
            content.sound = [UNNotificationSound defaultSound];
            DDLogDebug(@"Using default alert sound: %@", content.sound);
        }
    }
    else
        DDLogDebug(@"Using no alert sound");
    
    DDLogDebug(@"Publishing sound-but-no-body notification with id %@", idval);
    [self publishNotificationContent:[self updateBadgeForContent:content] withID:idval];
}

-(void) showNotificationForMessage:(MLMessage*) message withSound:(BOOL) sound andAccount:(xmpp*) account
{
    // always use legacy notifications if we should only show a generic "New Message" notifiation without name or content
    if(self.notificationPrivacySetting > NotificationPrivacySettingOptionDisplayOnlyName)
        return [self showLegacyNotificationForMessage:message withSound:sound];
    
    return [self showModernNotificationForMessage:message withSound:sound andAccount:account];
}

-(void) showModernNotificationForMessage:(MLMessage*) message withSound:(BOOL) sound andAccount:(xmpp*) account    API_AVAILABLE(ios(15.0), macosx(12.0))  //means: API_AVAILABLE(ios(15.0), maccatalyst(15.0))
{
    UNMutableNotificationContent* content = [UNMutableNotificationContent new];
    NSString* idval = [self identifierWithMessage:message];
    
    INSendMessageAttachment* audioAttachment = nil;
    NSString* msgText = NSLocalizedString(@"Open app to see more", @"");
    
    //only show msgText if allowed
    if(self.notificationPrivacySetting == NotificationPrivacySettingOptionDisplayNameAndMessage)
    {
        //XEP-0245: The slash me Command
        if([message.messageText hasPrefix:@"/me "])
            msgText = [[MLXEPSlashMeHandler sharedInstance] stringSlashMeWithMessage:message];
        else
            msgText = message.messageText;
        
        //notification settings
        content.threadIdentifier = [self threadIdentifierWithMessage:message];
        content.categoryIdentifier = @"message";
        
        //user info for answer etc.
        //don't simply use contact directly to make sure we always use a freshly created up to date contact when unpacking the userInfo dict
        content.userInfo = @{
            @"fromContactJid": message.buddyName,
            @"fromContactAccountId": message.accountId,
            @"messageId": message.messageId
        };
        
        if([message.messageType isEqualToString:kMessageTypeFiletransfer])
        {
            NSDictionary* info = [MLFiletransfer getFileInfoForMessage:message];
            if(info)
            {
                NSString* mimeType = info[@"mimeType"];
                
                if([mimeType hasPrefix:@"image/"])
                    msgText = NSLocalizedString(@"📷 An Image", @"");
                else if([mimeType hasPrefix:@"audio/"])
                    msgText = NSLocalizedString(@"🎵 An Audiomessage", @"");
                else if([mimeType hasPrefix:@"video/"])
                    msgText = NSLocalizedString(@"🎥 A Video", @"");
                else if([mimeType isEqualToString:@"application/pdf"])
                    msgText = NSLocalizedString(@"📄 A Document", @"");
                else
                    msgText = NSLocalizedString(@"📁 A File", @"");
                
                if(![info[@"needsDownloading"] boolValue])
                {
                    if([mimeType hasPrefix:@"image/"])
                    {
                        UNNotificationAttachment* attachment;
                        UTType* typeHint = [UTType typeWithMIMEType:mimeType];
                        if(typeHint == nil)
                            typeHint = UTTypeImage;
                        attachment = [self createNotificationAttachmentForFileInfo:info havingTypeHint:typeHint];
                        if(attachment)
                            content.attachments = @[attachment];
                    }
                    else if([mimeType hasPrefix:@"audio/"])
                    {
                        UNNotificationAttachment* attachment;
                        UTType* typeHint = [UTType typeWithMIMEType:mimeType];
                        if(typeHint == nil)
                            typeHint = UTTypeAudio;
                        audioAttachment = [INSendMessageAttachment attachmentWithAudioMessageFile:[INFile fileWithFileURL:[NSURL fileURLWithPath:info[@"cacheFile"]] filename:info[@"filename"] typeIdentifier:typeHint.identifier]];
                        DDLogVerbose(@"Added audio attachment(%@ = %@): %@", mimeType, typeHint, audioAttachment);
                        attachment = [self createNotificationAttachmentForFileInfo:info havingTypeHint:typeHint];
                        if(attachment)
                            content.attachments = @[attachment];
                    }
                    else if([mimeType hasPrefix:@"video/"])
                    {
                        UNNotificationAttachment* attachment;
                        UTType* typeHint = [UTType typeWithMIMEType:mimeType];
                        if(typeHint == nil)
                            typeHint = UTTypeMovie;
                        attachment = [self createNotificationAttachmentForFileInfo:info havingTypeHint:typeHint];
                        if(attachment)
                            content.attachments = @[attachment];
                    }
                }
            }
            else
            {
                // empty info dict default to "Sent a file"
                DDLogWarn(@"Got filetransfer with unknown type");
                msgText = NSLocalizedString(@"📁 A File", @"");
            }
        }
        else if([message.messageType isEqualToString:kMessageTypeUrl] && [[HelperTools defaultsDB] boolForKey:@"ShowURLPreview"])
            msgText = NSLocalizedString(@"🔗 A Link", @"");
        else if([message.messageType isEqualToString:kMessageTypeGeo])
            msgText = NSLocalizedString(@"📍 A Location", @"");
    }
    content.body = msgText;     //save message text to notification content
    
    if(sound && [[HelperTools defaultsDB] boolForKey:@"Sound"])
    {
        NSString* filename = [[HelperTools defaultsDB] objectForKey:@"AlertSoundFile"];
        if(filename)
        {
            content.sound = [UNNotificationSound soundNamed:[NSString stringWithFormat:@"AlertSounds/%@.aif", filename]];
            DDLogDebug(@"Using user configured alert sound: %@", content.sound);
        }
        else
        {
            content.sound = [UNNotificationSound defaultSound];
            DDLogDebug(@"Using default alert sound: %@", content.sound);
        }
    }
    else
        DDLogDebug(@"Using no alert sound");
        
    // update badge value prior to donating the interaction to sirikit
    [self updateBadgeForContent:content];
    
    INSendMessageIntent* intent = [self makeIntentForMessage:message usingText:msgText andAudioAttachment:audioAttachment direction:INInteractionDirectionIncoming];
    
    INInteraction* interaction = [[INInteraction alloc] initWithIntent:intent response:nil];
    interaction.direction = INInteractionDirectionIncoming;
    
    NSError* error = nil;
    UNNotificationContent* updatedContent = [content contentByUpdatingWithProvider:intent error:&error];
    if(error)
        DDLogError(@"Could not update notification content: %@", error);
    else
    {
        DDLogDebug(@"Publishing communication notification with id %@", idval);
        [self publishNotificationContent:updatedContent withID:idval];
    }
    
    //we can donate interactions after posting their notification (see signal source code)
    [interaction donateInteractionWithCompletion:^(NSError *error) {
        if(error)
            DDLogError(@"Could not donate interaction: %@", error);
    }];
}

-(void) donateInteractionForOutgoingDBId:(NSNumber*) messageDBId    API_AVAILABLE(ios(15.0), macosx(12.0))  //means: API_AVAILABLE(ios(15.0), maccatalyst(15.0))
{
    MLMessage* message = [[DataLayer sharedInstance] messageForHistoryID:messageDBId];
    INSendMessageIntent* intent = [self makeIntentForMessage:message usingText:@"dummyText" andAudioAttachment:nil direction:INInteractionDirectionOutgoing];
    INInteraction* interaction = [[INInteraction alloc] initWithIntent:intent response:nil];
    interaction.direction = INInteractionDirectionOutgoing;
    interaction.identifier = [NSString stringWithFormat:@"%@|%@", message.accountId, message.buddyName];
    [interaction donateInteractionWithCompletion:^(NSError *error) {
        if(error)
            DDLogError(@"Could not donate outgoing interaction: %@", error);
    }];
}

-(INSendMessageIntent*) makeIntentForMessage:(MLMessage*) message usingText:(NSString*) msgText andAudioAttachment:(INSendMessageAttachment*) audioAttachment direction:(INInteractionDirection) direction   API_AVAILABLE(ios(15.0), macosx(12.0))  //means: API_AVAILABLE(ios(15.0), maccatalyst(15.0))
{
    // some docu:
    // - https://developer.apple.com/documentation/usernotifications/implementing_communication_notifications?language=objc
    // - https://gist.github.com/Dexwell/dedef7389eae26c5b9db927dc5588905
    // - https://stackoverflow.com/a/68705169/3528174
    xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:message.accountId];
    MLContact* contact = [MLContact createContactFromJid:message.buddyName andAccountNo:message.accountId];
    INPerson* sender = nil;
    NSString* groupDisplayName = nil;
    NSMutableArray* recipients = [NSMutableArray new];
    if(message.isMuc)
    {
        groupDisplayName = contact.contactDisplayName;
        //we don't need different handling of incoming or outgoing messages for non-anon mucs because sender and receiver always contain the right contacts
        if([@"group" isEqualToString:message.mucType] && message.participantJid)
        {
            MLContact* contactInGroup = [MLContact createContactFromJid:message.participantJid andAccountNo:message.accountId];
            //use MLMessage's capability to calculate the fallback name using actualFrom
            sender = [self makeINPersonWithContact:contactInGroup andDisplayName:message.contactDisplayName andAccount:account];
            
            //add other group members
            for(NSDictionary* member in [[DataLayer sharedInstance] getMembersAndParticipantsOfMuc:message.buddyName forAccountId:message.accountId])
            {
                MLContact* contactInGroup = [MLContact createContactFromJid:emptyDefault(member[@"participant_jid"], @"", member[@"member_jid"]) andAccountNo:message.accountId];
                [recipients addObject:[self makeINPersonWithContact:contactInGroup andDisplayName:member[@"room_nick"] andAccount:account]];
            }
        }
        else
        {
            //in anon mucs we have to flip sender and receiver to make sure iOS handles them correctly
            if(direction == INInteractionDirectionIncoming)
            {
                //use MLMessage's capability to calculate the fallback name using actualFrom
                sender = [self makeINPersonWithContact:contact andDisplayName:message.contactDisplayName andAccount:account];
                //the next 2 lines are needed to make iOS show the group name in notifications
                [recipients addObject:[self makeINPersonForOwnAccount:account]];
                [recipients addObject:sender];
            }
            else
            {
                //we always need a sender (that's us in the outgoing case)
                sender = [self makeINPersonForOwnAccount:account];
                //use MLMessage's capability to calculate the fallback name using actualFrom
                [recipients addObject:[self makeINPersonWithContact:contact andDisplayName:message.contactDisplayName andAccount:account]];
                [recipients addObject:sender];      //match the recipients array for the incoming case above
            }
        }
    }
    else
    {
        //in 1:1 messages we have to flip sender and receiver to make sure iOS adds the correct share suggestions to its list
        if(direction == INInteractionDirectionIncoming)
        {
            sender = [self makeINPersonWithContact:contact andDisplayName:nil andAccount:account];
            [recipients addObject:[self makeINPersonForOwnAccount:account]];
        }
        else
        {
            sender = [self makeINPersonForOwnAccount:account];
            [recipients addObject:[self makeINPersonWithContact:contact andDisplayName:nil andAccount:account]];
        }
    }
    
    //DDLogDebug(@"Creating INSendMessageIntent with recipients=%@, speakableGroupName=%@, sender=%@", recipients, groupDisplayName, sender);
    INSendMessageIntent* intent = [[INSendMessageIntent alloc] initWithRecipients:recipients
                                                              outgoingMessageType:(audioAttachment ? INOutgoingMessageTypeOutgoingMessageAudio : INOutgoingMessageTypeOutgoingMessageText)
                                                                          content:msgText
                                                               speakableGroupName:(groupDisplayName ? [[INSpeakableString alloc] initWithSpokenPhrase:groupDisplayName] : nil)
                                                           conversationIdentifier:[[NSString alloc] initWithData:[HelperTools serializeObject:contact] encoding:NSISOLatin1StringEncoding]
                                                                      serviceName:message.accountId.stringValue
                                                                           sender:sender
                                                                      attachments:(audioAttachment ? @[audioAttachment] : @[])];
    //DDLogDebug(@"Intent is now: %@", intent);
    if(message.isMuc)
    {
        if(contact.avatar != nil)
        {
            DDLogDebug(@"Using muc avatar image: %@", contact.avatar);
            [intent setImage:[INImage imageWithImageData:UIImagePNGRepresentation(contact.avatar)] forParameterNamed:@"speakableGroupName"];
        }
        else
            DDLogDebug(@"NOT using avatar image...");
    }
    
    return intent;
    
    /*
    if(message.isMuc)
    {
        [intent setImage:avatar forParameterNamed:"speakableGroupName"];
        [intent setImage:avatar forParameterNamed:"sender"];
    }
    else
        [intent setImage:avatar forParameterNamed:"sender"];
    */
    
    /*
    INCallRecord* callRecord = [[INCallRecord alloc] initWithIdentifier:[self threadIdentifierWithMessage:message]
                                                            dateCreated:[NSDate date]
                                                         callRecordType:INCallRecordTypeOutgoing
                                                         callCapability:INCallCapabilityAudioCall
                                                           callDuration:@0
                                                                 unseen:@YES];
    INStartCallIntent* intent = [[INStartCallIntent alloc] initWithCallRecordFilter:nil
                                                               callRecordToCallBack:callRecord
                                                                         audioRoute:INCallAudioRouteUnknown
                                                                    destinationType:INCallDestinationTypeNormal
                                                                           contacts:@[sender]
                                                                     callCapability:INCallCapabilityAudioCall];
    */
}

-(INPerson*) makeINPersonForOwnAccount:(xmpp*) account    API_AVAILABLE(ios(15.0), macosx(12.0))  //means: API_AVAILABLE(ios(15.0), maccatalyst(15.0))
{
    DDLogDebug(@"Building INPerson for self contact...");
    INPersonHandle* personHandle = [[INPersonHandle alloc] initWithValue:account.connectionProperties.identity.jid type:INPersonHandleTypeUnknown label:@"Monal IM"];
    NSPersonNameComponents* nameComponents = [NSPersonNameComponents new];
    nameComponents.nickname = [MLContact ownDisplayNameForAccount:account];
    MLContact* ownContact = [MLContact createContactFromJid:account.connectionProperties.identity.jid andAccountNo:account.accountNo];
    INImage* contactImage = nil;
    if(ownContact.avatar != nil)
    {
        DDLogDebug(@"Using own avatar image: %@", ownContact.avatar);
        NSData* avatarData = UIImagePNGRepresentation(ownContact.avatar);
        contactImage = [INImage imageWithImageData:avatarData];
    }
    else
        DDLogDebug(@"NOT using own avatar image...");
    INPerson* person = [[INPerson alloc] initWithPersonHandle:personHandle
                                               nameComponents:nameComponents
                                                  displayName:nameComponents.nickname
                                                        image:contactImage
                                            contactIdentifier:nil
                                             customIdentifier:nil
                                                         isMe:YES
                                               suggestionType:INPersonSuggestionTypeInstantMessageAddress];
    return person;
}

-(INPerson*) makeINPersonWithContact:(MLContact*) contact andDisplayName:(NSString* _Nullable) displayName andAccount:(xmpp*) account    API_AVAILABLE(ios(15.0), macosx(12.0))  //means: API_AVAILABLE(ios(15.0), maccatalyst(15.0))
{
    DDLogDebug(@"Building INPerson for contact: %@ using display name: %@", contact, displayName);
    if(displayName == nil)
        displayName = contact.contactDisplayName;
    INPersonHandle* personHandle = [[INPersonHandle alloc] initWithValue:contact.contactJid type:INPersonHandleTypeUnknown label:@"Monal IM"];
    NSPersonNameComponents* nameComponents = [NSPersonNameComponents new];
    nameComponents.nickname = displayName;
    INImage* contactImage = nil;
    if(contact.avatar != nil)
    {
        DDLogDebug(@"Using avatar image: %@", contact.avatar);
        NSData* avatarData = UIImagePNGRepresentation(contact.avatar);
        contactImage = [INImage imageWithImageData:avatarData];
    }
    else
        DDLogDebug(@"NOT using avatar image...");
    INPerson* person = [[INPerson alloc] initWithPersonHandle:personHandle
                                               nameComponents:nameComponents
                                                  displayName:nameComponents.nickname
                                                        image:contactImage
                                            contactIdentifier:nil
                                             customIdentifier:nil
                                                         isMe:account.connectionProperties.identity.jid == contact.contactJid
                                               suggestionType:INPersonSuggestionTypeInstantMessageAddress];
    /*
    if(contact.isInRoster)	
        person.relationship = INPersonRelationshipFriend;
    */
    return person;
}

-(void) showLegacyNotificationForMessage:(MLMessage*) message withSound:(BOOL) sound
{
    UNMutableNotificationContent* content = [UNMutableNotificationContent new];
    MLContact* contact = [MLContact createContactFromJid:message.buddyName andAccountNo:message.accountId];
    NSString* idval = [self identifierWithMessage:message];
    
    //Only show contact name if allowed
    if(self.notificationPrivacySetting <= NotificationPrivacySettingOptionDisplayOnlyName)
    {
        content.title = [contact contactDisplayName];
        if(message.isMuc)
            content.subtitle = [NSString stringWithFormat:NSLocalizedString(@"%@ says:", @""), message.contactDisplayName];
    }
    else
        content.title = NSLocalizedString(@"New Message", @"");

    //only show msgText if allowed
    if(self.notificationPrivacySetting == NotificationPrivacySettingOptionDisplayNameAndMessage)
    {
        NSString* msgText = message.messageText;

        //XEP-0245: The slash me Command
        if([message.messageText hasPrefix:@"/me "])
            msgText = [[MLXEPSlashMeHandler sharedInstance] stringSlashMeWithMessage:message];
        
        content.body = msgText;
        content.threadIdentifier = [self threadIdentifierWithMessage:message];
        content.categoryIdentifier = @"message";
        //don't simply use contact directly to make sure we always use a freshly created up to date contact when unpacking the userInfo dict
        content.userInfo = @{
            @"fromContactJid": message.buddyName,
            @"fromContactAccountId": message.accountId,
            @"messageId": message.messageId
        };

        if(sound && [[HelperTools defaultsDB] boolForKey:@"Sound"])
        {
            NSString* filename = [[HelperTools defaultsDB] objectForKey:@"AlertSoundFile"];
            if(filename)
            {
                content.sound = [UNNotificationSound soundNamed:[NSString stringWithFormat:@"AlertSounds/%@.aif", filename]];
                DDLogDebug(@"Using user configured alert sound: %@", content.sound);
            }
            else
            {
                content.sound = [UNNotificationSound defaultSound];
                DDLogDebug(@"Using default alert sound: %@", content.sound);
            }
        }
        else
            DDLogDebug(@"Using no alert sound");

        if([message.messageType isEqualToString:kMessageTypeFiletransfer])
        {
            NSDictionary* info = [MLFiletransfer getFileInfoForMessage:message];
            if(info)
            {
                NSString* mimeType = info[@"mimeType"];
                if([mimeType hasPrefix:@"image/"])
                {
                    content.body = NSLocalizedString(@"Sent an Image 📷", @"");

                    UNNotificationAttachment* attachment;
                    if(![info[@"needsDownloading"] boolValue])
                    {
                        UTType* typeHint = [UTType typeWithMIMEType:mimeType];
                        if(typeHint == nil)
                            typeHint = UTTypeImage;
                        attachment = [self createNotificationAttachmentForFileInfo:info havingTypeHint:typeHint];
                        if(attachment)
                        {
                            content.attachments = @[attachment];
                            content.body = @"";
                        }
                    }
                }
                else if([mimeType hasPrefix:@"image/"])
                    content.body = NSLocalizedString(@"📷 An Image", @"");
                else if([mimeType hasPrefix:@"audio/"])
                    content.body = NSLocalizedString(@"🎵 An Audiomessage", @"");
                else if([mimeType hasPrefix:@"video/"])
                    content.body = NSLocalizedString(@"🎥 A Video", @"");
                else if([mimeType isEqualToString:@"application/pdf"])
                    content.body = NSLocalizedString(@"📄 A Document", @"");
                else
                    content.body = NSLocalizedString(@"Sent a File 📁", @"");
            }
            else
            {
                // empty info dict default to "Sent a file"
                content.body = NSLocalizedString(@"Sent a File 📁", @"");
            }
        }
        else if([message.messageType isEqualToString:kMessageTypeUrl] && [[HelperTools defaultsDB] boolForKey:@"ShowURLPreview"])
            content.body = NSLocalizedString(@"Sent a Link 🔗", @"");
        else if([message.messageType isEqualToString:kMessageTypeGeo])
            content.body = NSLocalizedString(@"Sent a Location 📍", @"");
    }
    else
        content.body = NSLocalizedString(@"Open app to see more", @"");

    DDLogDebug(@"Publishing notification with id %@", idval);
    [self publishNotificationContent:[self updateBadgeForContent:content] withID:idval];
}

-(UNNotificationAttachment* _Nullable) createNotificationAttachmentForFileInfo:(NSDictionary*) info havingTypeHint:(UTType*) typeHint
{
    NSError* error;
    NSString* attachmentDir = [[HelperTools getContainerURLForPathComponents:@[@"documentCache"]] path];
    //use "tmp." prefix to make sure this file will be garbage collected should the ios notification attachment implementation leave it behind
    NSString* attachmentBasename = [NSString stringWithFormat:@"tmp.%@", info[@"cacheId"]];
    NSString* notificationAttachment = [attachmentDir stringByAppendingPathComponent:[attachmentBasename stringByAppendingPathExtensionForType:typeHint]];
    //using stringByAppendingPathExtensionForType: does not produce playable audio notifications for audios sent by conversations,
    //but seems to work for other types
    //--> use info[@"fileExtension"] for audio files and stringByAppendingPathExtensionForType: for all other types
    if([typeHint conformsToType:UTTypeAudio])
        notificationAttachment = [notificationAttachment stringByAppendingPathComponent:[attachmentBasename stringByAppendingPathExtension:info[@"fileExtension"]]];
    UIImage* image = nil;
    if([info[@"mimeType"] hasPrefix:@"image/svg"])
    {
        NSString* pngAttachment = [attachmentDir stringByAppendingPathComponent:[attachmentBasename stringByAppendingPathExtensionForType:UTTypePNG]];
        DDLogVerbose(@"Preparing for notification attachment(%@): converting downloaded file from svg at '%@' to png at '%@'...", typeHint, info[@"cacheFile"], pngAttachment);
        //we want our code to run synchronously --> use PMKHang
        //this code should never run in the main queue to not provoke a deadlock
        if([NSThread isMainThread])
            @throw [NSException exceptionWithName:@"InvalidThread" reason:@"PMKHang on renderUIImageFromSVGURL must never be called on the main thread!" userInfo:nil]; 
        image = (UIImage*)nilExtractor(PMKHang([HelperTools renderUIImageFromSVGURL:[NSURL fileURLWithPath:info[@"cacheFile"]]]));
        if(image != nil)
        {
            [UIImagePNGRepresentation(image) writeToFile:pngAttachment atomically:YES];
            typeHint = UTTypePNG;
            notificationAttachment = pngAttachment;
        }
    }
    //fallback if svg extraction failed OR it wasn't an SVG image in the first place
    if(image == nil)
    {
        DDLogVerbose(@"Preparing for notification attachment(%@): hardlinking downloaded file from '%@' to '%@'...", typeHint, info[@"cacheFile"], notificationAttachment);
        error = [HelperTools hardLinkOrCopyFile:info[@"cacheFile"] to:notificationAttachment];
        if(error)
        {
            DDLogError(@"Could not hardlink cache file to notification image temp file!");
            return nil;
        }
    }
    [HelperTools configureFileProtectionFor:notificationAttachment];
    UNNotificationAttachment* attachment = [UNNotificationAttachment attachmentWithIdentifier:info[@"cacheId"] URL:[NSURL fileURLWithPath:notificationAttachment] options:@{UNNotificationAttachmentOptionsTypeHintKey:typeHint} error:&error];
    if(error != nil)
        DDLogError(@"Could not create UNNotificationAttachment: %@", error);
    return attachment;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
