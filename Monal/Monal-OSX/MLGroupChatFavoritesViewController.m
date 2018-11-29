//
//  MLGroupChatFavoritesViewController.m
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 1/11/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLGroupChatFavoritesViewController.h"
#import "MLXMPPManager.h"
#import "DataLayer.h"

@interface MLGroupChatFavoritesViewController ()

@property (nonatomic, strong) NSMutableArray *favorites;

@end

@implementation MLGroupChatFavoritesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
}

-(void) viewWillAppear
{
    [super viewWillAppear];
    [self refresh];
}

-(void) refresh
{
     self.favorites = [[NSMutableArray alloc] init];
    for(NSDictionary *row in [MLXMPPManager sharedInstance].connectedXMPP)
    {
        xmpp *account = [row objectForKey:kXmppAccount];
        [[DataLayer sharedInstance] mucFavoritesForAccount:account.accountNo withCompletion:^(NSMutableArray *results) {
            [self.favorites addObjectsFromArray:results];
            dispatch_async(dispatch_get_main_queue(),^(){
                [self.favoritesTable reloadData];
            });
            
        }];
    }
}

#pragma mark - table view datasource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return self.favorites.count;
}


#pragma mark - table view delegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn  row:(NSInteger)row
{
    
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"favoriteCell" owner:self];
    
    
    NSDictionary *dic = self.favorites[row];
    
    NSMutableString *cellText = [NSMutableString stringWithFormat:@"%@ on %@", [dic objectForKey:@"nick"], [dic objectForKey:@"room"]];
    
    NSNumber *autoJoin = [dic objectForKey:@"autojoin"];
    
    if(autoJoin.boolValue)
    {
        [cellText appendString:@" (autojoin)"];
    }
    
    cell.textField.stringValue = cellText;
    return cell;
}


-(IBAction)join:(id)sender
{
    NSIndexSet *selected = self.favoritesTable.selectedRowIndexes;
    if(selected.count>0) {
        NSUInteger row  =selected.firstIndex;
        
        NSDictionary *dic = self.favorites[row];
        NSNumber *account=[dic objectForKey:@"account_id"];
        [[MLXMPPManager sharedInstance] joinRoom:[dic objectForKey:@"room"] withNick:[dic objectForKey:@"nick"]  andPassword:@"" forAccounId:account.integerValue ];
   
        
        [[DataLayer sharedInstance] addContact:[dic objectForKey:@"room"] forAccount:[NSString stringWithFormat:@"%@", account] fullname:@"" nickname:[dic objectForKey:@"nick"] withCompletion:^(BOOL success) {
            if(!success)
            {
                [[DataLayer sharedInstance] updateOwnNickName:[dic objectForKey:@"nick"] forMuc:[dic objectForKey:@"room"] forAccount:[NSString stringWithFormat:@"%@", account]];
            }
        }];
        
    }
}

-(IBAction)doubleClick:(id)sender
{
    [self join:self];
}

-(IBAction)remove:(id)sender
{
    NSIndexSet *selected = self.favoritesTable.selectedRowIndexes;
    if(selected.count>0) {
        NSUInteger row  =selected.firstIndex;
        NSDictionary *dic = self.favorites[row];
        NSNumber *account=[dic objectForKey:@"account_id"];
        
        [[DataLayer sharedInstance] deleteMucFavorite:[dic objectForKey:@"mucid"] forAccountId:account.integerValue withCompletion:^(BOOL result) {
            dispatch_async(dispatch_get_main_queue(), ^{
                 [self refresh];
            });
        }];
        
  
    }
}


@end
