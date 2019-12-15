//
//  AppDelegate.h
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 6/9/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>
@import CocoaLumberjack;

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>

@property (nonatomic , weak) NSWindowController* mainWindowController;
@property (nonatomic, strong)  DDFileLogger *fileLogger;

@property (nonatomic , weak) IBOutlet NSMenuItem *encryptionKeys;
@property (nonatomic , weak) IBOutlet NSMenuItem *serverDetails;
@property (nonatomic , weak) IBOutlet NSMenuItem *mamPrefs;



@end

