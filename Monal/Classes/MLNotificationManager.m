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

@import UserNotifications;
@import CoreServices;
@import Intents;

@interface MLNotificationManager ()
@property (nonatomic, assign) NotificationPrivacySettingOption notificationPrivacySetting;
@end

@implementation MLNotificationManager

+(MLNotificationManager*) sharedInstance
{
    static dispatch_once_t once;
    static MLNotificationManager* sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[MLNotificationManager alloc] init] ;
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

    self.notificationPrivacySetting = (NotificationPrivacySettingOption)[[HelperTools defaultsDB] integerForKey:@"NotificationPrivacySetting"];
    return self;
}

-(void) handleXMPPError:(NSNotification*) notification
{
    //severe errors will be shown as notification (in addition to the banner shown if the app is in foreground)
    if([notification.userInfo[@"isSevere"] boolValue])
    {
        xmpp* xmppAccount = notification.object;
        DDLogError(@"SEVERE XMPP Error(%@): %@", xmppAccount.connectionProperties.identity.jid, notification.userInfo[@"message"]);
        NSString* idval = xmppAccount.connectionProperties.identity.jid;        //use this to only show the newest error notification per account
        UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
        content.title = xmppAccount.connectionProperties.identity.jid;
        content.body = notification.userInfo[@"message"];
        content.sound = [UNNotificationSound defaultSound];
        UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
        UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:idval content:content trigger:nil];
        [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
            if(error)
                DDLogError(@"Error posting xmppError notification: %@", error);
        }]; 
    }
}

#pragma mark message signals

-(void) handleFiletransferUpdate:(NSNotification*) notification
{
    xmpp* xmppAccount = notification.object;
    MLMessage* message = [notification.userInfo objectForKey:@"message"];
    NSString* idval = [self identifierWithMessage:message];
    
    //check if we already show any notifications and update them if necessary (e.g. publish a second notification having the same id)
    [[UNUserNotificationCenter currentNotificationCenter] getPendingNotificationRequestsWithCompletionHandler:^(NSArray* requests) {
        for(UNNotificationRequest* request in requests)
            if([request.identifier isEqualToString:idval])
            {
                [self internalMessageHandlerWithMessage:message andAccount:xmppAccount showAlert:YES andSound:YES];
            }
    }];
    [[UNUserNotificationCenter currentNotificationCenter] getDeliveredNotificationsWithCompletionHandler:^(NSArray* notifications) {
        for(UNNotification* notification in notifications)
             if([notification.request.identifier isEqualToString:idval])
            {
                [self internalMessageHandlerWithMessage:message andAccount:xmppAccount showAlert:YES andSound:NO];
            }
    }];
}

-(void) handleNewMessage:(NSNotification*) notification
{
    xmpp* xmppAccount = notification.object;
    MLMessage* message = [notification.userInfo objectForKey:@"message"];
    BOOL showAlert = notification.userInfo[@"showAlert"] ? [notification.userInfo[@"showAlert"] boolValue] : NO;
    [self internalMessageHandlerWithMessage:message andAccount:xmppAccount showAlert:showAlert andSound:YES];
}

-(void) internalMessageHandlerWithMessage:(MLMessage*) message andAccount:(xmpp*) xmppAccount showAlert:(BOOL) showAlert andSound:(BOOL) sound
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
    if(message.isMuc == YES)
    {
        if(!muted && message.participantJid != nil)
            muted |= [[DataLayer sharedInstance] isMutedJid:message.participantJid onAccount:message.accountId];
        if(!muted && [[DataLayer sharedInstance] isMucAlertOnMentionOnly:message.buddyName onAccount:message.accountId])
        {
            NSString* displayName = [MLContact ownDisplayNameForAccount:xmppAccount];
            NSString* ownJid = xmppAccount.connectionProperties.identity.jid;
            NSString* userPart = [HelperTools splitJid:ownJid][@"user"];
            if(!(
                [message.messageText localizedCaseInsensitiveContainsString:displayName] ||
                [message.messageText localizedCaseInsensitiveContainsString:ownJid] ||
                [message.messageText localizedCaseInsensitiveContainsString:userPart]
            ))
                muted = YES;
        }
    }
    if(muted)
    {
        DDLogDebug(@"not showing notification: this contact got muted");
        return;
    }
    
    if([HelperTools isNotInFocus])
    {
        DDLogVerbose(@"notification manager should show notification in background: %@", message.messageText);
        [self showNotificaionForMessage:message withSound:sound];
    }
    else
    {
        //don't show notifications for open chats
        if(![message isEqualToContact:self.currentContact])
        {
            DDLogVerbose(@"notification manager should show notification in foreground: %@", message.messageText);
            [self showNotificaionForMessage:message withSound:sound];
        }
        else
            DDLogDebug(@"not showing notification: chat is open");
    }
}

-(void) handleDisplayedMessages:(NSNotification*) notification
{
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    NSArray<MLMessage*>* messages = [notification.userInfo objectForKey:@"messagesArray"];
    DDLogVerbose(@"notification manager got displayed messages notice with %lu entries", [messages count]);
    
    //do this in its own thread because we don't want to block the main thread or other threads here (the removal can take ~50ms)
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for(MLMessage* msg in messages)
        {
            if([msg.messageType isEqualToString:kMessageTypeStatus])
                return;
            
            NSString* idval = [self identifierWithMessage:msg];
            
            DDLogVerbose(@"Removing pending/deliverd notification for message '%@' with identifier '%@'...", msg.messageId, idval);
            [center removePendingNotificationRequestsWithIdentifiers:@[idval]];
            [center removeDeliveredNotificationsWithIdentifiers:@[idval]];
        }
        //update app badge
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalUpdateUnread object:nil];
    });
    
}

-(void) handleDeletedMessage:(NSNotification*) notification
{
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    MLMessage* message = [notification.userInfo objectForKey:@"message"];
    
    if([message.messageType isEqualToString:kMessageTypeStatus])
        return;
    
    DDLogVerbose(@"notification manager got deleted message notice: %@", message.messageId);
    NSString* idval = [self identifierWithMessage:message];
    
    [center removePendingNotificationRequestsWithIdentifiers:@[idval]];
    [center removeDeliveredNotificationsWithIdentifiers:@[idval]];
    
    //update app badge
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalUpdateUnread object:nil];
}

-(NSString*) identifierWithMessage:(MLMessage*) message
{
    return [NSString stringWithFormat:@"%@_%@", [self threadIdentifierWithMessage:message], message.messageId];
}

-(NSString*) threadIdentifierWithMessage:(MLMessage*) message
{
    return [NSString stringWithFormat:@"%@_%@", message.accountId, message.buddyName];
}

-(UNMutableNotificationContent*) updateBadgeForContent:(UNMutableNotificationContent*) content
{
    NSNumber* unreadMsgCnt = [[DataLayer sharedInstance] countUnreadMessages];
    NSInteger unread = 0;
    if(unreadMsgCnt != nil)
        unread = [unreadMsgCnt integerValue];
    DDLogVerbose(@"Raw badge value: %lu", (long)unread);
    DDLogDebug(@"Adding badge value: %lu", (long)unread);
    content.badge = [NSNumber numberWithInteger:unread];
    return content;
}

-(void) publishNotificationContent:(UNNotificationContent*) content withID:(NSString*) idval
{
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    
    //scheduling the notification in 2 seconds will make it possible to be deleted by XEP-0333 chat-markers received directly after the message
    //this is useful in catchup scenarios
    DDLogVerbose(@"notification manager: publishing notification in 2 seconds: %@", content);
    UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:idval content:content trigger:[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:2 repeats: NO]];
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        if(error)
            DDLogError(@"Error posting local notification: %@", error);
    }];
}

-(void) showNotificaionForMessage:(MLMessage*) message withSound:(BOOL) sound
{
    // always use legacy notifications if we should only show a generic "New Message" notifiation without name or content
    if(self.notificationPrivacySetting > DisplayOnlyName)
        return [self showLegacyNotificaionForMessage:message withSound:sound];
    
    // use modern communication notifications on ios >= 15.0 and legacy ones otherwise
    if(@available(iOS 15.0, macCatalyst 15.0, *))
    {
        DDLogDebug(@"Using communication notifications");
        return [self showModernNotificaionForMessage:message withSound:sound];
    }
    return [self showLegacyNotificaionForMessage:message withSound:sound];
}

-(void) showModernNotificaionForMessage:(MLMessage*) message withSound:(BOOL) sound API_AVAILABLE(ios(15.0), macosx(12.0))  //means: API_AVAILABLE(ios(15.0), maccatalyst(15.0))
{
    UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
    NSString* idval = [self identifierWithMessage:message];
    MLContact* contact = [MLContact createContactFromJid:message.buddyName andAccountNo:message.accountId];
    
    // only show msgText if allowed
    NSString* msgText = NSLocalizedString(@"Open app to see more", @"");
    if(self.notificationPrivacySetting == DisplayNameAndMessage)
    {
        //XEP-0245: The slash me Command
        if([message.messageText hasPrefix:@"/me "])
            msgText = [[MLXEPSlashMeHandler sharedInstance] stringSlashMeWithMessage:message];
        else
            msgText = message.messageText;
        
        // notification settings (TODO: is this reallyneeded for communication notifications?)
        content.body = msgText;
        content.threadIdentifier = [self threadIdentifierWithMessage:message];
        content.categoryIdentifier = @"message";
        
        // user info for answer etc. (TODO: is this really needed for communication notifications?)
        content.userInfo = @{
            @"fromContactJid": message.buddyName,
            @"fromContactAccountId": message.accountId,
            @"messageId": message.messageId
        };
        
        if([message.messageType isEqualToString:kMessageTypeFiletransfer])
            msgText = NSLocalizedString(@"Sent a File 📁", @"");
        else if([message.messageType isEqualToString:kMessageTypeUrl] && [[HelperTools defaultsDB] boolForKey:@"ShowURLPreview"])
            msgText = NSLocalizedString(@"Sent a Link 🔗", @"");
        else if([message.messageType isEqualToString:kMessageTypeGeo])
            msgText = NSLocalizedString(@"Sent a Location 📍", @"");
    }
    
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
    
    INPersonHandle* personHandle = [[INPersonHandle alloc] initWithValue:contact.contactJid type:INPersonHandleTypeEmailAddress label:contact.accountId];
    INImage* contactImage = [INImage imageWithImageData:UIImagePNGRepresentation(contact.avatar)];
    INPerson* sender = [[INPerson alloc] initWithPersonHandle:personHandle
                                                nameComponents:nil
                                                    displayName:message.contactDisplayName
                                                        image:contactImage
                                            contactIdentifier:nil
                                                customIdentifier:nil];
    INSendMessageIntent* intent = [[INSendMessageIntent alloc] initWithRecipients:nil
                                                                outgoingMessageType:INOutgoingMessageTypeOutgoingMessageText
                                                                            content:msgText
                                                                speakableGroupName:nil   //(message.isMuc ? [contact contactDisplayName] : nil)
                                                            conversationIdentifier:[self threadIdentifierWithMessage:message]
                                                                        serviceName:contact.accountId
                                                                            sender:sender
                                                                        attachments:nil];
    INInteraction* interaction = [[INInteraction alloc] initWithIntent:intent response:nil];
    interaction.direction = INInteractionDirectionIncoming;
    [interaction donateInteractionWithCompletion:^(NSError *error) {
        if(error)
            DDLogError(@"Could not donate interaction: %@", error);
        else
        {
            NSError* error = nil;
            UNNotificationContent* updatedContent = [content contentByUpdatingWithProvider:intent error:&error];
            if(error)
                DDLogError(@"Could not update notification content: %@", error);
            else
            {
                DDLogDebug(@"Publishing communication notification with id %@", idval);
                [self publishNotificationContent:updatedContent withID:idval];
            }
        }
    }];
}

-(void) showLegacyNotificaionForMessage:(MLMessage*) message withSound:(BOOL) sound
{
    UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
    MLContact* contact = [MLContact createContactFromJid:message.buddyName andAccountNo:message.accountId];
    NSString* idval = [self identifierWithMessage:message];
    
    // Only show contact name if allowed
    if(self.notificationPrivacySetting <= DisplayOnlyName)
    {
        content.title = [contact contactDisplayName];
        if(message.isMuc)
            content.subtitle = [NSString stringWithFormat:NSLocalizedString(@"%@ says:", @""), message.contactDisplayName];
    }
    else
        content.title = NSLocalizedString(@"New Message", @"");

    // only show msgText if allowed
    if(self.notificationPrivacySetting == DisplayNameAndMessage)
    {
        NSString* msgText = message.messageText;

        //XEP-0245: The slash me Command
        if([message.messageText hasPrefix:@"/me "])
            msgText = [[MLXEPSlashMeHandler sharedInstance] stringSlashMeWithMessage:message];
        
        content.body = msgText;
        content.threadIdentifier = [self threadIdentifierWithMessage:message];
        content.categoryIdentifier = @"message";
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
                        NSString* typeHint = (NSString*)kUTTypePNG;
                        if([mimeType isEqualToString:@"image/jpeg"])
                            typeHint = (NSString*)kUTTypeJPEG;
                        if([mimeType isEqualToString:@"image/png"])
                            typeHint = (NSString*)kUTTypePNG;
                        if([mimeType isEqualToString:@"image/gif"])
                            typeHint = (NSString*)kUTTypeGIF;
                        NSError *error;
                        attachment = [UNNotificationAttachment attachmentWithIdentifier:info[@"cacheId"] URL:[NSURL fileURLWithPath:info[@"cacheFile"]] options:@{UNNotificationAttachmentOptionsTypeHintKey:typeHint} error:&error];
                        if(error)
                            DDLogError(@"Error %@", error);
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
                    content.body = NSLocalizedString(@"🎵 A Audiomessage", @"");
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

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
