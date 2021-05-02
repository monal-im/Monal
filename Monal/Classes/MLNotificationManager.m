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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleDisplayedMessage:) name:kMonalDisplayedMessageNotice object:nil];
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
    MLMessage* message = [notification.userInfo objectForKey:@"message"];
    NSString* idval = [self identifierWithMessage:message];
    
    //check if we already show any notifications and update them if necessary (e.g. publish a second notification having the same id)
    [[UNUserNotificationCenter currentNotificationCenter] getPendingNotificationRequestsWithCompletionHandler:^(NSArray* requests) {
        for(UNNotificationRequest* request in requests)
            if([request.identifier isEqualToString:idval])
            {
                [self internalMessageHandlerWithMessage:message showAlert:YES andSound:YES];
            }
    }];
    [[UNUserNotificationCenter currentNotificationCenter] getDeliveredNotificationsWithCompletionHandler:^(NSArray* notifications) {
        for(UNNotification* notification in notifications)
             if([notification.request.identifier isEqualToString:idval])
            {
                [self internalMessageHandlerWithMessage:message showAlert:YES andSound:NO];
            }
    }];
}

-(void) handleNewMessage:(NSNotification*) notification
{
    MLMessage* message = [notification.userInfo objectForKey:@"message"];
    BOOL showAlert = notification.userInfo[@"showAlert"] ? [notification.userInfo[@"showAlert"] boolValue] : NO;
    [self internalMessageHandlerWithMessage:message showAlert:showAlert andSound:YES];
}

-(void) internalMessageHandlerWithMessage:(MLMessage*) message showAlert:(BOOL) showAlert andSound:(BOOL) sound
{
    if([message.messageType isEqualToString:kMessageTypeStatus])
        return;
    
    DDLogVerbose(@"notification manager should show notification for: %@", message.messageText);
    BOOL muted = [[DataLayer sharedInstance] isMutedJid:message.buddyName onAccount:message.accountId];
    if(message.isMuc == YES)
    {
        if(message.participantJid != nil) {
            muted |= [[DataLayer sharedInstance] isMutedJid:message.participantJid onAccount:message.accountId];
        }
    }
    if(muted == NO && showAlert == YES)
    {
        if([HelperTools isNotInFocus])
        {
            DDLogVerbose(@"notification manager should show notification in background: %@", message.messageText);
            [self showModernNotificaionForMessage:message withSound:sound];
        }
        else
        {
            //don't show notifications for open chats
            if(
                ![message.buddyName isEqualToString:self.currentContact.contactJid]
            )
                [self showModernNotificaionForMessage:message withSound:sound];
            else
                DDLogDebug(@"not showing notification: chat is open");
        }
    }
    else
        DDLogDebug(@"not showing notification: showAlert is NO (or this contact got muted)");
}

-(void) handleDisplayedMessage:(NSNotification*) notification
{
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    MLMessage* message = [notification.userInfo objectForKey:@"message"];
    
    if([message.messageType isEqualToString:kMessageTypeStatus])
        return;
    
    DDLogVerbose(@"notification manager got displayed message notice: %@", message.messageId);
    NSString* idval = [self identifierWithMessage:message];
    
    [center removePendingNotificationRequestsWithIdentifiers:@[idval]];
    [center removeDeliveredNotificationsWithIdentifiers:@[idval]];
    
    //update app badge
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalUpdateUnread object:nil];
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

-(void) publishNotificationContent:(UNMutableNotificationContent*) content withID:(NSString*) idval
{
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    
    //this will add a badge having a minimum of 1 to make sure people see that something happened (even after swiping away all notifications)
    NSNumber* unreadMsgCnt = [[DataLayer sharedInstance] countUnreadMessages];
    NSInteger unread = 0;
    if(unreadMsgCnt != nil)
        unread = [unreadMsgCnt integerValue];
    DDLogVerbose(@"Raw badge value: %lu", (long)unread);
    if(!unread)
        unread = 1;     //use this as fallback to always show a badge if a notification is shown
    DDLogDebug(@"Adding badge value: %lu", (long)unread);
    content.badge = [NSNumber numberWithInteger:unread];
    
    //scheduling the notification in 2 seconds will make it possible to be deleted by XEP-0333 chat-markers received directly after the message
    //this is useful in catchup scenarios
    DDLogVerbose(@"notification manager: publishing notification in 2 seconds: %@", content.body);
    UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:idval content:content trigger:[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:2 repeats: NO]];
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        if(error)
            DDLogError(@"Error posting local notification: %@", error);
    }];
}

-(void) showModernNotificaionForMessage:(MLMessage*) message withSound:(BOOL) sound
{
    UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
    MLContact* contact = [MLContact contactFromJid:message.buddyName andAccountNo:message.accountId];
    NSString* idval = [self identifierWithMessage:message];
    
    // Only show contact name if allowed
    if(self.notificationPrivacySetting <= DisplayOnlyName)
    {
        content.title = [contact contactDisplayName];
        if(message.isMuc)
            content.subtitle = [NSString stringWithFormat:NSLocalizedString(@"%@ says:", @""), message.actualFrom];
    }
    else
        content.title = NSLocalizedString(@"New Message", @"");

    // only show msgText if allowed
    if(self.notificationPrivacySetting == DisplayNameAndMessage)
    {
        NSString* msgText = message.messageText;

        //XEP-0245: The slash me Command
        if([message.messageText hasPrefix:@"/me "])
        {
            BOOL isMuc = [[DataLayer sharedInstance] isBuddyMuc:message.buddyName forAccount:message.accountId];
            msgText = [[MLXEPSlashMeHandler sharedInstance] stringSlashMeWithAccountId:message.accountId
                                                                           displayName:[contact contactDisplayName]
                                                                            actualFrom:message.actualFrom
                                                                               message:message.messageText
                                                                               isGroup:isMuc];
        }
        
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
                content.sound = [UNNotificationSound soundNamed:[NSString stringWithFormat:@"AlertSounds/%@.aif",filename]];
            else
                content.sound = [UNNotificationSound defaultSound];
        }

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
    [self publishNotificationContent:content withID:idval];
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
