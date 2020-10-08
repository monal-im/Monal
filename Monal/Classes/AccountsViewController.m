//
//  AccountsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "AccountsViewController.h"
#import "DataLayer.h"
#import "XMPPEdit.h"
#import "MBProgressHUD.h"
#import "xmpp.h"
#import "HelperTools.h"

@interface AccountsViewController ()

@property (nonatomic , strong) MBProgressHUD *hud;
@property (nonatomic , strong) NSDateFormatter *uptimeFormatter;

@property (nonatomic, strong) NSIndexPath  *selected;

@property (nonatomic, strong) NSArray* accountList;

@end

@implementation AccountsViewController


#pragma mark View life cycle
- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    self.navigationItem.title=NSLocalizedString(@"Accounts",@"");
   
    self.accountsTable=self.tableView;
    self.accountsTable.delegate=self;
    self.accountsTable.dataSource=self;

    self.accountsTable.backgroundView=nil;
 
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.accountsTable reloadData];
    });
    
    self.uptimeFormatter = [[NSDateFormatter alloc] init];
    self.uptimeFormatter.dateStyle = NSDateFormatterShortStyle;
    self.uptimeFormatter.timeStyle = NSDateFormatterShortStyle;
    self.uptimeFormatter.doesRelativeDateFormatting = YES;
    self.uptimeFormatter.locale = [NSLocale currentLocale];
    self.uptimeFormatter.timeZone = [NSTimeZone systemTimeZone];
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(refreshAccountList) name:kMonalAccountStatusChanged object:nil];
  
    self.splitViewController.preferredDisplayMode=UISplitViewControllerDisplayModeAllVisible;
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshAccountList];
    
    self.selected=nil;
}

-(void) dealloc
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self];
}

-(void) refreshAccountList
{
    NSArray* accountList = [[DataLayer sharedInstance] accountList];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.accountList = accountList;
        [self.accountsTable reloadData];
    });
}



#pragma mark button actions

-(IBAction)connect:(id)sender
{
    self.hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    self.hud.removeFromSuperViewOnHide=YES;
    self.hud.label.text = NSLocalizedString(@"Reconnecting", @"");
    self.hud.detailsLabel.text = NSLocalizedString(@"Will logout and reconnect any connected accounts.", @"");
    [[MLXMPPManager sharedInstance] logoutAll];
    [HelperTools startTimer:1.0 withHandler:^{
        [[MLXMPPManager sharedInstance] connectIfNecessary];
    }];
    [self.hud hideAnimated:YES afterDelay:3.0f];
    self.hud=nil;
}

#pragma mark memory management
- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark tableview delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    self.selected = indexPath;
    
    [self performSegueWithIdentifier:@"editXMPP" sender:self];
    
}


-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"editXMPP"]) {
        
        XMPPEdit* editor = (XMPPEdit *)segue.destinationViewController;
    
        editor.originIndex=self.selected;
        if(self.selected.section == 0)
        {
            //existing
            editor.accountno = [NSString stringWithFormat:@"%@",[[_accountList objectAtIndex:self.selected.row] objectForKey:@"account_id"]];
        }
        else if(self.selected.section == 1)
        {
            editor.accountno = @"-1";
        }
    }
}


#pragma mark tableview datasource
-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

-(UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    NSString* sectionTitle = [self tableView:tableView titleForHeaderInSection:section];
    return [HelperTools MLCustomViewHeaderWithTitle:sectionTitle];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case 0:
        {
            return NSLocalizedString(@"Accounts",@"");
            break;
        }
            
        case 1:
        {
            return NSLocalizedString(@"Add New Account",@"");
            break;
        }
            
        default:
        {
            return  nil;
        }
            break;
    }
}


- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case 0:
        {
            return [_accountList count];
            break;
        }
        case 1:
        {
            return 1;
            break;
        }
            
        default:
        {
            return 0;
        }
            break;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case 0:
        {
            UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"AccountCell"];
            if(cell == nil)
            {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AccountCell"];
            }
            else
            {
                cell.accessoryView = nil;
            }
            if([(NSString*)[[_accountList objectAtIndex:indexPath.row] objectForKey:@"domain"] length] > 0) {
                cell.textLabel.text = [NSString stringWithFormat:@"%@@%@", [[_accountList objectAtIndex:indexPath.row] objectForKey:@"username"],
                                     [[_accountList objectAtIndex:indexPath.row] objectForKey:@"domain"]];
            }
            else {
                cell.textLabel.text = [[_accountList objectAtIndex:indexPath.row] objectForKey:@"username"];
            }
            
            
            UIImageView* accessory = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
            cell.detailTextLabel.text=nil;
            
            if([[[_accountList objectAtIndex:indexPath.row] objectForKey:@"enabled"] boolValue] == YES) {
                   cell.imageView.image = [UIImage imageNamed:@"888-checkmark"];
                if([[MLXMPPManager sharedInstance] isAccountForIdConnected: [NSString stringWithFormat:@"%@", [[_accountList objectAtIndex:indexPath.row] objectForKey:@"account_id"]]]) {
                    accessory.image = [UIImage imageNamed:@"Connected"];
                    cell.accessoryView = accessory;
                    
                    NSDate* connectedTime = [[MLXMPPManager sharedInstance] connectedTimeFor: [NSString stringWithFormat:@"%@", [[_accountList objectAtIndex:indexPath.row] objectForKey:@"account_id"]]];
                    if(connectedTime) {
                        cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Connected since: %@", @""), [self.uptimeFormatter stringFromDate:connectedTime]];
                    }
                }
                else {
                    accessory.image = [UIImage imageNamed:NSLocalizedString(@"Disconnected", @"")];
                    cell.accessoryView = accessory;
                }
            }
            else {
                    cell.imageView.image = [UIImage imageNamed:@"disabled"];
            }
            return cell;
            break;
        }
        case 1:
        {
            UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"ProtocolCell"];
            if(cell == nil)
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ProtocolCell"];
            cell.textLabel.text = NSLocalizedString(@"XMPP", @"");
            cell.imageView.image = [UIImage imageNamed:@"XMPP"];
            cell.detailTextLabel.text = NSLocalizedString(@"Jabber, Prosody, ejabberd etc.   ", @"");
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

            return cell;
            break;
        }
        default:
        {
            return 0;
        }
            break;
    }
    
    return nil;
}

@end
