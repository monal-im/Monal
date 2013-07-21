//
//  MLNotificationManager.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/20/13.
//
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"

/**
 Singleton object that will handle all sliders, alerts and sounds. listens for new message notification. 
 */
@interface MLNotificationManager : NSObject
{
    
}

+ (MLNotificationManager* )sharedInstance;

/**
 handles the notification. 
 1. background will show alert
 2. foreground will show slider
 */
-(void) handleNewMessage:(NSNotification *)notification;

@end
