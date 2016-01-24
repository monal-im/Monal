//
//  AppDelegate.m
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 6/9/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "AppDelegate.h"

#import "MASPreferencesWindowController.h"
#import "MLAccountSettings.h"
#import "MLDisplaySettings.h"
#import "MLPresenceSettings.h"
#import "MLXMPPManager.h"

#import "NXOAuth2.h"

#import "Countly.h"
#import <Fabric/Fabric.h>
#import <Crashlytics/Crashlytics.h>
#import "DDLog.h"

static const int ddLogLevel = LOG_LEVEL_VERBOSE;

@interface AppDelegate ()

@property (nonatomic , strong) MASPreferencesWindowController *preferencesWindow;
@property (nonatomic , weak)  MLAccountSettings *accountsVC;
@property (nonatomic , weak)  MLPresenceSettings *presenceVC;
@property (nonatomic , weak)  MLDisplaySettings *displayVC;


@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
  
#ifdef  DEBUG
    [DDLog addLogger:[DDASLLogger sharedInstance]];
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    self.fileLogger = [[DDFileLogger alloc] init];
    self.fileLogger.rollingFrequency = 60 * 60 * 24; // 24 hour rolling
    self.fileLogger.logFileManager.maximumNumberOfLogFiles = 5;
    self.fileLogger.maximumFileSize=1024 * 500;
    [DDLog addLogger:self.fileLogger];
#endif
    
    [[MLXMPPManager sharedInstance] connectIfNecessary];
    
    [[Countly sharedInstance] startOnCloudWithAppKey:@"2a165fc42c1c5541e49b024a9e75d155cdde999e"];
    
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"NSApplicationCrashOnExceptions": @YES }];
    [Fabric with:@[[Crashlytics class]]];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receivedSleepNotification:)
                                                               name: NSWorkspaceWillSleepNotification object: NULL];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receivedWakeNotification:)
                                                               name: NSWorkspaceDidWakeNotification object: NULL];

    
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag{
    
    if(flag==NO){
        [self.mainWindowController showWindow:self];
    }
    return YES;	
}


-(IBAction)displayWindow:(id)sender;
{
    [self.mainWindowController showWindow:self];
}

#pragma mark - device sleep 
- (void) receivedSleepNotification: (NSNotification*) notificaiton
{
    DDLogVerbose(@"Device Sleeping");
    [[MLXMPPManager sharedInstance] logoutAll];
}

- (void) receivedWakeNotification: (NSNotification*) notification
{
    DDLogVerbose(@"Device Waking");
    [[MLXMPPManager sharedInstance] connectIfNecessary];
}

#pragma mark  - Actions
-(void) linkVCs
{
    NSStoryboard *storyboard= [NSStoryboard storyboardWithName:@"Main" bundle:nil];
    if(!self.accountsVC)
    {
        self.accountsVC = [storyboard instantiateControllerWithIdentifier:@"accounts"];        
    }
    
    if(!self.presenceVC)
    {
        self.presenceVC = [storyboard instantiateControllerWithIdentifier:@"presence"];
    }
    
    if(!self.displayVC)
    {
        self.displayVC = [storyboard instantiateControllerWithIdentifier:@"display"];
    }
    
}

-(IBAction)showPreferences:(id)sender
{
    [self linkVCs];
    if(!self.preferencesWindow) {
        NSArray *array = @[self.accountsVC, self.presenceVC, self.displayVC];
        self.preferencesWindow = [[MASPreferencesWindowController alloc] initWithViewControllers:array];
    }
    [self.preferencesWindow showWindow:self];
    
}



@end
