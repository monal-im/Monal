//
//  MLMAMPrefTableViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 5/17/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLMAMPrefTableViewController.h"

@interface MLMAMPrefTableViewController ()
@property (nonatomic, strong) NSMutableArray *mamPref;
@property (nonatomic, strong) NSString *currentPref; 

@end

@implementation MLMAMPrefTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updatePrefs:) name:kMLMAMPref object:nil];

}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.mamPref =[[NSMutableArray alloc] init];
    self.navigationItem.title= self.xmppAccount.connectionProperties.identity.domain;
    [self.mamPref addObject:@{@"Title":NSLocalizedString(@"All messages are archived by default.",@""), @"value":@"always"}];
     [self.mamPref addObject:@{@"Title":NSLocalizedString(@"Messages never archived by default.",@""), @"value":@"never"}];
     [self.mamPref addObject:@{@"Title":NSLocalizedString(@"Archive only if the contact is in roster",@""), @"value":@"roster"}];
    
     [self.xmppAccount getMAMPrefs];
}


-(void) updatePrefs:(NSNotification *) notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *dic= (NSDictionary *) notification.object;
        self.currentPref =[dic objectForKey:@"mamPref"];
        [self.tableView reloadData];
    });
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.mamPref.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"serverCell" forIndexPath:indexPath];
    NSDictionary *dic = [self.mamPref objectAtIndex:indexPath.row];
    cell.textLabel.text= [dic objectForKey:@"Title"];
    cell.detailTextLabel.text= [dic objectForKey:@"Description"];
    
    if([[dic objectForKey:@"value"] isEqualToString:self.currentPref])
    {
        cell.accessoryType=UITableViewCellAccessoryCheckmark;
    } else  {
        cell.accessoryType=UITableViewCellAccessoryNone;
    }
    
    
    return cell;
}

-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    switch(indexPath.row)
    {
        case 0:{
            self.currentPref=@"always";
            break;
        }
        case 1:{
            self.currentPref=@"never";
            break;
        }
        case 2:{
            self.currentPref=@"roster";
            break;
        }
    }
    [self.xmppAccount setMAMPrefs:self.currentPref];
    
    [self.tableView reloadData];
}


-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return NSLocalizedString(@"Select Message Archive Management (MAM) Preferences ",@"");
}

@end
