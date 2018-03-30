//
//  SworIMAppDelegate.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import "MonalAppDelegate.h"


#import "CallViewController.h"

#import "MLNotificationManager.h"
#import "DataLayer.h"
#import "NXOAuth2AccountStore.h"

@import Crashlytics;
@import Fabric;
#import <DropboxSDK/DropboxSDK.h>

//xmpp
#import "MLXMPPManager.h"

@interface MonalAppDelegate ()

@property (nonatomic, strong)  UITabBarItem* activeTab;

@end

static const int ddLogLevel = LOG_LEVEL_VERBOSE;

@implementation MonalAppDelegate


-(void) setUISettings
{
    UIColor *monalGreen =[UIColor colorWithRed:128.0/255 green:203.0/255 blue:182.0/255 alpha:1.0f];
    UIColor *monaldarkGreen =[UIColor colorWithRed:20.0/255 green:138.0/255 blue:103.0/255 alpha:1.0f];
    
    [[UINavigationBar appearance] setBarTintColor:monalGreen];
    [[UINavigationBar appearance] setTintColor:[UIColor whiteColor]];
    [[UINavigationBar appearance] setTitleTextAttributes:@{
                                                           NSForegroundColorAttributeName: [UIColor darkGrayColor]
                                                           }];
    if (@available(iOS 11.0, *)) {
        [[UINavigationBar appearance] setPrefersLargeTitles:YES];
        [[UINavigationBar appearance] setLargeTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]}];
        
    }
    
    [[UITabBar appearance] setTintColor:monaldarkGreen];
    
    
}


#pragma mark - VOIP APNS notificaion

-(void) voipRegistration
{
    DDLogInfo(@"registering for voip APNS...");
    dispatch_queue_t mainQueue = dispatch_get_main_queue();
    // Create a push registry object
    PKPushRegistry * voipRegistry = [[PKPushRegistry alloc] initWithQueue: mainQueue];
    // Set the registry's delegate to self
    voipRegistry.delegate = self;
    // Set the push type to VoIP
    voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
    
}

// Handle updated APNS tokens
-(void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials: (PKPushCredentials *)credentials forType:(NSString *)type
{
    DDLogInfo(@"voip APNS token: %@", credentials.token);
    
    unsigned char *tokenBytes = (unsigned char *)[credentials.token bytes];
    NSMutableString *token = [[NSMutableString alloc] init];
    [MLXMPPManager sharedInstance].hasAPNSToken=YES;
    NSInteger counter=0;
    while(counter< credentials.token.length)
    {
        [token appendString:[NSString stringWithFormat:@"%02x", (unsigned char) tokenBytes[counter]]];
        counter++;
    }
    
    NSString *node = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    
    NSString *post = [NSString stringWithFormat:@"type=apns&node=%@&token=%@", [node stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]],
                      [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    NSData *postData = [post dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    NSString *postLength = [NSString stringWithFormat:@"%luld",[postData length]];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    //this is the hardcoded push api endpoint
    [request setURL:[NSURL URLWithString:@"https://push.monal.im:5281/push_appserver/v1/register"]];
    [request setHTTPMethod:@"POST"];
    [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:postData];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            
            NSHTTPURLResponse *httpresponse= (NSHTTPURLResponse *) response;
            
            if(!error && httpresponse.statusCode<400)
            {
                DDLogInfo(@"connection to push api successful");
                
                NSString *responseBody = [[NSString alloc] initWithData:data  encoding:NSUTF8StringEncoding];
                DDLogInfo(@"push api returned: %@", responseBody);
                NSArray *responseParts=[responseBody componentsSeparatedByString:@"\n"];
                if(responseParts.count>0){
                    if([responseParts[0] isEqualToString:@"OK"] && [responseParts count]==3)
                    {
                        DDLogInfo(@"push api: node='%@', secret='%@'", responseParts[1], responseParts[2]);
                        [[MLXMPPManager sharedInstance] setPushNode:responseParts[1] andSecret:responseParts[2]];
                    }
                    else {
                        DDLogError(@" push api returned invalid data: %@", [responseParts componentsJoinedByString: @" | "]);
                    }
                } else {
                    DDLogError(@"push api could  not be broken into parts");
                }
                
            } else
            {
                DDLogError(@" connection to push api NOT successful");
            }
            
        }] resume];
    });
    
}

-(void)pushRegistry:(PKPushRegistry *)registry didInvalidatePushTokenForType:(NSString *)type
{
    DDLogInfo(@"didInvalidatePushTokenForType called (and ignored, TODO: disable push on server?)");
}

// Handle incoming pushes
-(void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(NSString *)type
{
    DDLogInfo(@"incoming voip notfication: %@", [payload dictionaryPayload]);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        //reconenct and fetch messages
        
       __block UIBackgroundTaskIdentifier tempTask= [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^(void) {
           DDLogInfo(@"voip wake expiring");
           [[UIApplication sharedApplication] endBackgroundTask:tempTask];
            tempTask=UIBackgroundTaskInvalid;
        }];
        
        [[MLXMPPManager sharedInstance] connectIfNecessary];
         DDLogInfo(@"voip wake compelte");
        
//        [[UIApplication sharedApplication] endBackgroundTask:tempTask];
//        tempTask=UIBackgroundTaskInvalid;
    });
}

#pragma mark notification actions
-(void) showCallScreen:(NSNotification*) userInfo
{
//    dispatch_async(dispatch_get_main_queue(),
//                   ^{
//                       NSDictionary* contact=userInfo.object;
//                       CallViewController *callScreen= [[CallViewController alloc] initWithContact:contact];
//
//
//
//                       [self.tabBarController presentModalViewController:callNav animated:YES];
//                   });
}

-(void) updateUnread
{
    //make sure unread badge matches application badge
    
    [[DataLayer sharedInstance] countUnreadMessagesWithCompletion:^(NSNumber *result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            
            NSInteger unread =0;
            if(result)
            {
                unread= [result integerValue];
            }
            
            if(unread>0)
            {
                _activeTab.badgeValue=[NSString stringWithFormat:@"%ld",(long)unread];
                [UIApplication sharedApplication].applicationIconBadgeNumber =unread;
            }
            else
            {
                _activeTab.badgeValue=nil;
                [UIApplication sharedApplication].applicationIconBadgeNumber =0;
            }
        });
    }];
    
}

#pragma mark app life cycle


- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler;
{
    completionHandler(UNNotificationPresentationOptionAlert);
}


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    
#ifdef  DEBUG
    [DDLog addLogger:[DDASLLogger sharedInstance]];
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    self.fileLogger = [[DDFileLogger alloc] init];
    self.fileLogger.rollingFrequency = 60 * 60 * 24; // 24 hour rolling
    self.fileLogger.logFileManager.maximumNumberOfLogFiles = 5;
    self.fileLogger.maximumFileSize=1024 * 500;
    [DDLog addLogger:self.fileLogger];
#endif
    
    if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"10.0")){
        [UNUserNotificationCenter currentNotificationCenter].delegate=self;
    }
    
    //ios8 register for local notifications and badges
    if([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)])
    {
        NSSet *categories;
        
        UIMutableUserNotificationAction *replyAction = [[UIMutableUserNotificationAction alloc] init];
        replyAction.activationMode = UIUserNotificationActivationModeBackground;
        replyAction.title = @"Reply";
        replyAction.identifier = @"ReplyButton";
        replyAction.destructive = NO;
        replyAction.authenticationRequired = NO;
        replyAction.behavior = UIUserNotificationActionBehaviorTextInput;
        
        UIMutableUserNotificationCategory *actionCategory = [[UIMutableUserNotificationCategory alloc] init];
        actionCategory.identifier = @"Reply";
        [actionCategory setActions:@[replyAction] forContext:UIUserNotificationActionContextDefault];
        categories = [NSSet setWithObject:actionCategory];
        
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert|UIUserNotificationTypeSound|UIUserNotificationTypeBadge categories:categories];
        [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
    }
    
    //register for voip push using pushkit
    if([UIApplication sharedApplication].applicationState!=UIApplicationStateBackground) {
       // if we are launched in the background, it was from a push. dont do this again.
        [self voipRegistration];
 
    }
    else  {
        [MLXMPPManager sharedInstance].pushNode = [[NSUserDefaults standardUserDefaults] objectForKey:@"pushNode"];
        [MLXMPPManager sharedInstance].pushSecret=[[NSUserDefaults standardUserDefaults] objectForKey:@"pushSecret"];
        [MLXMPPManager sharedInstance].hasAPNSToken=YES;
           NSLog(@"push node %@", [MLXMPPManager sharedInstance].pushNode); 
    }
    
    [self setUISettings];

    
    [MLNotificationManager sharedInstance].window=self.window;
    
    // should any accounts connect?
    [[MLXMPPManager sharedInstance] connectIfNecessary];
    
    [Fabric with:@[[Crashlytics class]]];
    
    //update logs if needed
    if(! [[NSUserDefaults standardUserDefaults] boolForKey:@"Logging"])
    {
        [[DataLayer sharedInstance] messageHistoryCleanAll];
    }
    
    //Dropbox
    DBSession *dbSession = [[DBSession alloc]
                            initWithAppKey:@"a134q2ecj1hqa59"
                            appSecret:@"vqsf5vt6guedlrs"
                            root:kDBRootAppFolder];
    [DBSession setSharedSession:dbSession];
    
    DDLogInfo(@"App started");
    return YES;
}

-(void) applicationDidBecomeActive:(UIApplication *)application
{
    //  [UIApplication sharedApplication].applicationIconBadgeNumber=0;
}

#pragma mark - handling urls

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options
{
    if([url.scheme isEqualToString:@"com.googleusercontent.apps.472865344000-invcngpma1psmiek5imc1gb8u7mef8l9"])
    {
        [[NXOAuth2AccountStore sharedStore] handleRedirectURL:url];
        return YES;
    }
    else  {
    
    if ([[DBSession sharedSession] handleOpenURL:url]) {
        if ([[DBSession sharedSession] isLinked]) {
            DDLogVerbose(@"App linked successfully!");
            // At this point you can start making API calls
        }
        return YES;
    }
    }
    // Add whatever other url handling code your app requires here
    return NO;
}


#pragma mark  - user notifications
-(void) application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings
{
    DDLogVerbose(@"did register for local notifications");
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
    DDLogVerbose(@"entering app with %@", notification);
    
    //iphone
    //make sure tab 0
    if([notification.userInfo objectForKey:@"from"]) {
        [self.tabBarController setSelectedIndex:0];
        [[MLXMPPManager sharedInstance].contactVC presentChatWithName:[notification.userInfo objectForKey:@"from"] account:[notification.userInfo objectForKey:@"accountNo"] ];
    }
}


-(void) application:(UIApplication *)application handleActionWithIdentifier:(nullable NSString *)identifier forLocalNotification:(nonnull UILocalNotification *)notification withResponseInfo:(nonnull NSDictionary *)responseInfo completionHandler:(nonnull void (^)())completionHandler
{
    if ([notification.category isEqualToString:@"Reply"]) {
        if ([identifier isEqualToString:@"ReplyButton"]) {
            NSString *message = responseInfo[UIUserNotificationActionResponseTypedTextKey];
            if (message.length > 0) {
                
                if([notification.userInfo objectForKey:@"from"]) {
                    
                    NSString *replyingAccount = [notification.userInfo objectForKey:@"to"];
                    
                    NSString *messageID =[[NSUUID UUID] UUIDString];
                    
                    [[DataLayer sharedInstance] addMessageHistoryFrom:replyingAccount to:[notification.userInfo objectForKey:@"from"] forAccount:[notification.userInfo objectForKey:@"accountNo"] withMessage:message actuallyFrom:replyingAccount withId:messageID withCompletion:^(BOOL success, NSString *messageType) {
                        
                    }];
                    
                    [[MLXMPPManager sharedInstance] sendMessage:message toContact:[notification.userInfo objectForKey:@"from"] fromAccount:[notification.userInfo objectForKey:@"accountNo"] isMUC:NO messageId:messageID withCompletionHandler:^(BOOL success, NSString *messageId) {
                        
                    }];
                    
                    [[DataLayer sharedInstance] markAsReadBuddy:[notification.userInfo objectForKey:@"from"] forAccount:[notification.userInfo objectForKey:@"accountNo"]];
                    [self updateUnread];
                    
                }
                
                
            }
        }
    }
    if(completionHandler) completionHandler();
}


#pragma mark - memory
-(void) applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    [[MLImageManager sharedInstance] purgeCache];
}

#pragma mark - backgrounding
- (void)applicationWillEnterForeground:(UIApplication *)application
{
    DDLogVerbose(@"Entering FG");
 
    [[MLXMPPManager sharedInstance] resetForeground];
    [[MLXMPPManager sharedInstance] setClientsActive];
}

-(void) applicationDidEnterBackground:(UIApplication *)application
{
    UIApplicationState state = [application applicationState];
    if (state == UIApplicationStateInactive) {
        DDLogVerbose(@"Screen lock");
    } else if (state == UIApplicationStateBackground) {
        DDLogVerbose(@"Entering BG");
    }
    
    [self updateUnread];
//    [[MLXMPPManager sharedInstance] setClientsInactive];
//    
//    __block UIBackgroundTaskIdentifier tempTask= [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^(void) {
//        DDLogInfo(@"background wake expiring");
//        [[UIApplication sharedApplication] endBackgroundTask:tempTask];
//        tempTask=UIBackgroundTaskInvalid;
//    }];
}

-(void)applicationWillTerminate:(UIApplication *)application
{
    
    [self updateUnread];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - splitview controller delegate
- (BOOL)splitViewController:(UISplitViewController *)svc shouldHideViewController:(UIViewController *)vc inOrientation:(UIInterfaceOrientation)orientation
{
    return NO;
}

@end

