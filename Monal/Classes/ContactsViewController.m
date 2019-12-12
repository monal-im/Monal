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
#import "addContact.h"
#import "CallViewController.h"
#import "MonalAppDelegate.h"
#import "UIColor+Theme.h"


#define konlineSection 1
#define kofflineSection 2

@interface ContactsViewController () 
@property (nonatomic, strong) NSArray* searchResults ;
@property (nonatomic, strong) UISearchController *searchController;

@property (nonatomic ,strong) NSMutableArray* contacts;
@property (nonatomic ,strong) NSMutableArray* offlineContacts;
@property (nonatomic ,strong) MLContact* lastSelectedContact;

@end

@implementation ContactsViewController



#pragma mark view life cycle
- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    self.navigationItem.title=NSLocalizedString(@"Contacts",@"");
    
    self.contactsTable=self.tableView;
    self.contactsTable.delegate=self;
    self.contactsTable.dataSource=self;
    
    
    self.contacts=[[NSMutableArray alloc] init] ;
    self.offlineContacts=[[NSMutableArray alloc] init] ;
    
    [self.contactsTable reloadData];
    
    
    [self.contactsTable registerNib:[UINib nibWithNibName:@"MLContactCell"
                                                   bundle:[NSBundle mainBundle]]
             forCellReuseIdentifier:@"ContactCell"];
    
    self.splitViewController.preferredDisplayMode=UISplitViewControllerDisplayModeAllVisible;
    
    self.searchController =[[UISearchController alloc] initWithSearchResultsController:nil];
    
    self.searchController.searchResultsUpdater = self;
    self.searchController.delegate=self;
    self.searchController.dimsBackgroundDuringPresentation = NO;
    self.definesPresentationContext = YES;
    
    if (@available(iOS 11.0, *)) {
        self.navigationItem.searchController= self.searchController;
    }
    else  {
        // Install the search bar as the table header.
        UITableView *tableView = (UITableView *)self.view;
        tableView.tableHeaderView = self.searchController.searchBar;
    }
    
    self.tableView.emptyDataSetSource = self;
    self.tableView.emptyDataSetDelegate = self;
    
    MonalAppDelegate* appDelegate= (MonalAppDelegate*) [UIApplication sharedApplication].delegate;
    appDelegate.splitViewController= self.splitViewController;
    appDelegate.tabBarController = (MLTabBarController *) self.tabBarController;
    
    
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}


-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    self.lastSelectedContact=nil;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshDisplay) name:UIApplicationWillEnterForegroundNotification object:nil];
    [self refreshDisplay];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(addOnlineUser:) name: kMonalContactOnlineNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshDisplay) name:kMonalAccountStatusChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearAccount:) name:kMonalAccountClearContacts object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshContact:) name: kMonalContactRefresh object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(presentChat:) name:kMonalPresentChat object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(removeOnlineUser:) name: kMonalContactOfflineNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showCallRequest:) name:kMonalCallRequestNotice object:nil];
    
    [[MLXMPPManager sharedInstance] handleNewMessage:nil];
    
    if(![[NSUserDefaults standardUserDefaults] boolForKey:@"HasSeenIntro"]) {
        [self performSegueWithIdentifier:@"showIntro" sender:self];
    }
    else if([[MLXMPPManager sharedInstance].connectedXMPP count]==0)
    {
        if(![[NSUserDefaults standardUserDefaults] boolForKey:@"HasSeenLogin"]) {
            [self performSegueWithIdentifier:@"showLogin" sender:self];
        }
    } else  {
        //for 3->4 release remove later
        if(![[NSUserDefaults standardUserDefaults] boolForKey:@"HasSeeniOS13Message"]) {
            
            UIAlertController *messageAlert =[UIAlertController alertControllerWithTitle:@"Notification Changes" message:[NSString stringWithFormat:@"Notifications have changed in iOS 13 because of some iOS changes. For now you will just see something saying there is a new message and not the text or who sent it. I have decided to do this so you have reliable messaging while I work to update Monal to get the old expereince back."] preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *acceptAction =[UIAlertAction actionWithTitle:@"Got it!" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self dismissViewControllerAnimated:YES completion:nil];
                
            }];
            
            [messageAlert addAction:acceptAction];
            [self.tabBarController presentViewController:messageAlert animated:YES completion:nil];
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"HasSeeniOS13Message"];
        }
    }
    
    if(self.contacts.count+self.offlineContacts.count==0)
    {
        [self.tableView reloadData];
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



#pragma mark - updating user display

-(NSInteger) positionOfOnlineContact:(MLContact *) user
{
    NSInteger pos=0;
    for(MLContact* row in self.contacts)
    {
        if([row.contactJid caseInsensitiveCompare:user.contactJid ]==NSOrderedSame &&
           [row.accountId integerValue]==[user.accountId integerValue] )
        {
            return pos;
        }
        pos++;
    }
    
    return -1;
    
}

-(NSInteger) positionOfOfflineContact:(MLContact *) user
{
    NSInteger pos=0;
    for(MLContact* row in self.offlineContacts)
    {
        if([row.contactJid caseInsensitiveCompare:user.contactJid ]==NSOrderedSame &&
           [row.accountId integerValue]==[user.accountId integerValue] )
        {
            
            return pos;
        }
        pos++;
    }
    
    return  -1;
    
}

-(BOOL) updateContactRow:(MLContact *) contactrow withContact:(MLContact *) contact
{
    BOOL hasChange=NO;
    if(contact.state && ![contact.state isEqualToString:contactrow.state] ) {
        contactrow.state=contact.state;
        hasChange=YES;
    }
    if(contact.statusMessage && ![contact.statusMessage isEqualToString:contactrow.statusMessage] ) {
        contactrow.statusMessage=contact.statusMessage;
        hasChange=YES;
    }
    
    if(contact.contactDisplayName && ![contact.contactDisplayName isEqualToString:contactrow.contactDisplayName]  &&
       [contact.contactDisplayName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length>0) {
        contactrow.nickName=contact.nickName;
        contactrow.fullName=contact.fullName;
        hasChange=YES;
    }
    return hasChange;
}

-(void)updateContactAt:(NSInteger) pos withInfo:(MLContact *) contact
{
    MLContact *contactrow =[self.contacts objectAtIndex:pos];
    BOOL hasChange= [self updateContactRow:contactrow withContact:contact];
    
    if(hasChange &&  self.searchResults.count==0)
    {
        
        [self.contactsTable beginUpdates];
        NSIndexPath *path1 = [NSIndexPath indexPathForRow:pos inSection:konlineSection];
        [self.contactsTable reloadRowsAtIndexPaths:@[path1]
                                  withRowAnimation:UITableViewRowAnimationNone];
        [self.contactsTable endUpdates];
    } else  {
        
    }
}

-(void)updateOfflineContactAt:(NSInteger) pos withInfo:(MLContact *) contact
{
    MLContact *contactrow =[self.offlineContacts objectAtIndex:pos];
    
    BOOL hasChange= [self updateContactRow:contactrow withContact:contact];
    
    if(hasChange &&  self.searchResults.count==0) {
        
        [self.contactsTable beginUpdates];
        NSIndexPath *path1 = [NSIndexPath indexPathForRow:pos inSection:kofflineSection];
        [self.contactsTable reloadRowsAtIndexPaths:@[path1]
                                  withRowAnimation:UITableViewRowAnimationNone];
        [self.contactsTable endUpdates];
    } else  {
        
    }
}

-(void) refreshContact:(NSNotification *) notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        MLContact* user = [notification.userInfo objectForKey:@"contact"];;
        NSInteger initalPos=-1;
        initalPos=[self positionOfOnlineContact:user];
        if(initalPos>=0)
        {
            [self updateContactAt:initalPos withInfo:user];
        }
        else
        {
            //offline?
            initalPos=[self positionOfOfflineContact:user];
            
            if(initalPos>=0)
            {
                [self updateOfflineContactAt:initalPos withInfo:user];
            }
            
        }
    });
}


-(void) addOnlineUser:(NSNotification *) notification
{
    MLContact *contact = [notification.userInfo objectForKey:@"contact"];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
        {
            return;
        }
        
        if (self.navigationController.topViewController!=self)
        {
            return;
        }
        NSInteger initalPos=-1;
        initalPos=[self positionOfOnlineContact:contact];
        if(initalPos>=0)
        {
            DDLogVerbose(@"user %@ already in list updating status and nothing else",contact.contactJid);
            [self updateContactAt:initalPos withInfo:contact];
        }
        else
        {
            
            //insert into tableview
            // for now just online
            [[DataLayer sharedInstance] contactForUsername:contact.contactJid forAccount:contact.accountId withCompletion:^(NSArray * contactRow) {
                
                //mutex to prevent others from modifying contacts at the same time
                dispatch_async(dispatch_get_main_queue(),
                               ^{
                    //check if already there
                    NSInteger pos=-1;
                    NSInteger offlinepos=-1;
                    pos=[self positionOfOnlineContact:contact];
                    
                    if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                    {
                        offlinepos =[self positionOfOfflineContact:contact];
                        if(offlinepos>=0 && offlinepos<[self.offlineContacts count])
                        {
                            DDLogVerbose(@"removed from offline");
                            
                            [self.offlineContacts removeObjectAtIndex:offlinepos];
                            if(self.searchResults.count==0) {
                                [self.contactsTable beginUpdates];
                                NSIndexPath *path2 = [NSIndexPath indexPathForRow:offlinepos inSection:kofflineSection];
                                [self.contactsTable deleteRowsAtIndexPaths:@[path2]
                                                          withRowAnimation:UITableViewRowAnimationFade];
                                [self.contactsTable endUpdates];
                            }
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
                        [self.contacts insertObject:[contactRow objectAtIndex:0] atIndex:0];
                        
                        //sort
                        NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:@"contactJid"  ascending:YES];
                        NSArray* sortArray =[NSArray arrayWithObjects:descriptor,nil];
                        [self.contacts sortUsingDescriptors:sortArray];
                        
                        //find where it is
                        NSInteger newpos=[self positionOfOnlineContact:contact];
                        
                        DDLogVerbose(@"sorted contacts %@", self.contacts);
                        
                        DDLogVerbose(@"inserting %@ st sorted  pos %ld", [self.contacts objectAtIndex:newpos], (long)newpos);
                        
                        if(self.searchResults.count==0) {
                            [self.contactsTable beginUpdates];
                            
                            NSIndexPath *path1 = [NSIndexPath indexPathForRow:newpos inSection:konlineSection];
                            [self.contactsTable insertRowsAtIndexPaths:@[path1]
                                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                            
                            [self.contactsTable endUpdates];
                        }
                        
                        
                    }else
                    {
                        DDLogVerbose(@"user %@ already in list updating status",contact.contactJid);
                        [self updateContactAt:pos withInfo:contact];
                    }
                });
            }];
        }
    });
    
}

-(void) removeOnlineUser:(NSNotification *) notification
{
    MLContact* contact = [notification.userInfo objectForKey:@"contact"];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
        {
            return;
        }
        
        if (self.navigationController.topViewController!=self)
        {
            return;
        }
        
        [[DataLayer sharedInstance] contactForUsername:contact.contactJid forAccount:contact.accountId withCompletion:^(NSArray* contactRow) {
            
            dispatch_async(dispatch_get_main_queue(),
                           ^{
                //mutex to prevent others from modifying contacts at the same time
                
                //check if  there
                NSInteger  pos=-1;
                NSInteger  counter=0;
                NSInteger  offlinepos=-1;
                pos=[self positionOfOnlineContact:contact];
                
                
                if((contactRow.count<1))
                {
                    DDLogError(@"ERROR:could not find contact row");
                    return;
                }
                
                if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                {
                    
                    counter=0;
                    offlinepos =[self positionOfOfflineContact:contact];
                    //in contacts but not in offline.. (not in roster this shouldnt happen)
                    if((offlinepos==-1) &&(pos>=0)    && self.searchResults.count==0)
                    {
                        NSMutableDictionary* row= [contactRow objectAtIndex:0] ;
                        [self.offlineContacts insertObject:row atIndex:0];
                        
                        //sort
                        NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:@"contactJid"  ascending:YES];
                        NSArray* sortArray =[NSArray arrayWithObjects:descriptor,nil];
                        [self.offlineContacts sortUsingDescriptors:sortArray];
                        
                        //find where it is
                        
                        counter=0;
                        offlinepos = [self positionOfOfflineContact:contact];
                        DDLogVerbose(@"sorted contacts %@", self.offlineContacts);
                        [self.contactsTable beginUpdates];
                        NSIndexPath *path2 = [NSIndexPath indexPathForRow:offlinepos inSection:kofflineSection];
                        DDLogVerbose(@"inserting offline at %ld", (long)offlinepos);
                        [self.contactsTable insertRowsAtIndexPaths:@[path2]
                                                  withRowAnimation:UITableViewRowAnimationFade];
                        [self.contactsTable endUpdates];
                    }
                }
                
                // it exists
                if(pos>=0  && self.searchResults.count==0)
                {
                    [self.contacts removeObjectAtIndex:pos];
                    DDLogVerbose(@"removing %@ at pos %ld", contact.contactJid, (long)pos);
                    [self.contactsTable beginUpdates];
                    NSIndexPath *path1 = [NSIndexPath indexPathForRow:pos inSection:konlineSection];
                    [self.contactsTable deleteRowsAtIndexPaths:@[path1]
                                              withRowAnimation:UITableViewRowAnimationAutomatic];
                    
                    
                    [self.contactsTable endUpdates];
                }
                
            });
        }];
    });
    
}

-(void) clearAccount:(NSNotification *) notification
{
    NSDictionary* user = notification.userInfo;
    NSString *accountNo = [user objectForKey:kAccountID];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self clearContactsForAccount:accountNo];
    });
    
}

-(void) clearContactsForAccount: (NSString*) accountNo
{
    //mutex to prevent others from modifying contacts at the same time
    dispatch_async(dispatch_get_main_queue(),
                   ^{
        if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
        {
            return;
        }
        
        NSMutableArray* indexPaths =[[NSMutableArray alloc] init];
        NSMutableIndexSet* indexSet = [[NSMutableIndexSet alloc] init];
        
        int counter=0;
        for(MLContact* row in self.contacts)
        {
            if([row.accountId  integerValue]==[accountNo integerValue] )
            {
                DDLogVerbose(@"removing  pos %d", counter);
                NSIndexPath *path1 = [NSIndexPath indexPathForRow:counter inSection:konlineSection];
                [indexPaths addObject:path1];
                [indexSet addIndex:counter];
                
            }
            counter++;
        }
        
        [self.contacts removeObjectsAtIndexes:indexSet];
        [self.contactsTable beginUpdates];
        [self.contactsTable deleteRowsAtIndexPaths:indexPaths
                                  withRowAnimation:UITableViewRowAnimationAutomatic];
        [self.contactsTable endUpdates];
        
    });
    
}


#pragma mark - jingle

-(void) showCallRequest:(NSNotification *) notification
{
    NSDictionary *dic = notification.object;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *contactName=[dic objectForKey:@"user"];
        NSString *userName=[dic objectForKey:kAccountName];
        
        
        UIAlertController *messageAlert =[UIAlertController alertControllerWithTitle:@"Incoming Call" message:[NSString stringWithFormat:@"Incoming audio call to %@ from %@ ",userName,  contactName] preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *acceptAction =[UIAlertAction actionWithTitle:@"Accept" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            
            [self performSegueWithIdentifier:@"showCall" sender:dic];
            
            [[MLXMPPManager sharedInstance] handleCall:dic withResponse:YES];
        }];
        
        UIAlertAction *closeAction =[UIAlertAction actionWithTitle:@"Decline" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            [[MLXMPPManager sharedInstance] handleCall:dic withResponse:NO];
        }];
        [messageAlert addAction:closeAction];
        [messageAlert addAction:acceptAction];
        
        [self.tabBarController presentViewController:messageAlert animated:YES completion:nil];
        
    });
    
}

#pragma mark - message signals

-(void) refreshDisplay
{
    if([[NSUserDefaults standardUserDefaults] boolForKey:@"SortContacts"]) //sort by status
    {
        [[DataLayer sharedInstance] onlineContactsSortedBy:@"Status" withCompeltion:^(NSMutableArray *results) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.contacts= results;
                [self.contactsTable reloadData];
            });
        }];
    }
    else {
        [[DataLayer sharedInstance] onlineContactsSortedBy:@"Name" withCompeltion:^(NSMutableArray *results) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.contacts= results;
                [self.contactsTable reloadData];
            });
        }];
    }
    
    if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
    {
        [[DataLayer sharedInstance] offlineContactsWithCompletion:^(NSMutableArray *results) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.offlineContacts= results;
                [self.contactsTable reloadData];
            });
        }];
    }
    
    if(self.searchResults.count==0)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.contactsTable reloadData];
        });
    }
    
}


-(void) handleNewMessage:(NSNotification *)notification
{
    MLMessage *message =[notification.userInfo objectForKey:@"message"];
    
    if([message.messageType isEqualToString:kMessageTypeStatus]) return;
    
    dispatch_sync(dispatch_get_main_queue(),^{
        if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground || !message.shouldShowAlert)
        {
            return;
        }
    });
    
    DDLogVerbose(@"contats view got new message notice %@", notification.userInfo);
    if([[self.currentNavController topViewController] isKindOfClass:[chatViewController class]]) {
        chatViewController* currentTop=(chatViewController*)[self.currentNavController topViewController];
        if( (([currentTop.contact.contactJid isEqualToString:message.from] )|| ([currentTop.contact.contactJid isEqualToString:message.to] )) &&
           [currentTop.contact.accountId isEqualToString:message.accountId]
           )
        {
            return;
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        int pos=-1;
        int counter=0;
        for(MLContact* row in self.contacts)
        {
            if([row.contactJid caseInsensitiveCompare:message.from]==NSOrderedSame &&
               [row.accountId  integerValue]==[message.accountId integerValue])
            {
                pos=counter;
                break;
            }
            counter++;
        }
        
        if(pos>=0)
        {
            
            //                          int unreadCount=[[[self.contacts objectAtIndex:pos] objectForKey:@"count"] integerValue];
            //                          unreadCount++;
            //                         int unreadCount= [[DataLayer sharedInstance] countUserUnreadMessages:[notification.userInfo objectForKey:@"from"] forAccount:[notification.userInfo objectForKey:kaccountNoKey]];
            //                          [[self.contacts objectAtIndex:pos] setObject: [NSNumber numberWithInt:unreadCount] forKey:@"count"];
            
            
            
            NSIndexPath *path1 = [NSIndexPath indexPathForRow:pos inSection:konlineSection];
            [self.contactsTable beginUpdates];
            [self.contactsTable reloadRowsAtIndexPaths:@[path1]
                                      withRowAnimation:UITableViewRowAnimationNone];
            [self.contactsTable endUpdates];
        }
    });
    
}

#pragma mark - chat presentation
-(void) presentChat:(NSNotification *)notification
{
    NSDictionary *userinfo = notification.userInfo;
    MLContact *row = [userinfo objectForKey:@"contact"];
    
    [self presentChatWithRow:row];
    
}

-(void) presentChatWithRow:(MLContact *)row
{
    if([self.lastSelectedContact.contactJid isEqualToString:row.contactJid] &&
       [self.lastSelectedContact.accountId integerValue]==[row.accountId integerValue]) {
        return;
    }
    
    self.lastSelectedContact=row;
    [self  performSegueWithIdentifier:@"showConversation" sender:row];
}

-(void) prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"showConversation"])
    {
        UINavigationController *nav = segue.destinationViewController;
        chatViewController* chatVC = (chatViewController *)nav.topViewController;
        [chatVC setupWithContact:sender];
    }
    else if([segue.identifier isEqualToString:@"showDetails"])
    {
        UINavigationController *nav = segue.destinationViewController;
        ContactDetails* details = (ContactDetails *)nav.topViewController;
        details.contact= sender;
    }
    else  if([segue.identifier isEqualToString:@"showCall"])
    {
        
        CallViewController* details = (CallViewController *)segue.destinationViewController;
        details.contact= sender;
    }
    
    
    
    
}



#pragma mark - Search Controller

- (void)didDismissSearchController:(UISearchController *)searchController;
{
    self.searchResults=nil;
    [self.tableView reloadData];
}


- (void)updateSearchResultsForSearchController:(UISearchController *)searchController;
{
    if(searchController.searchBar.text.length>0) {
        
        NSString *term = [searchController.searchBar.text  copy];
        self.searchResults = [[DataLayer sharedInstance] searchContactsWithString:term];
        
    } else  {
        self.searchResults=nil;
    }
    [self.tableView reloadData];
}


#pragma mark - tableview datasource
-(NSString*) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString* toReturn=nil;
    switch (section) {
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

-(NSArray<UITableViewRowAction *> *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewRowAction *delete = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive title:@"Delete" handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {
        [self deleteRowAtIndexPath:indexPath];
    }];
    UITableViewRowAction *mute;
    MLContactCell *cell = (MLContactCell *)[tableView cellForRowAtIndexPath:indexPath];
    if(cell.muteBadge.hidden)
    {
        mute = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDefault title:@"Mute" handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {
            [self muteContactAtIndexPath:indexPath];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            });
        }];
        [mute setBackgroundColor:[UIColor monalGreen]];
        
    } else  {
        mute = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDefault title:@"Unmute" handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {
            [self unMuteContactAtIndexPath:indexPath];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            });
        }];
        [mute setBackgroundColor:[UIColor monalGreen]];
        
    }
    
    //    UITableViewRowAction *block = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal title:@"Block" handler:^(UITableViewRowAction * _Nonnull action, NSIndexPath * _Nonnull indexPath) {
    //        [self blockContactAtIndexPath:indexPath];
    //        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    //    }];
    //    [block setBackgroundColor:[UIColor darkGrayColor]];
    
    return @[delete, mute];
    
}

-(MLContact  *)contactAtIndexPath:(NSIndexPath *) indexPath
{
    MLContact* contact;
    if ((indexPath.section==1) && (indexPath.row<=[self.contacts count]) ) {
        contact=[self.contacts objectAtIndex:indexPath.row];
    }
    else if((indexPath.section==2) && (indexPath.row<=[self.offlineContacts count]) ) {
        contact=[self.offlineContacts objectAtIndex:indexPath.row];
    }
    return contact;
}

-(void) muteContactAtIndexPath:(NSIndexPath *) indexPath
{
    MLContact *contact = [self contactAtIndexPath:indexPath];
    if(contact){
        [[DataLayer sharedInstance] muteJid:contact.contactJid];
    }
}

-(void) unMuteContactAtIndexPath:(NSIndexPath *) indexPath
{
    MLContact *contact = [self contactAtIndexPath:indexPath];
    if(contact){
        [[DataLayer sharedInstance] unMuteJid:contact.contactJid];
    }
}


-(void) blockContactAtIndexPath:(NSIndexPath *) indexPath
{
    MLContact *contact = [self contactAtIndexPath:indexPath];
    if(contact){
        [[DataLayer sharedInstance] blockJid:contact.contactJid];
    }
}


-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    NSInteger toreturn=0;
    if(self.searchResults.count>0) {
        toreturn =1;
    }
    else{
        if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
            toreturn =3;
        else
            toreturn =2;
    }
    return toreturn;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger toReturn=0;
    if(self.searchResults.count>0) {
        toReturn=[self.searchResults count];
    }
    //if(tableView ==self.view)
    else {
        switch (section) {
            case konlineSection:
                toReturn= [self.contacts count];
                break;
            case kofflineSection:
                toReturn=[self.offlineContacts count];
                break;
            default:
                break;
        }
    }
    
    
    return toReturn;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    MLContact* row =nil;
    if(self.searchResults.count>0) {
        row = [self.searchResults objectAtIndex:indexPath.row];
    }
    else
    {
        if(indexPath.section==konlineSection)
        {
            row = [self.contacts objectAtIndex:indexPath.row];
        }
        else if(indexPath.section==kofflineSection)
        {
            row = [self.offlineContacts objectAtIndex:indexPath.row];
        }
        else {
            DDLogError(@"Could not identify cell section");
        }
    }
    
    MLContactCell* cell =[tableView dequeueReusableCellWithIdentifier:@"ContactCell"];
    if(!cell)
    {
        cell =[[MLContactCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ContactCell"];
    }
    
    cell.count=0;
    cell.userImage.image=nil;
    cell.statusText.text=@"";
    
    [cell showDisplayName:row.contactDisplayName];
    
    if(![row.statusMessage isEqualToString:@"(null)"] && ![row.statusMessage isEqualToString:@""]) {
        [cell showStatusText:row.statusMessage];
    }
    else {
        [cell showStatusText:nil];
    }
    if(tableView ==self.view) {
        if(indexPath.section==konlineSection)
        {
            NSString* stateString=[row.state stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ;
            
            if(([stateString isEqualToString:@"away"]) ||
               ([stateString isEqualToString:@"dnd"])||
               ([stateString isEqualToString:@"xa"])
               )
            {
                cell.status=kStatusAway;
            }
            else if([row.state isEqualToString:@"(null)"] ||
                    [row.state isEqualToString:@""])
                cell.status=kStatusOnline;
        }
        else  if(indexPath.section==kofflineSection) {
            cell.status=kStatusOffline;
        }}
    else {
        
        if(row.isOnline==YES)
        {
            cell.status=kStatusOnline;
        }
        else
        {
            cell.status=kStatusOffline;
        }
    }
    
    cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
    
    cell.accountNo=[row.accountId integerValue];
    cell.username=row.contactJid;
    
    
    [[DataLayer sharedInstance] countUserUnreadMessages:cell.username forAccount:row.accountId withCompletion:^(NSNumber *unread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            cell.count=[unread integerValue];
        });
    }];
    
    
    [[MLImageManager sharedInstance] getIconForContact:row.contactJid andAccount:row.accountId withCompletion:^(UIImage *image) {
        cell.userImage.image=image;
    }];
    
    [cell setOrb];
    
    [[DataLayer sharedInstance] isMutedJid:row.contactJid  withCompletion:^(BOOL muted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            cell.muteBadge.hidden=!muted;
        });
    }];
    
    return cell;
}

#pragma mark - tableview delegate

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 60.0f;
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

-(void) deleteRowAtIndexPath:(NSIndexPath *) indexPath
{
    MLContact* contact;
    if ((indexPath.section==1) && (indexPath.row<=[self.contacts count]) ) {
        contact=[self.contacts objectAtIndex:indexPath.row];
    }
    else if((indexPath.section==2) && (indexPath.row<=[self.offlineContacts count]) ) {
        contact=[self.offlineContacts objectAtIndex:indexPath.row];
    }
    else {
        //we cannot delete here
        return;
    }
    
    NSString* messageString = [NSString  stringWithFormat:NSLocalizedString(@"Remove %@ from contacts?", nil),contact.fullName ];
    
    BOOL isMUC=[[DataLayer sharedInstance] isBuddyMuc:contact.contactJid forAccount:contact.accountId];
    if(isMUC)
    {
        messageString =@"Leave this converstion?";
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:messageString
                                                                   message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"No" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [alert dismissViewControllerAnimated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        if(isMUC) {
            [[MLXMPPManager sharedInstance] leaveRoom:contact.contactJid withNick:contact.accountNickInGroup forAccountId:contact.accountId ];
        }
        else  {
            [[MLXMPPManager sharedInstance] removeContact:contact];
        }
        
        if(self.searchResults.count==0) {
            [self.contactsTable beginUpdates];
            if ((indexPath.section==1) && (indexPath.row<=[self.contacts count]) ) {
                [self.contacts removeObjectAtIndex:indexPath.row];
            }
            else if((indexPath.section==2) && (indexPath.row<=[self.offlineContacts count]) ) {
                [self.offlineContacts removeObjectAtIndex:indexPath.row];
            }
            else {
                //nothing to delete just end
                [self.contactsTable endUpdates];
                return;
            }
            
            [self.contactsTable deleteRowsAtIndexPaths:@[indexPath]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
            [self.contactsTable endUpdates];
        }
        
    }]];
    
    alert.popoverPresentationController.sourceView=self.tableView;
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self deleteRowAtIndexPath:indexPath];
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary *contactDic;
    if(self.searchResults.count>0)
    {
        contactDic=  [self.searchResults objectAtIndex:indexPath.row];
    }
    else  {
        if(indexPath.section==konlineSection) {
            contactDic=[self.contacts objectAtIndex:indexPath.row];
        }
        else {
            contactDic=[self.offlineContacts objectAtIndex:indexPath.row];
        }
    }
    
    [self performSegueWithIdentifier:@"showDetails" sender:contactDic];
}

-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    MLContact* row;
    
    if(self.searchResults.count>0)
    {
        row= [self.searchResults objectAtIndex:indexPath.row];
    } else
    {
        if((indexPath.section==konlineSection))
        {
            if(indexPath.row<self.contacts.count)
                row=[self.contacts objectAtIndex:indexPath.row];
        }
        else if (indexPath.section==kofflineSection)
        {
            if(indexPath.row<self.offlineContacts.count)
                row= [self.offlineContacts objectAtIndex:indexPath.row];
        }
        
        row.unreadCount=0;
    }
    
    [self presentChatWithRow:row];
    
}

#pragma mark - empty data set

- (UIImage *)imageForEmptyDataSet:(UIScrollView *)scrollView
{
    return [UIImage imageNamed:@"river"];
}

- (NSAttributedString *)titleForEmptyDataSet:(UIScrollView *)scrollView
{
    NSString *text = @"You need friends for this ride";
    
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:18.0f],
                                 NSForegroundColorAttributeName: [UIColor darkGrayColor]};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (NSAttributedString *)descriptionForEmptyDataSet:(UIScrollView *)scrollView
{
    NSString *text = @"Add new contacts with the + button above. Your friends will pop up here when they can talk";
    
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    paragraph.alignment = NSTextAlignmentCenter;
    
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:14.0f],
                                 NSForegroundColorAttributeName: [UIColor lightGrayColor],
                                 NSParagraphStyleAttributeName: paragraph};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (UIColor *)backgroundColorForEmptyDataSet:(UIScrollView *)scrollView
{
    if (@available(iOS 11.0, *)) {
        return [UIColor colorNamed:@"contacts"];
    } else {
        return [UIColor colorWithRed:228/255.0 green:222/255.0 blue:204/255.0 alpha:1];
    }
}

- (BOOL)emptyDataSetShouldDisplay:(UIScrollView *)scrollView
{
    BOOL  toreturn=(self.contacts.count+self.offlineContacts.count==0)?YES:NO;
    
    if(toreturn)
    {
        // A little trick for removing the cell separators
        self.tableView.tableFooterView = [UIView new];
    }
    
    return toreturn;
}


@end
