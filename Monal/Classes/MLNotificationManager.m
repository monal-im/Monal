//
//  MLNotificationManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/20/13.
//
//

#import "MLNotificationManager.h"
#import "MLImageManager.h"
#import "MLMessage.h"
@import UserNotifications;
@import CoreServices;

@interface MLNotificationManager ()
@property (nonatomic, strong) NSMutableArray *tempNotificationIds;

@end



@implementation MLNotificationManager

+ (MLNotificationManager* )sharedInstance
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
    self=[super init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    self.tempNotificationIds = [[NSMutableArray alloc] init];
    
    return self;
}

#pragma mark message signals

-(void) handleNewMessage:(NSNotification *)notification
{
    MLMessage *message =[notification.userInfo objectForKey:@"message"];
    
    if([message.messageType isEqualToString:kMessageTypeStatus]) return;
    
    DDLogVerbose(@"notification manager got new message notice %@", notification.userInfo);
    [[DataLayer sharedInstance] isMutedJid:message.actualFrom withCompletion:^(BOOL muted) {
        if(!muted){
            
            if (message.shouldShowAlert) {
                dispatch_async(dispatch_get_main_queue(),
                               ^{
                    [self presentAlert:notification];
                });
            }
        }
    }];
}

-(NSString *) identifierWithNotification:(NSNotification *) notification
{
    MLMessage *message =[notification.userInfo objectForKey:@"message"];
    
    return [NSString stringWithFormat:@"%@_%@",
            message.accountId,
            message.from];
    
}


/**
 for ios10 and up
 */
-(void) showModernNotificaion:(NSNotification *)notification
{
    MLMessage *message =[notification.userInfo objectForKey:@"message"];
    UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
    NSString* acctString = message.accountId;
    
    [[DataLayer sharedInstance] fullNameForContact:message.from inAccount:acctString withCompeltion:^(NSString *displayName) {
        
        content.title = displayName.length>0?displayName:message.from;
        
        if(![message.from isEqualToString:message.actualFrom])
        {
            content.subtitle =[NSString stringWithFormat:@"%@ says:",message.actualFrom];
        }
        
        NSString *idval = [NSString stringWithFormat:@"%@_%@", [self identifierWithNotification:notification],message.messageId];
        
        content.body = message.messageText;
        // content.userInfo= notification.userInfo;
        content.threadIdentifier =[self identifierWithNotification:notification];
        content.categoryIdentifier=@"Reply";
        
        if( [DEFAULTS_DB boolForKey:@"Sound"]==true)
        {
            NSString *filename = [DEFAULTS_DB objectForKey:@"AlertSoundFile"];
            if(filename) {
                content.sound = [UNNotificationSound soundNamed:[NSString stringWithFormat:@"AlertSounds/%@.aif",filename]];
            } else  {
                content.sound = [UNNotificationSound defaultSound];
            }
        }
        
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        if([message.messageType isEqualToString:kMessageTypeImage])
        {
            [[MLImageManager sharedInstance] imageURLForAttachmentLink:message.messageText withCompletion:^(NSURL * _Nullable url) {
                if(url) {
                    NSError *error;
                    UNNotificationAttachment* attachment= [UNNotificationAttachment attachmentWithIdentifier:idval URL:url options:@{UNNotificationAttachmentOptionsTypeHintKey:(NSString*) kUTTypePNG} error:&error];
                    if(attachment) content.attachments=@[attachment];
                    if(error) {
                        DDLogError(@"Error %@", error);
                    }
                }
                
                if(!content.attachments)  {
                    content.body =NSLocalizedString(@"Sent an Image 📷",@ "");
                }else  {
                    content.body=@"";
                }
                UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:idval
                                                                                      content:content trigger:nil];
                [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
                    
                }];
                
            }];
            return;
        }
        else if([message.messageType isEqualToString:kMessageTypeUrl]) {
            content.body =NSLocalizedString(@"Sent a Link 🔗",@ "");
        } else if([message.messageType isEqualToString:kMessageTypeGeo]) {
            content.body =NSLocalizedString(@"Sent a location📍",@ "");
        }
        
        UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:idval
                                                                              content:content trigger:nil];
        [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
            
        }];
    }];
}


-(void) presentAlert:(NSNotification *)notification
{
    if(([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
       || ([UIApplication sharedApplication].applicationState==UIApplicationStateInactive ))
    {
        [self showModernNotificaion:notification];
    }
    else
    {
          MLMessage *message =[notification.userInfo objectForKey:@"message"];
        if(!([message.from isEqualToString:self.currentContact.contactJid]) &&
           !([message.to isEqualToString:self.currentContact.contactJid] ) )
            //  &&![[notification.userInfo objectForKey:@"from"] isEqualToString:@"Info"]
        {
                [self showModernNotificaion:notification];
        }
    }
    
};

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
