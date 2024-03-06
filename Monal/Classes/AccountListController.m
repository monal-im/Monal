//
//  AccountListController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "AccountListController.h"
#import "DataLayer.h"
#import "MLXMPPManager.h"
#import "HelperTools.h"

@interface AccountListController ()
@property (nonatomic, strong) NSDateFormatter* uptimeFormatter;

@property (nonatomic, strong) NSIndexPath* selected; // User-selected account - needed for segue
@property (nonatomic, strong) UITableView* accountsTable;
@property (nonatomic, strong) NSArray<NSDictionary*>* accountList;

@end

@implementation AccountListController


#pragma mark View life cycle
- (void) setupAccountsView
{
	// Do any additional setup after loading the view.
    self.accountsTable.backgroundView = nil;
    self.accountsTable = self.tableView;
    self.accountsTable.delegate = self;
    self.accountsTable.dataSource = self;
 
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.accountsTable reloadData];
    });
    
    self.uptimeFormatter = [NSDateFormatter new];
    self.uptimeFormatter.dateStyle = NSDateFormatterShortStyle;
    self.uptimeFormatter.timeStyle = NSDateFormatterShortStyle;
    self.uptimeFormatter.doesRelativeDateFormatting = YES;
    self.uptimeFormatter.locale = [NSLocale currentLocale];
    self.uptimeFormatter.timeZone = [NSTimeZone systemTimeZone];

    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(refreshAccountList) name:kMonalAccountStatusChanged object:nil];
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(NSUInteger) getAccountNum
{
    return self.accountList.count;
}

-(NSNumber*) getAccountNoByIndex:(NSUInteger) index
{
    NSNumber* result = [[self.accountList objectAtIndex: index] objectForKey:@"account_id"];
    MLAssert(result != nil, @"getAccountNoByIndex, result should not be nil");
    return result;
}

-(NSString *) getAccountNameByIndex:(NSUInteger) accNo
{
    NSString *str = [NSString stringWithFormat:@"%@@%@", [[self.accountList objectAtIndex:accNo] objectForKey:@"username"],
                     [[self.accountList objectAtIndex:accNo] objectForKey:@"domain"]];
    return str;
}

-(void) refreshAccountList
{
    NSArray* accountList = [[DataLayer sharedInstance] accountList];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.accountList = accountList;
        [self.accountsTable reloadData];
    });
}

-(void) initContactCell:(MLSwitchCell*) cell forAccNo:(NSUInteger) accNo
{
    [cell initTapCell:@"\n\n"];
    cell = [cell initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AccountCell"];
    NSDictionary* account = [self.accountList objectAtIndex:accNo];
    MLAssert(account != nil, ([NSString stringWithFormat:@"Expected non nil account in row %lu", (unsigned long)accNo]));
    if([(NSString*)[account objectForKey:@"domain"] length] > 0) {
        cell.textLabel.text = [NSString stringWithFormat:@"%@@%@", [[self.accountList objectAtIndex:accNo] objectForKey:@"username"],
                                [[self.accountList objectAtIndex:accNo] objectForKey:@"domain"]];
    }
    else
    {
        cell.textLabel.text = [[self.accountList objectAtIndex:accNo] objectForKey:@"username"];
    }

    UIImageView* accessory = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
    cell.detailTextLabel.text = nil;

    if([[account objectForKey:@"enabled"] boolValue] == YES)
    {
        cell.imageView.image = [UIImage systemImageNamed:@"checkmark.circle"];
        if([[MLXMPPManager sharedInstance] isAccountForIdConnected:[[self.accountList objectAtIndex:accNo] objectForKey:@"account_id"]])
        {
            accessory.image = [UIImage imageNamed:@"Connected"];
            cell.accessoryView = accessory;
            
            NSDate* connectedTime = [[MLXMPPManager sharedInstance] connectedTimeFor:[[self.accountList objectAtIndex:accNo] objectForKey:@"account_id"]];
            if(connectedTime) {
                cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Connected since: %@", @""), [self.uptimeFormatter stringFromDate:connectedTime]];
            }
        }
        else
        {
            accessory.image = [UIImage imageNamed:@"Disconnected"];
            cell.accessoryView = accessory;
            cell.detailTextLabel.text = NSLocalizedString(@"Connecting...", @"");
        }
    }
    else
    {
        cell.imageView.image = [UIImage systemImageNamed:@"circle"];
        accessory.image = nil;
        cell.accessoryView = accessory;
        cell.detailTextLabel.text = NSLocalizedString(@"Account disabled", @"");
    }
}

@end
