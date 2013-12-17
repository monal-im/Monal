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
    
    // =nil;
    [_contactsTable.backgroundView setBackgroundColor:[UIColor colorWithPatternImage:[UIImage imageNamed:@"debut_dark"]]];
    
    
    _contacts=[[NSMutableArray alloc] init] ;
    _offlineContacts=[[NSMutableArray alloc] init] ;
    _infoCells=[[NSMutableArray alloc] init] ;
    
    [_contactsTable reloadData];
    
    UIBarButtonItem* rightButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addContact)];
    self.navigationItem.rightBarButtonItem=rightButton;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
}

-(void) viewWillAppear:(BOOL)animated
{
    _lastSelectedUser=nil;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshDisplay) name:UIApplicationWillEnterForegroundNotification object:nil];
    [self refreshDisplay];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    
    [[MLXMPPManager sharedInstance] handleNewMessage:nil];
}

-(void) viewWillDisappear:(BOOL)animated
{
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
    [self.navigationController presentModalViewController:addContactNav animated:YES];
    
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
                           debug_NSLog(@"hiding disconencted timer started");
                           dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3ull * NSEC_PER_SEC), q_background,  ^{
                               debug_NSLog(@"hiding disconencted");
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
    
    //mutex to prevent others from modifying contacts at the same time
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       //check if already there
                       int pos=-1;
                       int offlinepos=-1;
                       int counter=0;
                       for(NSDictionary* row in _contacts)
                       {
                           if([[row objectForKey:@"buddy_name"] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
                              [[row objectForKey:@"account_id"]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
                           {
                               pos=counter;
                               break;
                           }
                           counter++;
                       }
                       
                       
                       if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                       {
                           counter=0;
                           for(NSDictionary* row in _offlineContacts)
                           {
                               if([[row objectForKey:@"buddy_name"] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
                                  [[row objectForKey:@"account_id"]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
                               {
                                   offlinepos=counter;
                                   break;
                               }
                               counter++;
                           }
                       }
                       
                       //not there
                       if(pos<0)
                       {
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
                           
                           if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                           {
                               if(offlinepos>=0 && offlinepos<[_offlineContacts count])
                               {
                                   [_offlineContacts removeObjectAtIndex:offlinepos];
                               }
                           }
                           
                           //sort
                           NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:@"buddy_name"  ascending:YES];
                           NSArray* sortArray =[NSArray arrayWithObjects:descriptor,nil];
                           [_contacts sortUsingDescriptors:sortArray];
                           
                           //find where it is
                           int pos=0;
                           int counter=0;
                           for(NSDictionary* row in _contacts)
                           {
                               if([[row objectForKey:@"buddy_name"] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
                                  [[row objectForKey:@"account_id"]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
                               {
                                   pos=counter;
                                   break;
                               }
                               counter++;
                           }
                           debug_NSLog(@"sorted contacts %@", _contacts);
                           
                           debug_NSLog(@"inserting %@ at pos %d", [_contacts objectAtIndex:pos], pos);
                           [_contactsTable beginUpdates];
                           NSIndexPath *path1 = [NSIndexPath indexPathForRow:pos inSection:konlineSection];
                           [_contactsTable insertRowsAtIndexPaths:@[path1]
                                                 withRowAnimation:UITableViewRowAnimationAutomatic];
                           
                           if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                           {
                               if(offlinepos>=0 && offlinepos<=[_offlineContacts count]) // since if last one is delted it is equal to count   
                               {
                                   NSIndexPath *path2 = [NSIndexPath indexPathForRow:offlinepos inSection:kofflineSection];
                                   [_contactsTable deleteRowsAtIndexPaths:@[path2]
                                                         withRowAnimation:UITableViewRowAnimationFade];
                               }
                           }
                           [_contactsTable endUpdates];
                           
                           
                       }else
                       {
                           debug_NSLog(@"user %@ already in list",[user objectForKey:kusernameKey]);
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
                   });
    
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
    
    //mutex to prevent others from modifying contacts at the same time
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       //check if  there
                       int pos=-1;
                       int counter=0;
                       int offlinepos=-1;
                       for(NSDictionary* row in _contacts)
                       {
                           if([[row objectForKey:@"buddy_name"] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
                              [[row objectForKey:@"account_id"]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
                           {
                               pos=counter;
                               break;
                           }
                           counter++;
                       }
                       
                       
                       NSArray* contactRow=[[DataLayer sharedInstance] contactForUsername:[user objectForKey:kusernameKey] forAccount:[user objectForKey:kaccountNoKey]];
                       
                       if(!(contactRow.count>=1))
                       {
                           debug_NSLog(@"ERROR:could not find contact row");
                           return;
                       }
                       
                       if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                       {
                       
                       counter=0;
                       for(NSDictionary* row in _offlineContacts)
                       {
                           if([[row objectForKey:@"buddy_name"] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
                              [[row objectForKey:@"account_id"]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
                           {
                               offlinepos=counter;
                               break;
                           }
                           counter++;
                       }
                       
                       if(offlinepos==-1)
                       {
                           NSMutableDictionary* row= [contactRow objectAtIndex:0] ;
                           [_offlineContacts insertObject:row atIndex:0];
                           
                           //sort
                           NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:@"buddy_name"  ascending:YES];
                           NSArray* sortArray =[NSArray arrayWithObjects:descriptor,nil];
                           [_offlineContacts sortUsingDescriptors:sortArray];
                           
                           //find where it is
                           
                           counter=0;
                           for(NSDictionary* row in _offlineContacts)
                           {
                               if([[row objectForKey:@"buddy_name"] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
                                  [[row objectForKey:@"account_id"]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
                               {
                                   offlinepos=counter;
                                   break;
                               }
                               counter++;
                           }
                           debug_NSLog(@"sorted contacts %@", _offlineContacts);
                       }
                       }
                       
                       //not there
                       if(pos>=0)
                       {
                           [_contacts removeObjectAtIndex:pos];
                           debug_NSLog(@"removing %@ at pos %d", [user objectForKey:kusernameKey], pos);
                           [_contactsTable beginUpdates];
                           NSIndexPath *path1 = [NSIndexPath indexPathForRow:pos inSection:konlineSection];
                           [_contactsTable deleteRowsAtIndexPaths:@[path1]
                                                 withRowAnimation:UITableViewRowAnimationAutomatic];
                           
                           if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"] && offlinepos>-1)
                           {
                               NSIndexPath *path2 = [NSIndexPath indexPathForRow:offlinepos inSection:kofflineSection];
                               [_contactsTable insertRowsAtIndexPaths:@[path2]
                                                     withRowAnimation:UITableViewRowAnimationFade];
                           }
                           
                           [_contactsTable endUpdates];
                       }

                   });
 
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
                               
                               debug_NSLog(@"removing  pos %d", counter);
                               
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
    
    if([[NSUserDefaults standardUserDefaults] objectForKey:@"SortContacts"]) //sort by status
        _contacts=[NSMutableArray arrayWithArray:[[DataLayer sharedInstance] onlineBuddiesSortedBy:@"Status"]];
    else
        _contacts=[NSMutableArray arrayWithArray:[[DataLayer sharedInstance] onlineBuddiesSortedBy:@"Name"]];
    
    if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
    {
    _offlineContacts=[NSMutableArray arrayWithArray:[[DataLayer sharedInstance] offlineBuddies]];
    }
    
    [self.contactsTable reloadData];
    
}


-(void) handleNewMessage:(NSNotification *)notification
{
    if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
    {
        return;
    }
    
    debug_NSLog(@"chat view got new message notice %@", notification.userInfo);
    
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
    
    if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
        return 3;
    else
        return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    int toReturn=0;
    
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
    
    return toReturn;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
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
    
    if(indexPath.section==kofflineSection)
    {
        row = [_offlineContacts objectAtIndex:indexPath.row];
    }
    
    cell.textLabel.text=[row objectForKey:@"full_name"];
    if(![[row objectForKey:@"status"] isEqualToString:@"(null)"] && ![[row objectForKey:@"status"] isEqualToString:@""])
        cell.detailTextLabel.text=[row objectForKey:@"status"];
    else
        cell.detailTextLabel.text=nil;
    
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
    
    cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
    
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
        NSString* messageString = [NSString  stringWithFormat:NSLocalizedString(@"Remove %@ from contacts?", nil),[contact objectForKey:@"full_name"] ];
        RIButtonItem* cancelButton = [RIButtonItem itemWithLabel:NSLocalizedString(@"Cancel", nil) action:^{
            
        }];
        
        RIButtonItem* yesButton = [RIButtonItem itemWithLabel:NSLocalizedString(@"Yes", nil) action:^{
            [[MLXMPPManager sharedInstance] removeContact:contact];
            
            [_contactsTable beginUpdates];
            [_contacts removeObjectAtIndex:indexPath.row];
            
            [_contactsTable deleteRowsAtIndexPaths:@[indexPath]
                                  withRowAnimation:UITableViewRowAnimationAutomatic];
            [_contactsTable endUpdates];
        }];
        
        UIActionSheet* sheet =[[UIActionSheet alloc] initWithTitle:messageString cancelButtonItem:cancelButton destructiveButtonItem:yesButton otherButtonItems: nil];
        [sheet showFromTabBar:self.tabBarController.tabBar];
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    ContactDetails* detailVC =nil;
    if(indexPath.section==konlineSection)
        detailVC= [[ContactDetails alloc]  initWithContact:[_contacts objectAtIndex:indexPath.row] ];
    else
        detailVC=[[ContactDetails alloc]  initWithContact:[_offlineContacts objectAtIndex:indexPath.row] ];
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        MLChatCell* cell = (MLChatCell*)[tableView cellForRowAtIndexPath:indexPath];
        
        _popOverController = [[UIPopoverController alloc] initWithContentViewController:detailVC];
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
    if((indexPath.section==konlineSection))
        
    {
        
        row=[_contacts objectAtIndex:indexPath.row];
        
    }
    else if (indexPath.section==kofflineSection)
    {
        row= [_offlineContacts objectAtIndex:indexPath.row];
    }
    
    [row setObject:[NSNumber numberWithInt:0] forKey:@"count"];
    
    //make chat view
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
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
    }
    
    chatViewController* chatVC = [[chatViewController alloc] initWithContact:row ];
    [self.currentNavController pushViewController:chatVC animated:YES];
    
    [tableView beginUpdates];
    [tableView reloadRowsAtIndexPaths:@[indexPath]
                     withRowAnimation:UITableViewRowAnimationNone];
    [tableView endUpdates];
    
    _lastSelectedUser=row;
    
    
}



@end
