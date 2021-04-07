//
//  main.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "HelperTools.h"
#import "MonalAppDelegate.h"
#import "MLDefinitions.h"
#import "DataLayer.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        //log unhandled exceptions
        NSSetUncaughtExceptionHandler(&logException);

        [HelperTools configureLogging];

        // check start arguments
        if([NSProcessInfo.processInfo.arguments containsObject:@"--reset"])
        {
            // reset db
            NSFileManager* fileManager = [NSFileManager defaultManager];
            NSURL* containerUrl = [fileManager containerURLForSecurityApplicationGroupIdentifier:kAppGroup];
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
                assert(err == nil);
            }

            // reset NSUserDefaults
            [[NSUserDefaults alloc] removePersistentDomainForName:kAppGroup];
        }
        else if([NSProcessInfo.processInfo.arguments containsObject:@"--invalidateAccountStates"])
        {
            [[DataLayer sharedInstance] invalidateAllAccountStates];
        }
        int retVal = UIApplicationMain(argc, argv, nil, NSStringFromClass([MonalAppDelegate class]));
        return retVal;
    }
}
