//
//  MLNotificationManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/20/13.
//
//

#import "MLNotificationManager.h"


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
    return self;
}

#pragma mark message signals

-(void) handleNewMessage:(NSNotification *)notification
{
    debug_NSLog(@"notificaiton manager got new message notice %@", notification.userInfo);

    dispatch_async(dispatch_get_main_queue(),
                  ^{
                      
                      if(([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
                         || ([UIApplication sharedApplication].applicationState==UIApplicationStateInactive ))
                      {
                          
                          //increment badge
                          [UIApplication sharedApplication].applicationIconBadgeNumber++;
                          //present notification
                          
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
                              
                              if([[NSUserDefaults standardUserDefaults] boolForKey:@"MessagePreview"])
                                  alarm.alertBody = [NSString stringWithFormat: @"%@: %@", [notification.userInfo objectForKey:@"from"], [notification.userInfo objectForKey:@"messageText"]];
                              else
                                  alarm.alertBody =  [notification.userInfo objectForKey:@"from"];
                              
                              if( [[NSUserDefaults standardUserDefaults] boolForKey:@"Sound"]==true)
                              {
                                  alarm.soundName=UILocalNotificationDefaultSoundName; 
                              }
                              
                              alarm.userInfo=notification.userInfo;
                              
                              [app scheduleLocalNotification:alarm];
                              
                              //	[app presentLocalNotificationNow:alarm];
                              debug_NSLog(@"Scheduled local message alert "); 
                              
                          }
                          
   
                      }
                      else
                   {
                       if(!([[notification.userInfo objectForKey:@"from"] isEqualToString:self.currentContact] &&
                          [[notification.userInfo objectForKey:@"acountNo"] isEqualToString:self.currentAccountNo])
                        //  &&![[notification.userInfo objectForKey:@"from"] isEqualToString:@"Info"]
                          )
                       {
                       
                      SlidingMessageViewController* slidingView= [[SlidingMessageViewController alloc] correctSliderWithTitle:[notification.userInfo objectForKey:@"from"] message:[notification.userInfo objectForKey:@"messageText"] userfilename:[notification.userInfo objectForKey:@"from"] user:[notification.userInfo objectForKey:@"from"]];
                       
                       [self.window addSubview:slidingView.view];
                       
                       [slidingView showMsg];
                       }
                       
                   }
                      
                  });
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
