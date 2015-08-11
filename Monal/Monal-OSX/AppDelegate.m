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
#import "DataLayer.h"


@interface AppDelegate ()

@property (nonatomic , strong)  MASPreferencesWindowController *preferencesWindow;
@property (nonatomic , weak)  MLAccountSettings *accountsVC;
@property (nonatomic , weak)  MLPresenceSettings *presenceVC;
@property (nonatomic , weak)  MLDisplaySettings *displayVC;


@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application

#ifdef  DEBUG
    [DDLog addLogger:[DDASLLogger sharedInstance]];
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    self.fileLogger = [[DDFileLogger alloc] init];
    self.fileLogger.rollingFrequency = 60 * 60 * 24; // 24 hour rolling
    self.fileLogger.logFileManager.maximumNumberOfLogFiles = 5;
    self.fileLogger.maximumFileSize=1024 * 500;
    [DDLog addLogger:self.fileLogger];
#endif
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    
      [[MLXMPPManager sharedInstance] connectIfNecessary];
    
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

#pragma mark -- notifications
-(void) handleNewMessage:(NSNotification *)notification;
{
    NSUserNotification *alert =[[NSUserNotification alloc] init];
    NSString* acctString =[NSString stringWithFormat:@"%ld", (long)[[notification.userInfo objectForKey:@"accountNo"] integerValue]];
    NSString* fullName =[[DataLayer sharedInstance] fullName:[notification.userInfo objectForKey:@"from"] forAccount:acctString];
    
    NSString* nameToShow=[notification.userInfo objectForKey:@"from"];
    if([fullName length]>0) nameToShow=fullName;
    
    alert.title= nameToShow;
    alert.informativeText=[notification.userInfo objectForKey:@"messageText"]; 
    
    //alert.contentImage;
    
    [[NSUserNotificationCenter defaultUserNotificationCenter] scheduleNotification:alert];
}

@end
