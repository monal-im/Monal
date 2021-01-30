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


int main(int argc, char *argv[]) {
    @autoreleasepool {
        //log unhandled exceptions
        NSSetUncaughtExceptionHandler(&logException);
        
        [HelperTools configureLogging];
        
        int retVal = UIApplicationMain(argc, argv, nil, NSStringFromClass([MonalAppDelegate class]));
        return retVal;
    }
}
