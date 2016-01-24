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
#import "tools.h"
#import "MBProgressHUD.h"


@interface AccountsViewController ()
@property (nonatomic , strong) MBProgressHUD *hud;
@property (nonatomic , strong) NSDateFormatter *uptimeFormatter;

@end

@implementation AccountsViewController


#pragma mark View life cycle
- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    self.navigationItem.title=NSLocalizedString(@"Accounts",@"");
    self.view.backgroundColor=[UIColor lightGrayColor];
    self.view.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    
    _accountsTable=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _accountsTable.delegate=self;
    _accountsTable.dataSource=self;
    
    self.view=_accountsTable;
    
    _accountsTable.backgroundView=nil;
    if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))
    {
      
    }
    else
    {
        [self.view setBackgroundColor:[UIColor colorWithPatternImage:[UIImage imageNamed:@"debut_dark"]]];
    }
    _protocolList=[[DataLayer sharedInstance] protocolList];
    
    UIBarButtonItem* rightButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Reconnect All",@"") style:UIBarButtonItemStyleBordered target:self action:@selector(connectIfNecessary)];
    self.navigationItem.rightBarButtonItem=rightButton;
    
    UIBarButtonItem* leftButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Log out All",@"") style:UIBarButtonItemStyleBordered target:self action:@selector(logoutAll)];
    self.navigationItem.leftBarButtonItem=leftButton;
    
    self.uptimeFormatter =[[NSDateFormatter alloc] init];
    self.uptimeFormatter.dateStyle =NSDateFormatterShortStyle;
    self.uptimeFormatter.timeStyle =NSDateFormatterShortStyle;
    self.uptimeFormatter.doesRelativeDateFormatting=YES;
    self.uptimeFormatter.locale=[NSLocale currentLocale];
    self.uptimeFormatter.timeZone=[NSTimeZone systemTimeZone];
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(refreshAccountList) name:kMonalAccountStatusChanged object:nil];
    
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    _accountList=[[DataLayer sharedInstance] accountList];
    [self.accountsTable reloadData];

}

-(void) dealloc
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self];
}

-(void) refreshAccountList
{
    dispatch_async(dispatch_get_main_queue() , ^{
        _accountList=[[DataLayer sharedInstance] accountList];
        [self.accountsTable reloadData];
    });
}

#pragma mark button actions

-(void) connectIfNecessary
{
    
    self.hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    self.hud.removeFromSuperViewOnHide=YES;
    self.hud.labelText =@"Reconnecting";
    self.hud.detailsLabelText =@"Will connect any logged out accounts.";
    [[MLXMPPManager sharedInstance] connectIfNecessary];
    [self.hud hide:YES afterDelay:3.0f];
    self.hud=nil;
}

-(void) logoutAll
{
    self.hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    self.hud.removeFromSuperViewOnHide=YES;
    self.hud.labelText =@"Logging out all accounts";
    self.hud.detailsLabelText =@"Tap Reconnect to log everything back in.";
    [[MLXMPPManager sharedInstance] logoutAll];
    [self.hud hide:YES afterDelay:3.0f];
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
    XMPPEdit* editor =[[XMPPEdit alloc] init];
    editor.originIndex=indexPath; 
    if(indexPath.section==0)
    {
        //existing
        editor.accountno=[NSString stringWithFormat:@"%@",[[_accountList objectAtIndex:indexPath.row] objectForKey:@"account_id"]];
    }
    else if(indexPath.section==1)
    {
        editor.accountno=@"-1";
    }
    
    [self.navigationController pushViewController:editor animated:YES];
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark tableview datasource
-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

-(UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
  
    UIView *tempView=[[UIView alloc]initWithFrame:CGRectMake(0,200,300,244)];
    tempView.backgroundColor=[UIColor clearColor];
    
    UILabel *tempLabel=[[UILabel alloc]initWithFrame:CGRectMake(15,0,300,44)];
    tempLabel.backgroundColor=[UIColor clearColor];
    tempLabel.shadowColor = [UIColor blackColor];
    tempLabel.shadowOffset = CGSizeMake(0,2);
    tempLabel.textColor = [UIColor whiteColor]; //here you can change the text color of header.
    tempLabel.font = [UIFont boldSystemFontOfSize:17.0f];
    tempLabel.text=[self tableView:tableView titleForHeaderInSection:section ];
    
    [tempView addSubview:tempLabel];
    
    if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))
    {
        tempLabel.textColor=[UIColor darkGrayColor];
        tempLabel.text=  tempLabel.text.uppercaseString;
        tempLabel.shadowColor =[UIColor clearColor];
        tempLabel.font=[UIFont systemFontOfSize:[UIFont systemFontSize]];
        
    }
    
    return tempView;
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
//    switch (section) {
//        case 0:
//        {
//            return @"Only one can be enabled at a time.";
//            break;
//        }
//    }
    
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
            return [_protocolList count];
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
            UITableViewCell* cell =[tableView dequeueReusableCellWithIdentifier:@"AccountCell"];
            if(cell==nil)
            {
                cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AccountCell"];
            }
            else
            {
                cell.accessoryView=nil; 
            }
            if([(NSString*)[[_accountList objectAtIndex:indexPath.row] objectForKey:@"domain"] length]>0) {
                cell.textLabel.text=[NSString stringWithFormat:@"%@@%@", [[_accountList objectAtIndex:indexPath.row] objectForKey:@"username"],
                                     [[_accountList objectAtIndex:indexPath.row] objectForKey:@"domain"]];
            }
            else {
                cell.textLabel.text=[[_accountList objectAtIndex:indexPath.row] objectForKey:@"username"];
            }
            
            
            UIImageView *accessory =[[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
            cell.detailTextLabel.text=nil;
            
            if([[[_accountList objectAtIndex:indexPath.row] objectForKey:@"enabled"] boolValue] ==YES) {
                   cell.imageView.image=[UIImage imageNamed:@"888-checkmark"];
                if([[MLXMPPManager sharedInstance] isAccountForIdConnected: [NSString stringWithFormat:@"%@",[[_accountList objectAtIndex:indexPath.row] objectForKey:@"account_id"]]]) {
                    accessory.image=[UIImage imageNamed:@"Connected"];
                    cell.accessoryView =accessory;
                    
                    NSDate * connectedTime = [[MLXMPPManager sharedInstance] connectedTimeFor: [NSString stringWithFormat:@"%@",[[_accountList objectAtIndex:indexPath.row] objectForKey:@"account_id"]]];
                    if(connectedTime) {
                        cell.detailTextLabel.text=[NSString stringWithFormat:@"Connected since: %@",[self.uptimeFormatter stringFromDate:connectedTime]];
                    }
                    
                }
                else {
                    accessory.image =[UIImage imageNamed:@"Disconnected"];
                    cell.accessoryView =accessory;
                }
       
            }
            else {
                    cell.imageView.image=[UIImage imageNamed:@"disabled"];
            }
         
            return cell;
            break;
        }
        case 1:
        {
            UITableViewCell* cell =[tableView dequeueReusableCellWithIdentifier:@"ProtocolCell"];
            if(cell==nil)
            {
                cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ProtocolCell"];
            }
            NSString* protocol =[[_protocolList objectAtIndex:indexPath.row] objectForKey:@"protocol_name"];
            cell.textLabel.text=protocol;
            cell.imageView.image=[UIImage imageNamed:protocol];
            
            cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
            
            if([protocol isEqualToString:@"GTalk"])
            {
                cell.detailTextLabel.text=@"Google Talk, Google apps etc. ";
            }
            
            if([protocol isEqualToString:@"XMPP"])
            {
                 cell.detailTextLabel.text=@"Jabber,Openfire,Prosody etc.   ";
            }
            
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
