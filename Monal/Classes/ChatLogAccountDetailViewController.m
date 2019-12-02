//
//  ChatLogAccountDetailViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/12/13.
//
//

#import "ChatLogAccountDetailViewController.h"


@implementation ChatLogAccountDetailViewController


- (void)viewDidLoad
{
    [super viewDidLoad];
	
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _tableData =[[DataLayer sharedInstance] messageHistoryContacts:self.accountId];
    
    __block NSInteger pos;
    
    [self->_tableData enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        MLContact *contact = (MLContact *) obj;
        if([contact.contactJid isEqualToString:self.accountName]) {
            *stop=YES;
            pos=idx;
        }
    }];
    
    [_tableData removeObjectAtIndex:pos];
    
    [self.tableView reloadData];
    self.navigationItem.title=self.accountName;
    self.splitViewController.preferredDisplayMode=UISplitViewControllerDisplayModeAllVisible;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark tableview datasource delegate
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [_tableData count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell* cell =[tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if(cell==nil)
    {
        cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ChatAccountCell"];
        cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    }
    
    MLContact *row =[_tableData objectAtIndex:indexPath.row];
    
    cell.textLabel.text=row.contactDisplayName;

    return cell;

}

#pragma mark tableview delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
  
    [self performSegueWithIdentifier:@"showContactLogs" sender: [_tableData objectAtIndex:indexPath.row]];
}

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"showContactLogs"])
    {
        ChatLogContactViewController* vc = segue.destinationViewController;
        MLContact *contact = (MLContact *) sender;
        
        vc.contact= contact;
 
    }
}


@end
