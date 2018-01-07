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
    _tableData =[[DataLayer sharedInstance] messageHistoryBuddies:_accountId];
    [self.tableView reloadData];
    self.navigationItem.title=_accountName;
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
    
    cell.textLabel.text=[[_tableData objectAtIndex:indexPath.row] objectForKey:@"full_name"];
    if([cell.textLabel.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length<1) cell.textLabel.text=[[_tableData objectAtIndex:indexPath.row] objectForKey:@"message_from"];

    
    return cell;

}

#pragma mark tableview delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
  
    
    ChatLogContactViewController* vc = [[ChatLogContactViewController alloc] initWithAccountId:_accountId andContact: [_tableData objectAtIndex:indexPath.row] ];
    [self.navigationController pushViewController:vc animated:YES];
    
}

@end
