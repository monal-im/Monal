//
//  MLNotificationManager.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/20/13.
//
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"
#import "SlidingMessageViewController.h"
#import "DataLayer.h"

/**
 Singleton object that will handle all sliders, alerts and sounds. listens for new message notification. 
 */
@interface MLNotificationManager : NSObject
{
    
}

+ (MLNotificationManager* )sharedInstance;

@property (nonatomic, weak) UIWindow* window;

/**
 if in chat with this user then dont push messages for this user when not locked
 */
@property (nonatomic, strong) NSString* currentContact;

/**
 if in chat with this account's user then dont push messages for this user when not locked
 */
@property (nonatomic, strong) NSString* currentAccountNo;


/**
 handles the notification. 
 1. background will show alert
 2. foreground will show slider
 */
-(void) handleNewMessage:(NSNotification *)notification;

@end
