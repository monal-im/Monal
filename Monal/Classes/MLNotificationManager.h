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
#import "MLSoundManager.h"

/**
 Singleton object that will handle all sliders, alerts and sounds. listens for new message notification. 
 */
@interface MLNotificationManager : NSObject

+(MLNotificationManager*) sharedInstance;

@property (nonatomic, strong) MLContact* currentContact;
-(void) donateInteractionForOutgoingDBId:(NSNumber*) messageDBId    API_AVAILABLE(ios(15.0), macosx(12.0));  //means: API_AVAILABLE(ios(15.0),

@end
