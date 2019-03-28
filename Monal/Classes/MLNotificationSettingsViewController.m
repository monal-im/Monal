//
//  MLNotificationSettingsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/31/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLNotificationSettingsViewController.h"
#import "MLSwitchCell.h"
#import "MLXMPPManager.h"
@import UserNotificationsUI;

NS_ENUM(NSInteger, kNotificationSettingSection)
{
    kNotificationSettingSectionApplePush=0,
    kNotificationSettingSectionUser,
    kNotificationSettingSectionMonalPush,
    kNotificationSettingSectionAccounts,
    kNotificationSettingSectionAdvanced,
    kNotificationSettingSectionCount
};

static const int ddLogLevel = LOG_LEVEL_VERBOSE;

@interface MLNotificationSettingsViewController ()
@property (nonatomic, strong) NSArray *sectionsHeaders;
@property (nonatomic, strong) NSArray *sectionsFooters;
@property (nonatomic, strong) NSArray *apple;
@property (nonatomic, strong) NSArray *user;
@property (nonatomic, strong) NSArray *monal;


@property (nonatomic, assign) BOOL canShowNotifications;

@end

@implementation MLNotificationSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.sectionsFooters =@[@"Apple push service should always be on. If it is off, your device can not talk to Apple's server.",
                     @"If Monal can't show notifications, you will not see alerts when a message arrives. This happens if you tapped 'Decline' when Monal first asked permission.  Fix it by going to iOS Settings -> Monal -> Notifications and select 'Allow Notifications'. ",
                     @"If Monal push is off, your device could not talk to push.monal.im. This should also never be off. It requires Apple push service to work first. ",
                     @"",
                            @"Rebuilding is useful if you are not expereicing problems. This will require an app restart to work."];
    
    self.sectionsHeaders =@[@"",
                            @"",
                            @"",
                            @"Accounts",
                            @"Advanced"];
    
    self.apple=@[@"Apple Push Service"];
    self.user=@[@"Can Show Notifications"];
    self.monal=@[@"Monal Push Server"];
    
    self.splitViewController.preferredDisplayMode=UISplitViewControllerDisplayModeAllVisible;
}

-(void) viewWillAppear:(BOOL)animated
{
    self.navigationItem.title = NSLocalizedString(@"Notification Settings",@"");

    //TODO when ios 9 is dropped switch this to new API
    // [UNUserNotificationCenter getNotificationSettingsWithCompletionHandler:]
    UIUserNotificationSettings *notificationSettings= [[UIApplication sharedApplication] currentUserNotificationSettings];
    
    if (notificationSettings.types == UIUserNotificationTypeNone) {
        self.canShowNotifications=NO;
    }
    else if (notificationSettings.types  & UIUserNotificationTypeAlert){
      self.canShowNotifications=YES;
    }
    
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return kNotificationSettingSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger toreturn=0;
    switch(section)
    {
        case kNotificationSettingSectionUser: {
            toreturn=self.user.count;
            break;
        }
        case kNotificationSettingSectionApplePush: {
            toreturn=self.apple.count;
            break;
        }
        case kNotificationSettingSectionMonalPush: {
            toreturn= self.monal.count;
            break;
        }
            
        case kNotificationSettingSectionAccounts: {
            toreturn= [MLXMPPManager sharedInstance].connectedXMPP.count;
            break;
        }
        case kNotificationSettingSectionAdvanced: {
            toreturn=1;
            break;
        }
            
    }
    
    return toreturn;
}

-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString *toreturn= self.sectionsHeaders[section];
    return toreturn;
}

-(NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    NSString *toreturn= self.sectionsFooters[section];
    return toreturn;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    UITableViewCell *toreturn=[tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
    switch(indexPath.section)
    {
        case kNotificationSettingSectionUser: {
            
            UITableViewCell *cell= [tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
            cell.imageView.hidden=NO;
            cell.textLabel.text = self.user[0];
            if(self.canShowNotifications) {
                cell.imageView.image=[UIImage imageNamed:@"888-checkmark"];
            }
            else  {
               cell.imageView.image=[UIImage imageNamed:@"disabled"];
            }
            toreturn=cell;
            break;
        }
        case kNotificationSettingSectionApplePush: {
            UITableViewCell *cell= [tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
           
            cell.textLabel.text = self.apple[0];
            
            if([MLXMPPManager sharedInstance].hasAPNSToken) {
                 cell.imageView.image=[UIImage imageNamed:@"888-checkmark"];
            }
            else  {
                cell.imageView.image=[UIImage imageNamed:@"disabled"];
            }
            cell.imageView.hidden=NO;
            toreturn=cell;
            break;
        }
        case kNotificationSettingSectionMonalPush: {
            UITableViewCell *cell= [tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
            if([MLXMPPManager sharedInstance].pushNode) {
                cell.imageView.image=[UIImage imageNamed:@"888-checkmark"];
            }
            else  {
               cell.imageView.image=[UIImage imageNamed:@"disabled"];
            }
            cell.imageView.hidden=NO;
            cell.textLabel.text = self.monal[0];
            toreturn=cell;
            break;
        }
            
        case kNotificationSettingSectionAccounts: {
            UITableViewCell *cell= [tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
            cell.imageView.hidden=NO;
            NSDictionary  *row = [MLXMPPManager sharedInstance].connectedXMPP[indexPath.row];
            xmpp *xmppAccount = [row objectForKey:@"xmppAccount"];
            cell.textLabel.text =xmppAccount.fulluser;
            
            if(xmppAccount.pushEnabled) {
                cell.imageView.image=[UIImage imageNamed:@"888-checkmark"];
            }
            else  {
                cell.imageView.image=[UIImage imageNamed:@"disabled"];
            }
            
            toreturn=cell;
            break;
        }
            
        case kNotificationSettingSectionAdvanced: {
            UITableViewCell *cell= [tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
            cell.imageView.hidden=YES;
            cell.textLabel.text =@"Rebuild Tokens";
            toreturn=cell;
            break;
        }
            
    }
    
    return toreturn;
    
}


-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    switch(indexPath.section)
    {
        case kNotificationSettingSectionAdvanced: {
            
            NSString *node = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
            
            NSString *post = [NSString stringWithFormat:@"type=apns&node=%@", [node stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
            NSData *postData = [post dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
            NSString *postLength = [NSString stringWithFormat:@"%luld",[postData length]];
            
            NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
            //this is the hardcoded push api endpoint
            [request setURL:[NSURL URLWithString:@"https://push.monal.im:5281/push_appserver/v1/unregister"]];
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
                            if([responseParts[0] isEqualToString:@"OK"] )
                            {
                                DDLogInfo(@"push api: unregistered");
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
            
            break;
        }
    }
}


@end
