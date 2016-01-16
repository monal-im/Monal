//
//  AppDelegate.h
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 6/9/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "DDLog.h"
#import "DDASLLogger.h"
#import "DDFileLogger.h"
#import "DDTTYLogger.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic , weak) NSWindowController* mainWindowController;
@property (nonatomic, strong)  DDFileLogger *fileLogger;


@end

