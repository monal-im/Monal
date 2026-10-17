//
//  main.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <monalxmpp/HelperTools.h>
#import "MonalAppDelegate.h"
#import <monalxmpp/DataLayer.h>
#import <monalxmpp/MLConstants.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        [HelperTools initSystem];
        
        // check start arguments
        // reset sworim and ipc database for UI Tests
        if([NSProcessInfo.processInfo.arguments containsObject:@"--reset"])
        {
            // reset db
            NSFileManager* fileManager = [NSFileManager defaultManager];
            NSURL* containerUrl = [HelperTools getContainerURLForPathComponents:@[]];
            NSArray<NSString*>* dbPaths = @[
                [[containerUrl path] stringByAppendingPathComponent:@"sworim.sqlite"],
                [[containerUrl path] stringByAppendingPathComponent:@"sworim.sqlite-shm"],
                [[containerUrl path] stringByAppendingPathComponent:@"sworim.sqlite-wal"],
                [[containerUrl path] stringByAppendingPathComponent:@"ipc.sqlite"],
                [[containerUrl path] stringByAppendingPathComponent:@"ipc.sqlite-shm"],
                [[containerUrl path] stringByAppendingPathComponent:@"ipc.sqlite-wal"]
            ];
            for(NSString* path in dbPaths)
            {
                NSError* err;
                if([fileManager fileExistsAtPath:path])
                    [fileManager removeItemAtPath:path error:&err];
                MLAssert(err == nil, @"Error cleaning up DB!");
            }

            // reset NSUserDefaults
            [[NSUserDefaults alloc] removePersistentDomainForName:kAppGroup];
        }
        // invalidate account states
        if([NSProcessInfo.processInfo.arguments containsObject:@"--disableAnimations"])
            [UIView setAnimationsEnabled:NO];
        // invalidate account states
        if([NSProcessInfo.processInfo.arguments containsObject:@"--invalidateAccountStates"])
            [[DataLayer sharedInstance] invalidateAllAccountStates];
        
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([MonalAppDelegate class]));
    }
}
