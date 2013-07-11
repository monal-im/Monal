//
//  ContactsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "ContactsViewController.h"
#import "MLXMPPManager.h"
#import "MLContactCell.h"
#import "DataLayer.h"

@interface ContactsViewController ()

@end

@implementation ContactsViewController

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
    // Do any additional setup after loading the view from its nib.
    self.navigationItem.title=NSLocalizedString(@"Contacts",@"");
    self.view.backgroundColor=[UIColor lightGrayColor];
    self.view.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
   
    _contactsTable=[[UITableView alloc] init];
    _contactsTable.delegate=self;
    _contactsTable.dataSource=self;
    
    self.view=_contactsTable;
    
    // should any accounts connect?
    
    [[MLXMPPManager sharedInstance] connectIfNecessary];
    
}

-(void) viewWillAppear:(BOOL)animated
{
    
    //inefficient temp code
    _contacts=[[NSMutableArray alloc] initWithArray:[[DataLayer sharedInstance] onlineBuddiesSortedBy:@"Name"]];
    [_contactsTable reloadData];
    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark tableview datasource 
-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1; 
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [_contacts count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    MLContactCell* cell =[tableView dequeueReusableCellWithIdentifier:@"ContactCell"];
    if(!cell)
    {
        cell =[[MLContactCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ContactCell"];
    }
    
    NSDictionary* row = [_contacts objectAtIndex:indexPath.row];
    cell.textLabel.text=[row objectForKey:@"full_name"];
    if(![[row objectForKey:@"status"] isEqualToString:@"(null)"])
        cell.detailTextLabel.text=[row objectForKey:@"status"];
    
    if(([[row objectForKey:@"state"] isEqualToString:@"away"]) ||
       ([[row objectForKey:@"state"] isEqualToString:@"dnd"])||
        ([[row objectForKey:@"state"] isEqualToString:@"xa"])
       )
    {
         cell.status=kStatusAway;
    }
    else if([[row objectForKey:@"state"] isEqualToString:@"(null)"])
        cell.status=kStatusOnline;
    else if([[row objectForKey:@"state"] isEqualToString:@"offline"])
        cell.status=kStatusOffline;
    
    cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;

    cell.count=0; 
   
    return cell; 
}

#pragma mark tableview delegate


@end
