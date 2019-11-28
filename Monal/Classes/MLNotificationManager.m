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

static const int ddLogLevel = LOG_LEVEL_VERBOSE;

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
    
    DDLogVerbose(@"notificaiton manager got new message notice %@", notification.userInfo);
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
    
    NSString *displayName = [[DataLayer sharedInstance] fullName:message.from forAccount:acctString];
    
    content.title = displayName.length>0?displayName:message.from;
    
    if(![message.from isEqualToString:message.actualFrom])
    {
        content.subtitle =[NSString stringWithFormat:@"%@ says:",message.actualFrom];
    }
    
    NSString *idval = [NSString stringWithFormat:@"%@_%@", [self identifierWithNotification:notification],message.messageId];
    
    content.body = message.messageText;
    content.userInfo= notification.userInfo;
    content.threadIdentifier =[self identifierWithNotification:notification];
    content.categoryIdentifier=@"Reply";
    
    if( [[NSUserDefaults standardUserDefaults] boolForKey:@"Sound"]==true)
    {
        NSString *filename = [[NSUserDefaults standardUserDefaults] objectForKey:@"AlertSoundFile"];
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
                content.body =@"Sent an Image 📷";
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
    else if([message.messageType isEqualToString:kMessageTypeUrl])
    {
        content.body =@"Sent a Link 🔗";
    }
    
    UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:idval
                                                                          content:content trigger:nil];
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        
    }];
}

-(void) showLegacyNotification:(NSNotification *)notification
{
    MLMessage *message =[notification.userInfo objectForKey:@"message"];
    NSString* acctString =message.accountId;
    NSString* fullName =[[DataLayer sharedInstance] fullName:message.from forAccount:acctString];
    
    NSString* nickName =[[DataLayer sharedInstance] nickName:message.from forAccount:acctString];
    
    NSString* nameToShow=message.from;
    
    if([nickName length]>0) nameToShow=nickName;
    else if([fullName length]>0) nameToShow=fullName;
    NSDate* theDate=[NSDate dateWithTimeIntervalSinceNow:0]; //immediate fire
    
    UIApplication* app = [UIApplication sharedApplication];
    NSArray*    oldNotifications = [app scheduledLocalNotifications];
    
    // Clear out the old notification before scheduling a new one.
    if ([oldNotifications count] > 0)
        [app cancelAllLocalNotifications];
    
    // Create a new notification
    UILocalNotification* alarm = [[UILocalNotification alloc] init];
    if (alarm)
    {
        //scehdule info
        alarm.fireDate = theDate;
        alarm.timeZone = [NSTimeZone defaultTimeZone];
        alarm.repeatInterval = 0;
        alarm.category=@"Reply";
        
        if([[NSUserDefaults standardUserDefaults] boolForKey:@"MessagePreview"]) {
            alarm.alertTitle  =nameToShow;
            alarm.alertBody =message.messageText;
        }  else {
            alarm.alertTitle =  nameToShow;
        }
        
        if( [[NSUserDefaults standardUserDefaults] boolForKey:@"Sound"]==true)
        {
            NSString *filename = [[NSUserDefaults standardUserDefaults] objectForKey:@"AlertSoundFile"];
            if(filename) {
                alarm.soundName=[NSString stringWithFormat:@"AlertSounds/%@.aif",filename];
            } else  {
                alarm.soundName=UILocalNotificationDefaultSoundName;
            }
        }
        alarm.userInfo=notification.userInfo;
        [app scheduleLocalNotification:alarm];
        DDLogVerbose(@"Scheduled local message alert ");
    }
}

-(void) presentAlert:(NSNotification *)notification
{
    if(([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
       || ([UIApplication sharedApplication].applicationState==UIApplicationStateInactive ))
    {
        if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"10.0")){
            [self showModernNotificaion:notification];
        }
        else  {
            [self showLegacyNotification:notification];
        }
    }
    else
    {
          MLMessage *message =[notification.userInfo objectForKey:@"message"];
        if(!([message.from isEqualToString:self.currentContact]) &&
           !([message.to isEqualToString:self.currentContact] ) )
            //  &&![[notification.userInfo objectForKey:@"from"] isEqualToString:@"Info"]
        {
            if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"10.0")){
                [self showModernNotificaion:notification];
            } else  {
                NSString* acctString =message.accountId;
                NSString* fullName =[[DataLayer sharedInstance] fullName:message.from forAccount:acctString];
                
                NSString* nameToShow=message.from;
                if([fullName length]>0) nameToShow=fullName;
                NSDate* theDate=[NSDate dateWithTimeIntervalSinceNow:0]; //immediate fire
                
                SlidingMessageViewController* slidingView= [[SlidingMessageViewController alloc] correctSliderWithTitle:nameToShow message:message.messageText user:message.from account:message.accountId];
                
                [self.window addSubview:slidingView.view];
                
                [slidingView showMsg];
            }
        }
    }
    
};

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
