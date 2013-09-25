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


@interface AccountsViewController ()

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
}

-(void) viewWillAppear:(BOOL)animated
{
    _accountList=[[DataLayer sharedInstance] accountList];
    [self.accountsTable reloadData];
//    if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"6.0"))
//    {
//    [[UILabel appearanceWhenContainedIn:[UITableViewHeaderFooterView class], nil] setColor:[UIColor whiteColor]];
//    [[UILabel appearanceWhenContainedIn:[UITableViewHeaderFooterView class], nil] setShadowColor:nil];
//    }
}


#pragma mark button actions

-(void) connectIfNecessary
{
    [[MLXMPPManager sharedInstance] connectIfNecessary];
}

-(void) logoutAll
{
    [[MLXMPPManager sharedInstance] logoutAll];
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
            cell.textLabel.text=[NSString stringWithFormat:@"%@@%@", [[_accountList objectAtIndex:indexPath.row] objectForKey:@"username"],
                                 [[_accountList objectAtIndex:indexPath.row] objectForKey:@"domain"]];
            if([[[_accountList objectAtIndex:indexPath.row] objectForKey:@"enabled"] boolValue] ==YES)
                   cell.imageView.image=[UIImage imageNamed:@"enabled"];
                else
                    cell.imageView.image=[UIImage imageNamed:@"disabled"];
            
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
