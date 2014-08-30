//
//  ChatLogsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "ChatLogsViewController.h"
#import "DataLayer.h"
#import "ChatLogAccountDetailViewController.h"

@interface ChatLogsViewController ()

@end

@implementation ChatLogsViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    self.navigationItem.title=NSLocalizedString(@"Accounts With Logs",@"");
    self.view.backgroundColor=[UIColor lightGrayColor];
    self.view.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    
    _chatLogTable=[[UITableView alloc] init];
    _chatLogTable.delegate=self;
    _chatLogTable.dataSource=self;
    
    self.view=_chatLogTable;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    _tableData = [[DataLayer sharedInstance] accountList];
    [_chatLogTable reloadData];
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
        cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
        cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    }
    
    cell.textLabel.text=[NSString stringWithFormat:@"%@@%@", [[_tableData objectAtIndex:indexPath.row] objectForKey:@"username"],
                         [[_tableData objectAtIndex:indexPath.row] objectForKey:@"domain"]];
    

 
        return cell;

}

#pragma mark tableview delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    NSString* accountName= [NSString stringWithFormat:@"%@@%@", [[_tableData objectAtIndex:indexPath.row] objectForKey:@"username"],
                            [[_tableData objectAtIndex:indexPath.row] objectForKey:@"domain"]];;
    NSString* accountId= [NSString stringWithFormat:@"%@", [[_tableData objectAtIndex:indexPath.row] objectForKey:@"account_id"]];
    
    ChatLogAccountDetailViewController* vc = [[ChatLogAccountDetailViewController alloc] initWithAccountId:accountId andName:accountName];
    [self.navigationController pushViewController:vc animated:YES];
    
}


@end
