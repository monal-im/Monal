//
//  MLNotificationManager.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/20/13.
//
//

#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import "MLConstants.h"
#import "DataLayer.h"

/**
 Singleton object that will handle all sliders, alerts and sounds. listens for new message notification. 
 */
@interface MLNotificationManager : NSObject

+(MLNotificationManager*) sharedInstance;

/**
 if in chat with this user then dont push messages for this user when not locked
 */
@property (nonatomic, strong) MLContact* currentContact;

/**
 handles the notification. 
 1. background will show alert
 2. foreground will show slider
 */
-(void) handleNewMessage:(NSNotification*) notification;

@end
