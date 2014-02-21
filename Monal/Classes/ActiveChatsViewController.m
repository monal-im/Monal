//
//  ActiveChatsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "ActiveChatsViewController.h"
#import "DataLayer.h"
#import "MLContactCell.h"
#import "chatViewController.h"
#import "MonalAppDelegate.h"

@interface ActiveChatsViewController ()

@end

@implementation ActiveChatsViewController

#pragma mark view lifecycle
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
    self.navigationItem.title=NSLocalizedString(@"Active Chats",@"");
    self.view.backgroundColor=[UIColor lightGrayColor];
    self.view.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    
    _chatListTable=[[UITableView alloc] init];
    _chatListTable.delegate=self;
    _chatListTable.dataSource=self;
    
    self.view=_chatListTable;
    
    UIBarButtonItem* rightButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Close All",@"") style:UIBarButtonItemStyleBordered target:self action:@selector(closeAll)];
    self.navigationItem.rightBarButtonItem=rightButton;
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(refreshDisplay) name:UIApplicationWillEnterForegroundNotification object:nil];
    
}


-(void) refreshDisplay
{
    _contacts=[[DataLayer sharedInstance] activeBuddies];
    [_chatListTable reloadData];
    MonalAppDelegate* appDelegate= (MonalAppDelegate*) [UIApplication sharedApplication].delegate;
    [appDelegate updateUnread];
}

-(void) viewWillAppear:(BOOL)animated
{
    [self refreshDisplay];
    [[MLXMPPManager sharedInstance] handleNewMessage:nil];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void) closeAll
{
    [[DataLayer sharedInstance] removeAllActiveBuddies];
    [self refreshDisplay];
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
    
    NSString* fullName=[row objectForKey:@"full_name"];
    if([[fullName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]>0) {
        cell.textLabel.text=fullName;
    }
    else {
        cell.textLabel.text=[row objectForKey:@"buddy_name"];
    }
    
    
    if(![[row objectForKey:@"status"] isEqualToString:@"(null)"] && ![[row objectForKey:@"status"] isEqualToString:@""])
        cell.detailTextLabel.text=[row objectForKey:@"status"];
    
    if(([[row objectForKey:@"state"] isEqualToString:@"away"]) ||
       ([[row objectForKey:@"state"] isEqualToString:@"dnd"])||
       ([[row objectForKey:@"state"] isEqualToString:@"xa"])
       )
    {
        cell.status=kStatusAway;
    }
    else if([[row objectForKey:@"state"] isEqualToString:@"(null)"] || [[row objectForKey:@"state"] isEqualToString:@""])
        cell.status=kStatusOnline;
    else if([[row objectForKey:@"state"] isEqualToString:@"offline"])
        cell.status=kStatusOffline;
    
    cell.accessoryType = UITableViewCellAccessoryNone;
    
    cell.accountNo=[[row objectForKey:@"account_id"] integerValue];
    cell.username=[row objectForKey:@"buddy_name"] ;
    
    //cell.count=[[row objectForKey:@"count"] integerValue];
    NSString* accountNo=[NSString stringWithFormat:@"%d", cell.accountNo];
    cell.count=  [[DataLayer sharedInstance] countUserUnreadMessages:cell.username forAccount:accountNo];
    
    cell.imageView.image=[[MLImageManager sharedInstance] getIconForContact:[row objectForKey:@"buddy_name"] andAccount:accountNo];
    return cell;
}

#pragma mark tableview delegate

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath 
{
    return YES;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSDictionary* contact= [_contacts objectAtIndex:indexPath.row];
        
       [ [DataLayer sharedInstance] removeActiveBuddy:[contact objectForKey:@"buddy_name"] forAccount:[contact objectForKey:@"account_id"]];
        
        [_chatListTable beginUpdates];
           _contacts=[[DataLayer sharedInstance] activeBuddies];
        [_chatListTable deleteRowsAtIndexPaths:@[indexPath]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
        [_chatListTable endUpdates];
        
        
    }
}

-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
      
       // [[_contacts objectAtIndex:indexPath.row] setObject:[NSNumber numberWithInt:0] forKey:@"count"];
        
        //make chat view
//        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
//        {
//            if([[self.navigationController topViewController] isKindOfClass:[chatViewController class]])
//            {
//                chatViewController* currentTop=(chatViewController*)[self.navigationController topViewController];
//                if([currentTop.buddyName isEqualToString:[[_contacts objectAtIndex:indexPath.row] objectForKey:@"buddy_name"]] &&
//                   [currentTop.accountNo isEqualToString:
//                    [NSString stringWithFormat:@"%d",[[[_contacts objectAtIndex:indexPath.row] objectForKey:@"account_id"] integerValue]] ]
//                   )
//                {
//                    // do nothing
//                    return;
//                }
//                else
//                {
//                    [self.navigationController  popToRootViewControllerAnimated:NO];
//                }
//            }
    
        
        chatViewController* chatVC = [[chatViewController alloc] initWithContact:[_contacts objectAtIndex:indexPath.row] ];
        [self.navigationController pushViewController:chatVC animated:YES];
        
        [tableView beginUpdates];
        [tableView reloadRowsAtIndexPaths:@[indexPath]
                         withRowAnimation:UITableViewRowAnimationNone];
        [tableView endUpdates];
        
        _lastSelectedUser=[_contacts objectAtIndex:indexPath.row];
//    }
    
    
}



@end
