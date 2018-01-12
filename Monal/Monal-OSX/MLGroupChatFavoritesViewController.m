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
//    cell.name.backgroundColor =[NSColor clearColor];
//    cell.status.backgroundColor= [NSColor clearColor];
//
//    NSDictionary *dic = [self.serverCaps objectAtIndex:row];
//
//    cell.name.stringValue= [dic objectForKey:@"Title"];
//    cell.status.stringValue= [dic objectForKey:@"Description"];
//
    
    NSDictionary *dic = self.favorites[row];
    
    
    cell.textField.stringValue = [dic objectForKey:@"room"];
    return cell;
}


-(IBAction)join:(id)sender
{
    
}

-(IBAction)remove:(id)sender
{
    
}


@end
