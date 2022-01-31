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

@property (nonatomic, strong) MLContact* currentContact;
-(void) waitForDonations;

@end
