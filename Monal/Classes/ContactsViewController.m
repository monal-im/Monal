//
//  ContactsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "ContactsViewController.h"
#import "MLContactCell.h"
#import "MLInfoCell.h"
#import "DataLayer.h"
#import "chatViewController.h"
#import "ContactDetails.h"
#import "UIActionSheet+Blocks.h"
#import "addContact.h"


#define kinfoSection 0
#define konlineSection 1
#define kofflineSection 2

@interface ContactsViewController ()
@property (nonatomic, strong) NSArray* searchResults ;


@property (nonatomic ,strong) NSMutableArray* infoCells;
@property (nonatomic ,strong) NSMutableArray* contacts;
@property (nonatomic ,strong) NSMutableArray* offlineContacts;
@property (nonatomic ,strong) NSDictionary* lastSelectedUser;
@property (nonatomic ,strong) UIPopoverController* popOverController;

@end

@implementation ContactsViewController


static const int ddLogLevel = LOG_LEVEL_VERBOSE;

#pragma mark view life cycle
- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    self.navigationItem.title=NSLocalizedString(@"Contacts",@"");
    self.view.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    
    _contactsTable=(UITableView *)self.view;
    _contactsTable.delegate=self;
    _contactsTable.dataSource=self;
    
    self.view=_contactsTable;
    
    // =nil;
    if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))
    {
        self.view.backgroundColor =[UIColor whiteColor];
    }
    else{
        [_contactsTable.backgroundView setBackgroundColor:[UIColor colorWithPatternImage:[UIImage imageNamed:@"debut_dark"]]];
    }
    
    _contacts=[[NSMutableArray alloc] init] ;
    _offlineContacts=[[NSMutableArray alloc] init] ;
    _infoCells=[[NSMutableArray alloc] init] ;
    
    [_contactsTable reloadData];
    

    [_contactsTable registerNib:[UINib nibWithNibName:@"MLContactCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"ContactCell"];
    
    [self.searchDisplayController.searchResultsTableView registerNib:[UINib nibWithNibName:@"MLContactCell"
                                                                                     bundle:[NSBundle mainBundle]]
                                               forCellReuseIdentifier:@"ContactCell"];
    
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    _lastSelectedUser=nil;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshDisplay) name:UIApplicationWillEnterForegroundNotification object:nil];
    [self refreshDisplay];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    
    [[MLXMPPManager sharedInstance] handleNewMessage:nil];
    
    
    if([MLXMPPManager sharedInstance].connectedXMPP.count >0 ) {
        UIBarButtonItem* rightButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addContact)];
        self.navigationItem.rightBarButtonItem=rightButton;
        
        //    UIBarButtonItem* leftButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"menu"] style:UIBarButtonItemStylePlain target:self action:@selector(showMenu)];
        //    self.navigationItem.leftBarButtonItem=leftButton;
    }
    
    
}

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if(![[NSUserDefaults standardUserDefaults] boolForKey:@"hasSeenSelfSignedMessage"])
    {
    //if there are enabed accounts and alert hasnt been shown
    NSArray* accountList=[[DataLayer sharedInstance] accountList];
    int count=0;
    for (NSDictionary* account in accountList)
    {
        if([[account objectForKey:@"enabled"] boolValue]==YES)
        {
            count++;
        }
    }
    
    if(count>0)
    {
        UIAlertView *addError = [[UIAlertView alloc]
								 initWithTitle:@"Changes to SSL"
								 message:@"Monal has changed the way it treats self signed SSL certificates. If you already had an account created and your server uses a self signed SSL certificate, please go to accounts and explicity set the account to allow self signed SSL. This is a new option."
								 delegate:self cancelButtonTitle:@"Close"
								 otherButtonTitles: nil] ;
		[addError show];

    }
        
     [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"hasSeenSelfSignedMessage"];
    }
}


-(void) viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark Actions
-(void)addContact
{
    //present modal view
    addContact* addcontactView =[[addContact alloc] init];
    UINavigationController* addContactNav = [[UINavigationController alloc] initWithRootViewController:addcontactView];
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        addContactNav.modalPresentationStyle=UIModalPresentationFormSheet;
    }
    [self.navigationController presentViewController:addContactNav animated:YES completion:nil];
}

-(void)showMenu
{
    //present modal view
    addContact* addcontactView =[[addContact alloc] init];
    UINavigationController* addContactNav = [[UINavigationController alloc] initWithRootViewController:addcontactView];
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        addContactNav.modalPresentationStyle=UIModalPresentationFormSheet;
    }
    [self.navigationController presentViewController:addContactNav animated:YES completion:nil];
}

#pragma mark updating info display
-(void) showConnecting:(NSDictionary*) info
{
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       [ _infoCells insertObject:info atIndex:0];
                       [_contactsTable beginUpdates];
                       NSIndexPath *path1 = [NSIndexPath indexPathForRow:0 inSection:kinfoSection];
                       [_contactsTable insertRowsAtIndexPaths:@[path1]
                                             withRowAnimation:UITableViewRowAnimationAutomatic];
                       [_contactsTable endUpdates];
                       
                       dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
                       if([[info objectForKey:kinfoStatusKey] isEqualToString:@"Disconnected"])
                       {
                           DDLogInfo(@"hiding disconencted timer started");
                           dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3ull * NSEC_PER_SEC), q_background,  ^{
                               DDLogInfo(@"hiding disconencted");
                               [self hideConnecting:info];
                           });
                       }
                       
                   });
}

-(void) updateConnecting:(NSDictionary*) info
{
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       int pos=-1;
                       int counter=0;
                       for(NSDictionary* row in _infoCells)
                       {
                           if(([[row objectForKey:kaccountNoKey] isEqualToString:[info objectForKey:kaccountNoKey]] ) &&
                              ([[row objectForKey:kinfoTypeKey] isEqualToString:[info objectForKey:kinfoTypeKey]] ) )
                           {
                               pos=counter;
                               break;
                           }
                           counter++;
                       }
                       
                       //not there
                       if(pos>=0)
                       {
                           [_infoCells removeObjectAtIndex:pos];
                           [_infoCells insertObject:info atIndex:pos];
                           
                           [_contactsTable beginUpdates];
                           NSIndexPath *path1 = [NSIndexPath indexPathForRow:pos inSection:kinfoSection];
                           [_contactsTable reloadRowsAtIndexPaths:@[path1]
                                                 withRowAnimation:UITableViewRowAnimationAutomatic];
                           [_contactsTable endUpdates];
                       }
                   });
}


-(void) hideConnecting:(NSDictionary*) info
{
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       int pos=-1;
                       int counter=0;
                       for(NSDictionary* row in _infoCells)
                       {
                           if(([[row objectForKey:kaccountNoKey] isEqualToString:[info objectForKey:kaccountNoKey]] )&&
                              ([[row objectForKey:kinfoTypeKey] isEqualToString:[info objectForKey:kinfoTypeKey]] ))
                           {
                               pos=counter;
                               break;
                           }
                           counter++;
                       }
                       
                       //its there
                       if(pos>=0)
                       {
                           [_infoCells removeObjectAtIndex:pos];
                           [_contactsTable beginUpdates];
                           NSIndexPath *path1 = [NSIndexPath indexPathForRow:pos inSection:kinfoSection];
                           [_contactsTable deleteRowsAtIndexPaths:@[path1]
                                                 withRowAnimation:UITableViewRowAnimationAutomatic];
                           [_contactsTable endUpdates];
                       }
                   });
}

#pragma mark updating user display



-(NSInteger) positionOfOnlineContact:(NSDictionary *) user
{
    NSInteger pos=0;
    for(NSDictionary* row in self.contacts)
    {
        if([[row objectForKey:@"buddy_name"] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
           [[row objectForKey:@"account_id"]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
        {
            return pos;
        }
        pos++;
    }
    
    return -1;
    
}

-(NSInteger) positionOfOfflineContact:(NSDictionary *) user
{
    NSInteger pos=0;
    for(NSDictionary* row in self.offlineContacts)
    {
        if([[row objectForKey:@"buddy_name"] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
           [[row objectForKey:@"account_id"]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
        {
            
            return pos;
        }
        pos++;
    }
    
    return  -1;
    
}


-(void) addOnlineUser:(NSDictionary*) user
{
    if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
    {
        return;
    }
    
    if (self.navigationController.topViewController!=self)
    {
        return;
    }
    //insert into tableview
    // for now just online
    [[DataLayer sharedInstance] contactForUsername:[user objectForKey:kusernameKey] forAccount:[user objectForKey:kaccountNoKey] withCompletion:^(NSArray * contactRow) {
        
        //mutex to prevent others from modifying contacts at the same time
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           //check if already there
                           NSInteger pos=-1;
                           NSInteger offlinepos=-1;
                           pos=[self positionOfOnlineContact:user];
                           
                           if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                           {
                               offlinepos =[self positionOfOfflineContact:user];
                               if(offlinepos>=0 && offlinepos<[_offlineContacts count])
                               {
                                   DDLogVerbose(@"removed from offline");
                                   
                                   [_offlineContacts removeObjectAtIndex:offlinepos];
                                   [_contactsTable beginUpdates];
                                   NSIndexPath *path2 = [NSIndexPath indexPathForRow:offlinepos inSection:kofflineSection];
                                   [_contactsTable deleteRowsAtIndexPaths:@[path2]
                                                         withRowAnimation:UITableViewRowAnimationFade];
                                    [_contactsTable endUpdates];
                               }
                           }
                           
                           //not already in online list
                           if(pos<0)
                           {
                               if(!(contactRow.count>=1))
                               {
                                   DDLogError(@"ERROR:could not find contact row");
                                   return;
                               }
                               //insert into datasource
                               DDLogVerbose(@"inserted into contacts");
                               [_contacts insertObject:[contactRow objectAtIndex:0] atIndex:0];
                               
                               //sort
                               NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:@"buddy_name"  ascending:YES];
                               NSArray* sortArray =[NSArray arrayWithObjects:descriptor,nil];
                               [_contacts sortUsingDescriptors:sortArray];
                               
                               //find where it is
                               NSInteger newpos=[self positionOfOnlineContact:user];
                               
                               DDLogVerbose(@"sorted contacts %@", _contacts);
                               
                               DDLogVerbose(@"inserting %@ st sorted  pos %d", [_contacts objectAtIndex:newpos], newpos);
                               
                               
                               [_contactsTable beginUpdates];
                               
                               NSIndexPath *path1 = [NSIndexPath indexPathForRow:newpos inSection:konlineSection];
                               [_contactsTable insertRowsAtIndexPaths:@[path1]
                                                     withRowAnimation:UITableViewRowAnimationAutomatic];
                               
                               [_contactsTable endUpdates];
                               
                               
                           }else
                           {
                               DDLogVerbose(@"user %@ already in list updating status",[user objectForKey:kusernameKey]);
                               if(pos<self.contacts.count) {
                                   if([user objectForKey:kstateKey])
                                       [[_contacts objectAtIndex:pos] setObject:[user objectForKey:kstateKey] forKey:kstateKey];
                                   if([user objectForKey:kstatusKey])
                                       [[_contacts objectAtIndex:pos] setObject:[user objectForKey:kstatusKey] forKey:kstatusKey];
                                   
                                   if([user objectForKey:kfullNameKey])
                                       [[_contacts objectAtIndex:pos] setObject:[user objectForKey:kfullNameKey] forKey:@"full_name"];
                                   
                                   [_contactsTable beginUpdates];
                                   NSIndexPath *path1 = [NSIndexPath indexPathForRow:pos inSection:konlineSection];
                                   [_contactsTable reloadRowsAtIndexPaths:@[path1]
                                                         withRowAnimation:UITableViewRowAnimationNone];
                                   [_contactsTable endUpdates];
                                   
                               }
                               
                           }
                       });
    }];
    
    
}

-(void) removeOnlineUser:(NSDictionary*) user
{
    
    if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
    {
        return;
    }
    
    if (self.navigationController.topViewController!=self)
    {
        return;
    }
    
    [[DataLayer sharedInstance] contactForUsername:[user objectForKey:kusernameKey] forAccount:[user objectForKey:kaccountNoKey] withCompletion:^(NSArray* contactRow) {
        
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           //mutex to prevent others from modifying contacts at the same time
                           
                           //check if  there
                           NSInteger  pos=-1;
                           NSInteger  counter=0;
                           NSInteger  offlinepos=-1;
                           pos=[self positionOfOnlineContact:user];
                           
                           
                           if((contactRow.count<1))
                           {
                               DDLogError(@"ERROR:could not find contact row");
                               return;
                           }
                           
                           if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                           {
                               
                               counter=0;
                               offlinepos =[self positionOfOfflineContact:user];
                               //in contacts but not in offline.. (not in roster this shouldnt happen)
                               if((offlinepos==-1) &&(pos>=0))
                               {
                                   NSMutableDictionary* row= [contactRow objectAtIndex:0] ;
                                   [_offlineContacts insertObject:row atIndex:0];
                                   
                                   //sort
                                   NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:@"buddy_name"  ascending:YES];
                                   NSArray* sortArray =[NSArray arrayWithObjects:descriptor,nil];
                                   [_offlineContacts sortUsingDescriptors:sortArray];
                                   
                                   //find where it is
                                   
                                   counter=0;
                                   offlinepos = [self positionOfOfflineContact:user];
                                   DDLogVerbose(@"sorted contacts %@", _offlineContacts);
                                   [_contactsTable beginUpdates];
                                   NSIndexPath *path2 = [NSIndexPath indexPathForRow:offlinepos inSection:kofflineSection];
                                   DDLogVerbose(@"inserting offline at %d", offlinepos);
                                   [_contactsTable insertRowsAtIndexPaths:@[path2]
                                                         withRowAnimation:UITableViewRowAnimationFade];
                                   [_contactsTable endUpdates];
                               }
                           }
                           
                           // it exists
                           if(pos>=0)
                           {
                               [_contacts removeObjectAtIndex:pos];
                               DDLogVerbose(@"removing %@ at pos %d", [user objectForKey:kusernameKey], pos);
                               [_contactsTable beginUpdates];
                               NSIndexPath *path1 = [NSIndexPath indexPathForRow:pos inSection:konlineSection];
                               [_contactsTable deleteRowsAtIndexPaths:@[path1]
                                                     withRowAnimation:UITableViewRowAnimationAutomatic];
                               
                               
                               [_contactsTable endUpdates];
                           }
                           
                       });
    }];
    
    
}

-(void) clearContactsForAccount: (NSString*) accountNo
{
    if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
    {
        return;
    }
    
    //mutex to prevent others from modifying contacts at the same time
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       NSMutableArray* indexPaths =[[NSMutableArray alloc] init];
                       NSMutableIndexSet* indexSet = [[NSMutableIndexSet alloc] init];
                       
                       int counter=0;
                       for(NSDictionary* row in _contacts)
                       {
                           if([[row objectForKey:@"account_id"]  integerValue]==[accountNo integerValue] )
                           {
                               DDLogVerbose(@"removing  pos %d", counter);
                               NSIndexPath *path1 = [NSIndexPath indexPathForRow:counter inSection:konlineSection];
                               [indexPaths addObject:path1];
                               [indexSet addIndex:counter];

                           }
                           counter++;
                       }
                       
                       [_contacts removeObjectsAtIndexes:indexSet];
                       [_contactsTable beginUpdates];
                       [_contactsTable deleteRowsAtIndexPaths:indexPaths
                                             withRowAnimation:UITableViewRowAnimationAutomatic];
                       [_contactsTable endUpdates];
                       
                   });
    
}

#pragma mark message signals

-(void) refreshDisplay
{
    
    if([[NSUserDefaults standardUserDefaults] boolForKey:@"SortContacts"]) //sort by status
        _contacts=[NSMutableArray arrayWithArray:[[DataLayer sharedInstance] onlineContactsSortedBy:@"Status"]];
    else
        _contacts=[NSMutableArray arrayWithArray:[[DataLayer sharedInstance] onlineContactsSortedBy:@"Name"]];
    
    if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
    {
    _offlineContacts=[NSMutableArray arrayWithArray:[[DataLayer sharedInstance] offlineContacts]];
    }
    
    if(self.searchResults.count==0)
    {
        [self.contactsTable reloadData];
    }
    
}


-(void) handleNewMessage:(NSNotification *)notification
{
    if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
    {
        return;
    }
    
    DDLogVerbose(@"chat view got new message notice %@", notification.userInfo);
    if([[self.currentNavController topViewController] isKindOfClass:[chatViewController class]]) {
        chatViewController* currentTop=(chatViewController*)[self.currentNavController topViewController];
        if( (([currentTop.contactName isEqualToString:[notification.userInfo objectForKey:@"from"]] )|| ([currentTop.contactName isEqualToString:[notification.userInfo objectForKey:@"to"]] )) &&
           [currentTop.accountNo isEqualToString:
            [NSString stringWithFormat:@"%d",[[notification.userInfo objectForKey:kaccountNoKey] integerValue] ]]
           )
        {
            return;
        }
    }
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       
                       int pos=-1;
                       int counter=0;
                       for(NSDictionary* row in _contacts)
                       {
                           if([[row objectForKey:@"buddy_name"] caseInsensitiveCompare:[notification.userInfo objectForKey:@"from"] ]==NSOrderedSame &&
                              [[row objectForKey:@"account_id"]  integerValue]==[[notification.userInfo objectForKey:kaccountNoKey] integerValue] )
                           {
                               pos=counter;
                               break;
                           }
                           counter++;
                       }
                       
                       if(pos>=0)
                       {
                           
                           //                          int unreadCount=[[[_contacts objectAtIndex:pos] objectForKey:@"count"] integerValue];
                           //                          unreadCount++;
                           //                         int unreadCount= [[DataLayer sharedInstance] countUserUnreadMessages:[notification.userInfo objectForKey:@"from"] forAccount:[notification.userInfo objectForKey:kaccountNoKey]];
                           //                          [[_contacts objectAtIndex:pos] setObject: [NSNumber numberWithInt:unreadCount] forKey:@"count"];
                           
                           
                           
                           NSIndexPath *path1 = [NSIndexPath indexPathForRow:pos inSection:konlineSection];
                           [_contactsTable beginUpdates];
                           [_contactsTable reloadRowsAtIndexPaths:@[path1]
                                                 withRowAnimation:UITableViewRowAnimationNone];
                           [_contactsTable endUpdates];
                       }
                   });
    
}

#pragma mark chat presentation
-(void) presentChatWithName:(NSString *)buddyname account:(NSNumber *) account 
{
    NSDictionary *row =@{@"buddy_name":buddyname, @"account_id": account};
    [self presentChatWithRow:row];
    
}

-(void) presentChatWithRow:(NSDictionary *)row
{
    //make chat view
    chatViewController* chatVC = [[chatViewController alloc] initWithContact:row ];
    

    if([[self.currentNavController topViewController] isKindOfClass:[chatViewController class]])
    {
        chatViewController* currentTop=(chatViewController*)[self.currentNavController topViewController];
        if([currentTop.contactName isEqualToString:[row objectForKey:@"buddy_name"]] &&
           [currentTop.accountNo isEqualToString:
            [NSString stringWithFormat:@"%d",[[row objectForKey:@"account_id"] integerValue]] ]
           )
        {
            // do nothing
            return;
        }
        else
        {            
            [self.currentNavController  popToRootViewControllerAnimated:NO];

        }
    }
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        [self.currentNavController pushViewController:chatVC animated:NO];
    }
    else  {
        [self.currentNavController pushViewController:chatVC animated:YES];
        
    }
    
}

#pragma mark search display delegate

- (void)searchDisplayControllerWillBeginSearch:(UISearchDisplayController *)controller {
    self.searchResults=nil;
}

- (void)searchDisplayControllerWillEndSearch:(UISearchDisplayController *)controller
{
    self.searchResults=nil;

}

-(BOOL) searchDisplayController:(UISearchDisplayController *)controller shouldReloadTableForSearchString:(NSString *)searchString
{
    if(searchString.length >0) {
    
        self.searchResults = [[DataLayer sharedInstance] searchContactsWithString:searchString];
        return YES;
    }
    
    self.searchResults=nil;
    return NO;
}

#pragma mark tableview datasource
-(NSString*) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString* toReturn=nil;
    switch (section) {
        case kinfoSection:
            break;
        case konlineSection:
            toReturn= NSLocalizedString(@"Online", "");
            break;
        case kofflineSection:
            toReturn= NSLocalizedString(@"Offline", "");
            break;
        default:
            break;
    }
    
    return toReturn;
}

-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    NSInteger toreturn=0;
    if(tableView ==self.view) {
        if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
            toreturn =3;
        else
            toreturn =2;
    }
    else  if(tableView ==self.searchDisplayController.searchResultsTableView) {
        toreturn =1;
    }
    
    return toreturn;
    
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger toReturn=0;
    if(tableView ==self.view) {
        switch (section) {
            case kinfoSection:
                toReturn=[_infoCells count];
                break;
            case konlineSection:
                toReturn= [_contacts count];
                break;
            case kofflineSection:
                toReturn=[_offlineContacts count];
                break;
            default:
                break;
        }
    }
    else  if(tableView ==self.searchDisplayController.searchResultsTableView) {
        toReturn=[self.searchResults count];
    }
    
    return toReturn;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if(tableView ==self.view) {
        if(indexPath.section==kinfoSection)
        {
            MLInfoCell* cell =[tableView dequeueReusableCellWithIdentifier:@"InfoCell"];
            if(!cell)
            {
                cell =[[MLInfoCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"InfoCell"];
            }
            
            cell.textLabel.text=[[_infoCells objectAtIndex:indexPath.row] objectForKey:@"accountName"];
            cell.detailTextLabel.text=[[_infoCells objectAtIndex:indexPath.row] objectForKey:@"status"];
            cell.type=[[_infoCells objectAtIndex:indexPath.row] objectForKey:@"type"];
            cell.accountId=[[_infoCells objectAtIndex:indexPath.row] objectForKey:@"acccountId"];
            
            
            if([cell.detailTextLabel.text isEqualToString:@"Connecting"])
            {
                [cell.spinner startAnimating];
            }
            
            return cell;
        }
    }
    
    MLContactCell* cell =[tableView dequeueReusableCellWithIdentifier:@"ContactCell"];
    if(!cell)
    {
        cell =[[MLContactCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ContactCell"];
    }

    NSDictionary* row =nil;
 
    if(indexPath.section==konlineSection)
    {
        row = [_contacts objectAtIndex:indexPath.row];
    }
    
    cell.statusText.text=@"";
    
    if(tableView ==self.view) {
        if(indexPath.section==kofflineSection)
        {
            row = [_offlineContacts objectAtIndex:indexPath.row];
        }
    }
    else  if(tableView ==self.searchDisplayController.searchResultsTableView) {
        row = [self.searchResults objectAtIndex:indexPath.row];
    }
    
    NSString* fullName=[row objectForKey:@"full_name"];
    if([[fullName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]>0) {
        [cell showDisplayName:fullName];
    }
    else {
        [cell showDisplayName:[row objectForKey:@"buddy_name"]];
    }
    
    if(![[row objectForKey:@"status"] isEqualToString:@"(null)"] && ![[row objectForKey:@"status"] isEqualToString:@""]) {
        [cell showStatusText:[row objectForKey:@"status"]];
    }
    else {
       [cell showStatusText:nil];
    }
        if(tableView ==self.view) {
    if(indexPath.section==konlineSection)
    {
        NSString* stateString=[[row objectForKey:@"state"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ;
        
        if(([stateString isEqualToString:@"away"]) ||
           ([stateString isEqualToString:@"dnd"])||
           ([stateString isEqualToString:@"xa"])
           )
        {
            cell.status=kStatusAway;
        }
        else if([[row objectForKey:@"state"] isEqualToString:@"(null)"] || [[row objectForKey:@"state"] isEqualToString:@""])
            cell.status=kStatusOnline;
    }
    else  if(indexPath.section==kofflineSection) {
        cell.status=kStatusOffline;
    }}
        else {
            NSNumber *online=[row objectForKey:@"online"];
            if([online boolValue]==YES)
            {
                cell.status=kStatusOnline;
            }
            else
            {
                cell.status=kStatusOffline;
            }
        }
    
    cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
    
    cell.accountNo=[[row objectForKey:@"account_id"] integerValue];
    cell.username=[row objectForKey:@"buddy_name"] ;
    
    //cell.count=[[row objectForKey:@"count"] integerValue];
    NSString* accountNo=[NSString stringWithFormat:@"%ld", (long)cell.accountNo];
   [[DataLayer sharedInstance] countUserUnreadMessages:cell.username forAccount:accountNo withCompletion:^(NSNumber *unread) {
       dispatch_async(dispatch_get_main_queue(), ^{
           cell.count=[unread integerValue];
       });
   }];
    cell.userImage.image=[[MLImageManager sharedInstance] getIconForContact:[row objectForKey:@"buddy_name"] andAccount:accountNo];
    
    [cell setOrb];
    
    return cell;
}

#pragma mark tableview delegate

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 50.0f;
}

-(NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return @"Remove Contact";
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    if(tableView ==self.view) {
        return YES;
    }
    else
    {
        return NO;
    }
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
    if(tableView ==self.view) {
        return YES;
    }
    else
    {
        return NO;
    }
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSDictionary* contact;
        if ((indexPath.section==1) && (indexPath.row<=[_contacts count]) ) {
            contact=[_contacts objectAtIndex:indexPath.row];
        }
        else if((indexPath.section==2) && (indexPath.row<=[_offlineContacts count]) ) {
                contact=[_offlineContacts objectAtIndex:indexPath.row];
        }
        else {
            //we cannot delete here
            return;
        }
        
        NSString* messageString = [NSString  stringWithFormat:NSLocalizedString(@"Remove %@ from contacts?", nil),[contact objectForKey:@"full_name"] ];
        
        BOOL isMUC=[[DataLayer sharedInstance] isBuddyMuc:[contact objectForKey:@"buddy_name"] forAccount:[contact objectForKey:@"account_id"]];
        if(isMUC)
        {
            messageString =@"Leave this converstion?";
        }
  
        
        RIButtonItem* cancelButton = [RIButtonItem itemWithLabel:NSLocalizedString(@"Cancel", nil) action:^{
            
        }];
        
        RIButtonItem* yesButton = [RIButtonItem itemWithLabel:NSLocalizedString(@"Yes", nil) action:^{
            if(isMUC) {
                [[MLXMPPManager sharedInstance] leaveRoom:[contact objectForKey:@"buddy_name"] forAccountId: [NSString stringWithFormat:@"%@",[contact objectForKey:@"account_id"]]];
            }
            else  {
                [[MLXMPPManager sharedInstance] removeContact:contact];
            }
            
            [_contactsTable beginUpdates];
            if ((indexPath.section==1) && (indexPath.row<=[_contacts count]) ) {
               [_contacts removeObjectAtIndex:indexPath.row];
            }
            else if((indexPath.section==2) && (indexPath.row<=[_offlineContacts count]) ) {
                 [_offlineContacts removeObjectAtIndex:indexPath.row];
            }
            else {
                //nothing to delete just end
                 [_contactsTable endUpdates];
                return; 
                
            }
          
            
            [_contactsTable deleteRowsAtIndexPaths:@[indexPath]
                                  withRowAnimation:UITableViewRowAnimationAutomatic];
            [_contactsTable endUpdates];
            
        }];
        
        UIActionSheet* sheet =[[UIActionSheet alloc] initWithTitle:messageString cancelButtonItem:cancelButton destructiveButtonItem:yesButton otherButtonItems: nil];
        [sheet showFromTabBar:self.presentationTabBarController.tabBar];
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    ContactDetails* detailVC =nil;
    if(tableView ==self.view) {
        if(indexPath.section==konlineSection)
            detailVC= [[ContactDetails alloc]  initWithContact:[_contacts objectAtIndex:indexPath.row] ];
        else
            detailVC=[[ContactDetails alloc]  initWithContact:[_offlineContacts objectAtIndex:indexPath.row] ];
    }
    
    else  if(tableView ==self.searchDisplayController.searchResultsTableView)
    {
        detailVC=[[ContactDetails alloc]  initWithContact:[self.searchResults objectAtIndex:indexPath.row] ];
    }
    
    detailVC.currentNavController=self.currentNavController;
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        MLChatCell* cell = (MLChatCell*)[tableView cellForRowAtIndexPath:indexPath];
        _popOverController = [[UIPopoverController alloc] initWithContentViewController:detailVC];
        detailVC.popOverController=_popOverController;
        _popOverController.popoverContentSize = CGSizeMake(320, 480);
        [_popOverController presentPopoverFromRect:cell.bounds
                                            inView:cell
                          permittedArrowDirections:UIPopoverArrowDirectionLeft animated:YES];
    }
    else
    {
        [self.currentNavController pushViewController:detailVC animated:YES];
    }
    
}

-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    
    NSMutableDictionary* row;
    if(tableView ==self.view) {
    if(indexPath.section==kinfoSection)
    {
        return;
    }
    else
        if((indexPath.section==konlineSection))
        {
            row=[_contacts objectAtIndex:indexPath.row];
        }
        else if (indexPath.section==kofflineSection)
        {
            row= [_offlineContacts objectAtIndex:indexPath.row];
        }
    
    [row setObject:[NSNumber numberWithInt:0] forKey:@"count"];
    }
    else  if(tableView ==self.searchDisplayController.searchResultsTableView)
    {
        row= [self.searchResults objectAtIndex:indexPath.row];
    }

    [self presentChatWithRow:row];
    
    [tableView beginUpdates];
    [tableView reloadRowsAtIndexPaths:@[indexPath]
                     withRowAnimation:UITableViewRowAnimationNone];
    [tableView endUpdates];
    
    _lastSelectedUser=row;
    
    
}



@end
