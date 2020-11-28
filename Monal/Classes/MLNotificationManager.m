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

-(void) handleNewMessage:(NSNotification*) notification
{
    MLMessage* message = [notification.userInfo objectForKey:@"message"];
    
    if([message.messageType isEqualToString:kMessageTypeStatus])
        return;
    
    DDLogVerbose(@"notification manager got new message notice: %@", message.messageText);
    BOOL muted = [[DataLayer sharedInstance] isMutedJid:message.actualFrom];
    if(!muted && message.shouldShowAlert)
    {
        if([HelperTools isInBackground])
        {
            DDLogVerbose(@"notification manager got new message notice in background: %@", message.messageText);
            [self showModernNotificaion:notification];
        }
        else
        {
            //don't show notifications for open chats
            if(
                ![message.from isEqualToString:self.currentContact.contactJid] &&
                ![message.to isEqualToString:self.currentContact.contactJid]
            )
                [self showModernNotificaion:notification];
        }
    }
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
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalUpdateUnread object:nil];
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
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalUpdateUnread object:nil];
}

-(NSString*) identifierWithMessage:(MLMessage*) message
{
    return [NSString stringWithFormat:@"%@_%@", [self threadIdentifierWithMessage:message], message.messageId];
}

-(NSString*) threadIdentifierWithMessage:(MLMessage*) message
{
    return [NSString stringWithFormat:@"%@_%@", message.accountId, message.from];
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
    DDLogInfo(@"Adding badge value: %lu", (long)unread);
    content.badge = [NSNumber numberWithInteger:unread];
    
    //scheduling the notification in 1.5 seconds will make it possible to be deleted by XEP-0333 chat-markers received directly after the message
    //this is useful in catchup scenarios
    DDLogVerbose(@"notification manager: publishing notification in 1.5 seconds: %@", content.body);
    UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:idval content:content trigger:[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1.5 repeats: NO]];
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        if(error)
            DDLogError(@"Error posting local notification: %@", error);
    }];
}

-(void) showModernNotificaion:(NSNotification*) notification
{
    MLMessage* message = [notification.userInfo objectForKey:@"message"];
    UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
    
    MLContact* contact = [[DataLayer sharedInstance] contactForUsername:message.from forAccount:message.accountId];
    
    // Only show contact name if allowed
    if(self.notificationPrivacySetting <= DisplayOnlyName) {
        content.title = [contact contactDisplayName];

        if(![message.from isEqualToString:message.actualFrom])
        {
            content.subtitle = [NSString stringWithFormat:@"%@ says:", message.actualFrom];
        }
    } else {
        content.title = NSLocalizedString(@"New Message", @"");
    }
    NSString* idval = [self identifierWithMessage:message];

    // only show msgText if allowed
    if(self.notificationPrivacySetting == DisplayNameAndMessage)
    {
        NSString* msgText = message.messageText;

        //XEP-0245: The slash me Command
        if([message.messageText hasPrefix:@"/me "])
        {
            BOOL isMuc = [[DataLayer sharedInstance] isBuddyMuc:message.from forAccount:message.accountId];
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
            @"from": message.from,
            @"accountId": message.accountId,
            @"messageId": message.messageId
        };

        if([[HelperTools defaultsDB] boolForKey:@"Sound"])
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
            if(info && [info[@"mimeType"] hasPrefix:@"image/"])
            {
                NSString* typeHint = (NSString*)kUTTypePNG;
                if([info[@"mimeType"] isEqualToString:@"image/jpeg"])
                    typeHint = (NSString*)kUTTypeJPEG;
                if([info[@"mimeType"] isEqualToString:@"image/png"])
                    typeHint = (NSString*)kUTTypePNG;
                if([info[@"mimeType"] isEqualToString:@"image/png"])
                    typeHint = (NSString*)kUTTypeGIF;
                NSError *error;
                UNNotificationAttachment* attachment = [UNNotificationAttachment attachmentWithIdentifier:info[@"cacheId"] URL:[NSURL fileURLWithPath:info[@"cacheFile"]] options:@{UNNotificationAttachmentOptionsTypeHintKey:typeHint} error:&error];
                if(attachment)
                    content.attachments = @[attachment];
                if(error)
                    DDLogError(@"Error %@", error);

                if(!content.attachments)
                    content.body = NSLocalizedString(@"Sent an Image 📷", @"");
                else
                    content.body = @"";

                [self publishNotificationContent:content withID:idval];
            }
            else        //TODO JIM: add support for more mime types
            {
                content.body = NSLocalizedString(@"Sent a File 📁", @"");
            }
            return;
        }
        else if([message.messageType isEqualToString:kMessageTypeUrl])
            content.body = NSLocalizedString(@"Sent a Link 🔗", @"");
        else if([message.messageType isEqualToString:kMessageTypeGeo])
            content.body = NSLocalizedString(@"Sent a Location 📍", @"");
    } else {
        content.body = NSLocalizedString(@"Open app to see more", @"");
    }
    [self publishNotificationContent:content withID:idval];
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
