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
    [self.view setBackgroundColor:[UIColor colorWithPatternImage:[UIImage imageNamed:@"debut_dark"]]];
    _protocolList=[[DataLayer sharedInstance] protocolList];
    
}

-(void) viewWillAppear:(BOOL)animated
{
    _accountList=[[DataLayer sharedInstance] accountList];
    [self.accountsTable reloadData];
    [[UILabel appearanceWhenContainedIn:[UITableViewHeaderFooterView class], nil] setColor:[UIColor whiteColor]];
    [[UILabel appearanceWhenContainedIn:[UITableViewHeaderFooterView class], nil] setShadowColor:nil];
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

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case 0:
        {
            return @"Accounts";
            break;
        }
            
        case 1:
        {
            return @"Add New Account";
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
