//
//  ChatLogContactViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/12/13.
//
//

#import "ChatLogContactViewController.h"
#import "chatViewController.h"

@interface ChatLogContactViewController()

@end

@implementation ChatLogContactViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
 
    self.navigationItem.title = self.contact.fullName;

    _tableData = [[DataLayer sharedInstance] messageHistoryListDates:self.contact.contactJid forAccount:self.contact.accountId];
    self.navigationItem.title = NSLocalizedString(@"Log Date",@"");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    [self.tableView reloadData];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [_tableData count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if(cell == nil)
    {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ChatAccountCell"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    
    cell.textLabel.text = [[_tableData objectAtIndex:indexPath.row] objectForKey:@"the_date"];
    
    return cell;
}

#pragma mark tableview delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString* theDay = [[_tableData objectAtIndex:indexPath.row] objectForKey:@"the_date"];
    [self performSegueWithIdentifier:@"showDayHistory" sender:theDay];
}

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"showDayHistory"])
    {
        self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
        chatViewController *chat = segue.destinationViewController;
        chat.day=(NSString *)sender;
        [chat setupWithContact:self.contact];
    }
}

@end
