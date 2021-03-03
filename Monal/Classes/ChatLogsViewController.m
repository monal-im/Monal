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
    self.navigationItem.title = NSLocalizedString(@"Accounts With Logs",@"");
    _chatLogTable = self.tableView;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeAllVisible;
    NSArray* accountList = [[DataLayer sharedInstance] accountList];
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_tableData = accountList;
        [self->_chatLogTable reloadData];
    });
}

#pragma mark tableview datasource delegate
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [_tableData count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if(cell == nil)
    {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Cell"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    
    cell.textLabel.text=[NSString stringWithFormat:@"%@@%@",
                         [[_tableData objectAtIndex:indexPath.row] objectForKey:@"username"],
                         [[_tableData objectAtIndex:indexPath.row] objectForKey:@"domain"]];
     
    return cell;
}

#pragma mark tableview delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
       [self performSegueWithIdentifier:@"showAccountLog" sender:[_tableData objectAtIndex:indexPath.row]];
}

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"showAccountLog"])
    {
        ChatLogAccountDetailViewController *chat = segue.destinationViewController;
        NSDictionary *dic = (NSDictionary *) sender;
        
        NSString* accountName = [NSString stringWithFormat:@"%@@%@", [dic objectForKey:@"username"],
                                [dic objectForKey:@"domain"]];
        NSString* accountId = [NSString stringWithFormat:@"%@", [dic objectForKey:@"account_id"]];
        
        chat.accountId = accountId;
        chat.accountName = accountName;
    }
}
@end
