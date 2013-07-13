//
//  ContactsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "ContactsViewController.h"
#import "MLContactCell.h"
#import "DataLayer.h"


#define kinfoSetion 0
#define konlineSection 1
#define koflineSection 2 

@interface ContactsViewController ()

@end

@implementation ContactsViewController


#pragma mark view life cycle
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
    
    //inefficient temp code
    _contacts=[[NSMutableArray alloc] initWithArray:[[DataLayer sharedInstance] onlineBuddiesSortedBy:@"Name"]];
    [_contactsTable reloadData];
    
}

-(void) viewWillAppear:(BOOL)animated
{
    

    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark updating user display
-(void) addUser:(NSDictionary*) user
{
    
    //check if already there
    int pos=-1;
    int counter=0; 
    for(NSDictionary* row in _contacts)
    {
       if([[row objectForKey:@"buddy_name"] isEqualToString:[user objectForKey:kusernameKey]] &&
         [[row objectForKey:@"account_id"]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
       {
           pos=counter;
           break; 
       }
        counter++; 
    }

    
    
    //not there
    if(pos<0)
    {
        //mutex to prevent others from modifying contacts at the same time
        dispatch_sync(dispatch_get_main_queue(),
                      ^{
        //insert into tableview
        // for now just online
        NSArray* contactRow=[[DataLayer sharedInstance] contactForUsername:[user objectForKey:kusernameKey] forAccount:[user objectForKey:kaccountNoKey]];
        
        if(!(contactRow.count>=1))
        {
            debug_NSLog(@"ERROR:could not find contact row"); 
            return;
        }
        //insert into datasource
        [_contacts insertObject:[contactRow objectAtIndex:0] atIndex:0];
        //sort
        NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:@"buddy_name"  ascending:YES];
        NSArray* sortArray =[NSArray arrayWithObjects:descriptor,nil];
        [_contacts sortUsingDescriptors:sortArray];
  
        //find where it is
        int pos=0;
        int counter=0;
        for(NSDictionary* row in _contacts)
        {
            if([[row objectForKey:@"buddy_name"] isEqualToString:[user objectForKey:kusernameKey]] &&
               [[row objectForKey:@"account_id"]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
            {
                pos=counter;
                break;
            }
            counter++; 
        }

            debug_NSLog(@"inserting %@ at pos %d", [_contacts objectAtIndex:pos], pos);
             [_contactsTable beginUpdates];
              NSIndexPath *path1 = [NSIndexPath indexPathForRow:pos inSection:konlineSection];
             [_contactsTable insertRowsAtIndexPaths:@[path1]
                                   withRowAnimation:UITableViewRowAnimationFade];
             [_contactsTable endUpdates];
                      });
        
    }else
    {
        debug_NSLog(@"user %@ already in list",[user objectForKey:kusernameKey]);
    }
    
}

-(void) removeUser:(NSDictionary*) user
{
    
}

-(void) updateUser:(NSDictionary*) user
{
    
}


#pragma mark tableview datasource 
-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    int toReturn=0;
    
    switch (section) {
        case kinfoSetion:
            break;
        case konlineSection:
            toReturn= [_contacts count];
        case koflineSection:
            break;
        default:
            break;
    }
    
    return toReturn;
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

    cell.accountNo=[[row objectForKey:@"account_id"] integerValue];
    cell.username=[row objectForKey:@"buddy_name"] ;
    
    cell.count=[[DataLayer sharedInstance] countUserUnreadMessages:cell.username forAccount:[NSString stringWithFormat:@"%d", cell.accountNo]];
   
    return cell; 
}

#pragma mark tableview delegate


@end
