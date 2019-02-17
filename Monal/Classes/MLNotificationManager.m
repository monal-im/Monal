//
//  MLNotificationManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/20/13.
//
//

#import "MLNotificationManager.h"
@import UserNotifications;

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
    DDLogVerbose(@"notificaiton manager got new message notice %@", notification.userInfo);
    [[DataLayer sharedInstance] isMutedJid:[notification.userInfo objectForKey:@"from"] withCompletion:^(BOOL muted) {
        if(!muted){
            
            if ([[notification.userInfo objectForKey:@"showAlert"] boolValue]) {
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
    return [NSString stringWithFormat:@"%@_%@",
            [notification.userInfo objectForKey:@"accountNo"],
            [notification.userInfo objectForKey:@"from"]];
            
}


/**
 for ios10 and up
 */
-(void) showModernNotificaion:(NSNotification *)notification
{
    UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
    content.title =[notification.userInfo objectForKey:@"from"];
    
    if(![[notification.userInfo objectForKey:@"from"] isEqualToString:[notification.userInfo objectForKey:@"from"] ])
    {
        content.subtitle =[NSString stringWithFormat:@"%@ says:",[notification.userInfo objectForKey:@"actuallyfrom"]];
    }
    
    content.body =[notification.userInfo objectForKey:@"messageText"];
    content.userInfo= notification.userInfo;
    content.threadIdentifier =[self identifierWithNotification:notification];
    content.categoryIdentifier=@"Reply";
   
    if([[notification.userInfo objectForKey:@"messageType"] isEqualToString:kMessageTypeImage])
    {
        content.body =@"Sent an Image 📷";
    }
    
    if([[notification.userInfo objectForKey:@"messageType"] isEqualToString:kMessageTypeUrl])
    {
        content.body =@"Sent a Link 🔗";
    }
    
    if( [[NSUserDefaults standardUserDefaults] boolForKey:@"Sound"]==true)
    {
        NSString *filename = [[NSUserDefaults standardUserDefaults] objectForKey:@"AlertSoundFile"];
        if(filename) {
            content.sound = [UNNotificationSound soundNamed:[NSString stringWithFormat:@"AlertSounds/%@.aif",filename]];
        } else  {
            content.sound = [UNNotificationSound defaultSound];
        }
    }
    
    NSString *idval = [NSString stringWithFormat:@"%@_%@", [self identifierWithNotification:notification],[notification.userInfo objectForKey:@"messageid"]];
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:idval
                                                                          content:content trigger:nil];
    
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        
    }];

}

-(void) showLegacyNotification:(NSNotification *)notification
{
    
    NSString* acctString =[NSString stringWithFormat:@"%ld", (long)[[notification.userInfo objectForKey:@"accountNo"] integerValue]];
    NSString* fullName =[[DataLayer sharedInstance] fullName:[notification.userInfo objectForKey:@"from"] forAccount:acctString];
    
    NSString* nameToShow=[notification.userInfo objectForKey:@"from"];
    if([fullName length]>0) nameToShow=fullName;
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
            alarm.alertBody =[notification.userInfo objectForKey:@"messageText"];
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
        if(!([[notification.userInfo objectForKey:@"from"] isEqualToString:self.currentContact]) &&
           !([[notification.userInfo objectForKey:@"to"] isEqualToString:self.currentContact] ) )
            //  &&![[notification.userInfo objectForKey:@"from"] isEqualToString:@"Info"]
        {
            if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"10.0")){
                [self showModernNotificaion:notification];
            } else  {
                NSString* acctString =[NSString stringWithFormat:@"%ld", (long)[[notification.userInfo objectForKey:@"accountNo"] integerValue]];
                NSString* fullName =[[DataLayer sharedInstance] fullName:[notification.userInfo objectForKey:@"from"] forAccount:acctString];
                
                NSString* nameToShow=[notification.userInfo objectForKey:@"from"];
                if([fullName length]>0) nameToShow=fullName;
                NSDate* theDate=[NSDate dateWithTimeIntervalSinceNow:0]; //immediate fire
                
                SlidingMessageViewController* slidingView= [[SlidingMessageViewController alloc] correctSliderWithTitle:nameToShow message:[notification.userInfo objectForKey:@"messageText"] user:[notification.userInfo objectForKey:@"from"] account:[notification.userInfo objectForKey:@"accountNo"] ];
                
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
