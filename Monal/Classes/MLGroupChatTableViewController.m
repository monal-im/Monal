//
//  MLGroupChatTableViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 3/25/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLGroupChatTableViewController.h"
#import "MLXMPPManager.h"
#import "DataLayer.h"
#import "xmpp.h"

@interface MLGroupChatTableViewController ()

@property (nonatomic, strong) NSMutableArray *favorites;
@property (nonatomic, strong) NSDictionary *toEdit; 


@end

@implementation MLGroupChatTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];

}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
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
                [self.tableView reloadData];
            });
            
        }];
    }
}

-(void) viewWillAppear:(BOOL)animated
{
    [self refresh];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @"Favorite Group Chats (MUC). Tap to join. ";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.favorites.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ListItem" forIndexPath:indexPath];
    
    NSDictionary *dic = self.favorites[indexPath.row];
    
    NSMutableString *cellText = [NSMutableString stringWithFormat:@"%@ on %@", [dic objectForKey:@"nick"], [dic objectForKey:@"room"]];
    
    NSNumber *autoJoin = [dic objectForKey:@"autojoin"];
    
    if(autoJoin.boolValue)
    {
        cell.detailTextLabel.text= @"(autojoin)";
    }
    else  {
        cell.detailTextLabel.text= @"";
    }
    
    cell.textLabel.text = cellText;
    cell.accessoryType=UITableViewCellAccessoryDetailButton;
    
    return cell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
       NSDictionary *dic = self.favorites[indexPath.row];
    
    NSNumber *account=[dic objectForKey:@"account_id"];
    [[MLXMPPManager sharedInstance] joinRoom:[dic objectForKey:@"room"] withNick:[dic objectForKey:@"nick"]  andPassword:@"" forAccounId:account.integerValue ];
    [[DataLayer sharedInstance] addContact:[dic objectForKey:@"room"] forAccount:[NSString stringWithFormat:@"%@", account] fullname:@"" nickname:[dic objectForKey:@"nick"] withCompletion:^(BOOL success) {
        if(!success)
        {
                [[DataLayer sharedInstance] updateOwnNickName:[dic objectForKey:@"nick"] forMuc:[dic objectForKey:@"room"] forAccount:[NSString stringWithFormat:@"%@", account]];
        }
    }];

}

-(void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
     NSDictionary *dic = self.favorites[indexPath.row];
    self.toEdit=dic;
    [self performSegueWithIdentifier:@"editGroup" sender:self];
}


#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
 
}


@end
