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
@import UserNotifications;
@import CoreServices;

@interface MLNotificationManager ()

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
    return self;
}

#pragma mark message signals

-(void) handleNewMessage:(NSNotification*) notification
{
    MLMessage* message = [notification.userInfo objectForKey:@"message"];
    
    if([message.messageType isEqualToString:kMessageTypeStatus])
        return;
    
    DDLogVerbose(@"notification manager got new message notice: %@", message.messageText);
    [[DataLayer sharedInstance] isMutedJid:message.actualFrom withCompletion:^(BOOL muted) {
        if(!muted && message.shouldShowAlert)
        {
            if([HelperTools isInBackground])
                [self showModernNotificaion:notification];
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
    }];
}

-(NSString*) identifierWithNotification:(NSNotification*) notification
{
    MLMessage* message = [notification.userInfo objectForKey:@"message"];
    return [NSString stringWithFormat:@"%@_%@", message.accountId, message.from];
}

-(void) publishNotificationContent:(UNMutableNotificationContent*) content withID:(NSString*) idval
{
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    
    //this will add a badge having a minimum of 1 to make sure people see that something happened (even after swiping away all notifications)
    [[DataLayer sharedInstance] countUnreadMessagesWithCompletion:^(NSNumber *result) {
        NSInteger unread = 0;
        if(result)
            unread = [result integerValue];
        DDLogVerbose(@"Raw badge value: %lu", (long)unread);
        if(!unread)
            unread = 1;     //use this as fallback to always show a badge if a notification is shown
        DDLogInfo(@"Adding badge value: %lu", (long)unread);
        content.badge = [NSNumber numberWithInteger:unread];
        
        DDLogVerbose(@"notification manager: publishing notification: %@", content.body);
        UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:idval content:content trigger:nil];
        [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
            if(error)
                DDLogError(@"Error posting local notification: %@", error);
        }];
    }];
}

-(void) showModernNotificaion:(NSNotification*) notification
{
    MLMessage* message = [notification.userInfo objectForKey:@"message"];
    UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
    
    [[DataLayer sharedInstance] fullNameForContact:message.from inAccount:message.accountId withCompeltion:^(NSString *displayName) {
        
        content.title = displayName.length>0 ? displayName : message.from;
        
        if(![message.from isEqualToString:message.actualFrom])
        {
            content.subtitle = [NSString stringWithFormat:@"%@ says:", message.actualFrom];
        }
        
        NSString* idval = [NSString stringWithFormat:@"%@_%@", [self identifierWithNotification:notification], message.messageId];
        
        content.body = message.messageText;
        content.threadIdentifier = [self identifierWithNotification:notification];
        content.categoryIdentifier = @"Reply";
        
        if([[HelperTools defaultsDB] boolForKey:@"Sound"])
        {
            NSString* filename = [[HelperTools defaultsDB] objectForKey:@"AlertSoundFile"];
            if(filename)
                content.sound = [UNNotificationSound soundNamed:[NSString stringWithFormat:@"AlertSounds/%@.aif",filename]];
            else
                content.sound = [UNNotificationSound defaultSound];
        }
        
        if([message.messageType isEqualToString:kMessageTypeImage])
        {
            [[MLImageManager sharedInstance] imageURLForAttachmentLink:message.messageText withCompletion:^(NSURL * _Nullable url) {
                if(url)
                {
                    NSError *error;
                    UNNotificationAttachment* attachment = [UNNotificationAttachment attachmentWithIdentifier:[[NSUUID UUID] UUIDString] URL:url options:@{UNNotificationAttachmentOptionsTypeHintKey:(NSString*) kUTTypePNG} error:&error];
                    if(attachment)
                        content.attachments = @[attachment];
                    if(error)
                        DDLogError(@"Error %@", error);
                }
                
                if(!content.attachments)
                    content.body = NSLocalizedString(@"Sent an Image 📷", @"");
                else
                    content.body = @"";
                
                [self publishNotificationContent:content withID:idval];
            }];
            return;
        }
        else if([message.messageType isEqualToString:kMessageTypeUrl])
            content.body = NSLocalizedString(@"Sent a Link 🔗", @"");
        else if([message.messageType isEqualToString:kMessageTypeGeo])
            content.body = NSLocalizedString(@"Sent a location 📍", @"");
        
        [self publishNotificationContent:content withID:idval];
    }];
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
