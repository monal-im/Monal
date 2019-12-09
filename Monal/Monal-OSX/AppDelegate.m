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
#import "MLCloudStorageSettings.h"
#import "MLOptOutSettings.h"
#import "MLXMPPManager.h"

#import "NXOAuth2.h"

#import <Fabric/Fabric.h>
#import <Crashlytics/Crashlytics.h>

#import "DataLayer.h"




@interface AppDelegate ()

@property (nonatomic , strong) MASPreferencesWindowController *preferencesWindow;
@property (nonatomic , weak)  MLAccountSettings *accountsVC;
@property (nonatomic , weak)  MLPresenceSettings *presenceVC;
@property (nonatomic , weak)  MLDisplaySettings *displayVC;
@property (nonatomic , weak)  MLCloudStorageSettings *cloudVC;
@property (nonatomic , weak)  MLOptOutSettings *optOutVC;
@property (nonatomic , strong) id <NSObject> activity;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
  

    [DDLog addLogger:[DDASLLogger sharedInstance]];
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
#ifdef  DEBUG
    self.fileLogger = [[DDFileLogger alloc] init];
    self.fileLogger.rollingFrequency = 60 * 60 * 24; // 24 hour rolling
    self.fileLogger.logFileManager.maximumNumberOfLogFiles = 5;
    self.fileLogger.maximumFileSize=1024 * 500;
    [DDLog addLogger:self.fileLogger];
#endif
    
    [[MLXMPPManager sharedInstance] connectIfNecessary];
    
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"NSApplicationCrashOnExceptions": @YES }];
    [Fabric with:@[[Crashlytics class]]];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receivedSleepNotification:)
                                                               name: NSWorkspaceWillSleepNotification object: NULL];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receivedWakeNotification:)
                                                               name: NSWorkspaceDidWakeNotification object: NULL];
   
    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self andSelector:@selector(handleURLEvent:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
    
    //Dropbox
    DBSession *dbSession = [[DBSession alloc]
                            initWithAppKey:@"a134q2ecj1hqa59"
                            appSecret:@"vqsf5vt6guedlrs"
                            root:kDBRootAppFolder];
    [DBSession setSharedSession:dbSession];


    NSActivityOptions options = NSActivityUserInitiatedAllowingIdleSystemSleep;
    NSString *reason = @"Monal needs it's network connection. No napping.";
    self.activity = [[NSProcessInfo processInfo] beginActivityWithOptions:options reason:reason];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [[MLXMPPManager sharedInstance] logoutAll];
    [[NSProcessInfo processInfo] endActivity:self.activity];
    self.activity = nil;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag{
    
    if(flag==NO){
        [self.mainWindowController showWindow:self];
    }
    return YES;	
}

-(void) application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls
{
    NSURL *url= [urls firstObject];
    [[NXOAuth2AccountStore sharedStore] handleRedirectURL: url];
}



- (void)handleURLEvent:(NSAppleEventDescriptor*)event
        withReplyEvent:(NSAppleEventDescriptor*)replyEvent
{
//    if ([[DBSession sharedSession] handleOpenURL:[event paramDescriptorForKeyword:keyDirectObject]]) {
//        if ([[DBSession sharedSession] isLinked]) {
//            DDLogVerbose(@"App linked successfully!");
//            // At this point you can start making API calls
//        }
    
 //   }
    // Add whatever other url handling code your app requires here
 
    
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
    DDLogVerbose(@"Device Waking. Connecting in 5 sec");
    dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), q_background,  ^{
        [[MLXMPPManager sharedInstance] connectIfNecessary];
    });
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
    
    if(!self.cloudVC)
    {
        self.cloudVC = [storyboard instantiateControllerWithIdentifier:@"cloudStorage"];
    }
    
    if(!self.optOutVC)
    {
        self.optOutVC = [storyboard instantiateControllerWithIdentifier:@"optOutSettings"];
    }
    
}

-(IBAction)showPreferences:(id)sender
{
    [self linkVCs];
    if(!self.preferencesWindow) {
        NSArray *array = @[self.accountsVC, self.presenceVC, self.displayVC, self.cloudVC, self.optOutVC];
        self.preferencesWindow = [[MASPreferencesWindowController alloc] initWithViewControllers:array];
    }
    [self.preferencesWindow showWindow:self];
    
}



#pragma mark - Menu delegate

-(void)menuWillOpen:(NSMenu *)menu
{
    
    [[DataLayer sharedInstance] accountListWithCompletion:^(NSArray *result) {
        dispatch_async(dispatch_get_main_queue(), ^{
          
            if(self.encryptionKeys.submenu.itemArray.count>0) {
                NSMenuItem *template =[self.encryptionKeys.submenu.itemArray[0] copy];
                [self.encryptionKeys.submenu removeAllItems ];
                for(NSDictionary *account in result)
                {
                    
                    NSNumber *accountId =[account objectForKey:@"account_id"];
                    xmpp* xmppAccount= [[MLXMPPManager sharedInstance] getConnectedAccountForID:[NSString stringWithFormat:@"%@", accountId ]];
                    if(xmppAccount) {
                        NSMenuItem *item =[template copy];
                        
                        item.title=xmppAccount.fulluser;
                        item.tag=3000+accountId.integerValue;
                        
                        [self.encryptionKeys.submenu addItem:item];
                    }
                }
            }
            
            
            if(self.serverDetails.submenu.itemArray.count>0) {
                NSMenuItem *template =[self.serverDetails.submenu.itemArray[0] copy];
                [self.serverDetails.submenu removeAllItems ];
                for(NSDictionary *account in result)
                {
                    
                    NSNumber *accountId =[account objectForKey:@"account_id"];
                    xmpp* xmppAccount= [[MLXMPPManager sharedInstance] getConnectedAccountForID:[NSString stringWithFormat:@"%@", accountId ]];
                    if(xmppAccount) {
                        NSMenuItem *item =[template copy];
                        
                        item.title=xmppAccount.server;
                        item.tag=1000+accountId.integerValue;
                        
                        [self.serverDetails.submenu addItem:item];
                    }
                }
            }
                
                
                
                if(self.mamPrefs.submenu.itemArray.count>0) {
                    NSMenuItem *template =[self.mamPrefs.submenu.itemArray[0] copy];
                    [self.mamPrefs.submenu removeAllItems ];
                    for(NSDictionary *account in result)
                    {
                        
                        NSNumber *accountId =[account objectForKey:@"account_id"];
                        xmpp* xmppAccount= [[MLXMPPManager sharedInstance] getConnectedAccountForID:[NSString stringWithFormat:@"%@", accountId ]];
                        if(xmppAccount) {
                            NSMenuItem *item =[template copy];
                            
                            item.title=xmppAccount.server;
                            item.tag=2000+accountId.integerValue;
                            
                            [self.mamPrefs.submenu addItem:item];
                        }
                    }
            }
        });
        
    }];
    
    
}

@end
