//
//  HelperTools.m
//  Monal
//
//  Created by Friedrich Altheide on 08.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "HelperTools.h"
#import "DataLayer.h"

@implementation HelperTools

/*
 * create string containing the info when a user was seen the last time
 * return nil if no timestamp was found in the db
 */
+(NSString* _Nullable) lastInteractionFromJid:(NSString*) contactJid andAccountNo:(NSString*) accountNo
{
    NSDate* lastInteractionDate = [[DataLayer sharedInstance] lastInteractionFromJid:contactJid andAccountNo:accountNo];

    unsigned long lastInteractionTime = [lastInteractionDate timeIntervalSince1970]; // Date to epoch

    // get current timestamp
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    unsigned long currentTimestamp = currentTime;

    if(lastInteractionTime > 0 && lastInteractionTime <= currentTimestamp) {
        NSString* timeString;

        unsigned long diff = currentTimestamp - lastInteractionTime;
        if(diff / 60 < 1) {
            // less than one minute
            timeString = NSLocalizedString(@"Just seen", @"");
            diff = 0;
        } else if(diff / 60 < 2 * 60){
            // less than one hour
            timeString = NSLocalizedString(@"Last seen: %d min", @"");
            diff /= 60;
        } else if(diff / (60 * 60) < 2 * 24){
            // less than 24 hours
            timeString = NSLocalizedString(@"Last seen: %d hours", @"");
            diff /= 60 * 60;
        } else {
            // more than 24 hours
            timeString = NSLocalizedString(@"Last seen: %d days", @"");
            diff /= 60 * 60 * 24;
        }

        NSString* lastSeen = [NSString stringWithFormat:timeString, diff];
        return [NSString stringWithFormat:@"%@", lastSeen];
    } else {
        return nil;
    }
}

@end
