//
//  ChatLogContactViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/12/13.
//
//

#import "ChatLogContactViewController.h"


@implementation ChatLogContactViewController

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

-(id) initWithAccountId:(NSString*) accountId andContact: (NSDictionary*) contact
{
    self = [super init];
    if(self){
        _accountId=accountId;
        _contact=contact;
    }
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.title=[_contact objectForKey:@"full_name"];

}

- (void)viewWillAppear:(BOOL)animated
{    
    _tableData =[[DataLayer sharedInstance] messageHistoryListDates:[_contact objectForKey:@"message_from"] forAccount:_accountId];
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
    UITableViewCell* cell =[tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if(cell==nil)
    {
        cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ChatAccountCell"];
        cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    }
    
    cell.textLabel.text=[[_tableData objectAtIndex:indexPath.row] objectForKey:@"the_date"];
    
    return cell;
}



@end
