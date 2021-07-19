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
    
    self.uptimeFormatter = [[NSDateFormatter alloc] init];
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
    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self];
}

-(NSUInteger) getAccountNum
{
    return self.accountList.count;
}

-(NSString*) getAccountNoByIndex:(NSUInteger) index
{
    NSString* result = [NSString stringWithFormat:@"%@", [[self.accountList objectAtIndex: index] objectForKey:@"account_id"]];
    assert(result != nil);
    return result;
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
    NSAssert(account != nil, @"Expected non nil account in row %lu", (unsigned long)accNo);
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
        cell.imageView.image = [UIImage imageNamed:@"888-checkmark"];
        if([[MLXMPPManager sharedInstance] isAccountForIdConnected: [NSString stringWithFormat:@"%@", [[self.accountList objectAtIndex:accNo] objectForKey:@"account_id"]]])
        {
            accessory.image = [UIImage imageNamed:@"Connected"];
            cell.accessoryView = accessory;
            
            NSDate* connectedTime = [[MLXMPPManager sharedInstance] connectedTimeFor: [NSString stringWithFormat:@"%@", [[self.accountList objectAtIndex:accNo] objectForKey:@"account_id"]]];
            if(connectedTime) {
                cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Connected since: %@", @""), [self.uptimeFormatter stringFromDate:connectedTime]];
            }
        }
        else
        {
            accessory.image = [UIImage imageNamed:NSLocalizedString(@"Disconnected", @"")];
            cell.accessoryView = accessory;
            NSLocalizedString(@"Could not connect", @"")
        }
    }
    else
    {
        cell.imageView.image = [UIImage imageNamed:@"disabled"];
        accessory.image = nil;
        cell.accessoryView = accessory;
        cell.detailTextLabel.text = NSLocalizedString(@"Account disabled", @"");
    }
}

@end
