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

     [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    
    
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
}

-(void) viewDidAppear:(BOOL)animated
{
    _lastSelectedUser=nil;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark updating info display
-(void) showConnecting:(NSDictionary*) info
{
    dispatch_sync(dispatch_get_main_queue(),
                  ^{
                      [ _infoCells insertObject:info atIndex:0];
                      [_contactsTable beginUpdates];
                      NSIndexPath *path1 = [NSIndexPath indexPathForRow:0 inSection:kinfoSection];
                      [_contactsTable insertRowsAtIndexPaths:@[path1]
                                            withRowAnimation:UITableViewRowAnimationAutomatic];
                      [_contactsTable endUpdates];
                      
                      
                      dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
                      if([[info objectForKey:kinfoStatusKey] isEqualToString:@"Disconnected"])
                      {
                      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3ull * NSEC_PER_SEC), q_background,  ^{
                          [self hideConnecting:info];
                      });
                      }
                     
                  });
}

-(void) updateConnecting:(NSDictionary*) info
{
    dispatch_sync(dispatch_get_main_queue(),
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
    dispatch_sync(dispatch_get_main_queue(),
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
-(void) addUser:(NSDictionary*) user
{
      //mutex to prevent others from modifying contacts at the same time
    dispatch_sync(dispatch_get_main_queue(),
                  ^{
    //check if already there
    int pos=-1;
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
             [_contactsTable endUpdates];
                     
        
    }else
    {
        debug_NSLog(@"user %@ already in list",[user objectForKey:kusernameKey]);
        [[_contacts objectAtIndex:pos] setObject:[user objectForKey:kstateKey] forKey:kstateKey];
        [[_contacts objectAtIndex:pos] setObject:[user objectForKey:kstatusKey] forKey:kstatusKey];
        
        [_contactsTable beginUpdates];
        NSIndexPath *path1 = [NSIndexPath indexPathForRow:pos inSection:konlineSection];
        [_contactsTable reloadRowsAtIndexPaths:@[path1]
                              withRowAnimation:UITableViewRowAnimationNone];
        [_contactsTable endUpdates];
    }
      });
    
}

-(void) removeUser:(NSDictionary*) user
{
    //mutex to prevent others from modifying contacts at the same time
    dispatch_sync(dispatch_get_main_queue(),
                  ^{
                      //check if  there
                      int pos=-1;
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
                     
                      //not there
                      if(pos>=0)
                      {
                          [_contacts removeObjectAtIndex:pos];
                          debug_NSLog(@"removing %@ at pos %d", [user objectForKey:kusernameKey], pos);
                          [_contactsTable beginUpdates];
                          NSIndexPath *path1 = [NSIndexPath indexPathForRow:pos inSection:konlineSection];
                          [_contactsTable deleteRowsAtIndexPaths:@[path1]
                                                withRowAnimation:UITableViewRowAnimationAutomatic];
                          [_contactsTable endUpdates];
                      }
                      
                  });
    
                      
    
}

-(void) clearContactsForAccount: (NSString*) accountNo
{
    //mutex to prevent others from modifying contacts at the same time
    dispatch_sync(dispatch_get_main_queue(),
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

-(void) handleNewMessage:(NSNotification *)notification
{
    debug_NSLog(@"chat view got new message notice %@", notification.userInfo);

    if([[_lastSelectedUser objectForKey:@"buddy_name"] caseInsensitiveCompare:[notification.userInfo objectForKey:@"from"] ]==NSOrderedSame &&
       [[_lastSelectedUser objectForKey:@"account_id" ]  integerValue]==[[notification.userInfo objectForKey:kaccountNoKey] integerValue] )
    {
        debug_NSLog(@"user currently in chat. not updating");
        return; 
    }
    
    dispatch_sync(dispatch_get_main_queue(),
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
    return 3;
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
    
    NSDictionary* row = [_contacts objectAtIndex:indexPath.row];
    cell.textLabel.text=[row objectForKey:@"full_name"];
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
    
    cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;

    cell.accountNo=[[row objectForKey:@"account_id"] integerValue];
    cell.username=[row objectForKey:@"buddy_name"] ;
    
    //cell.count=[[row objectForKey:@"count"] integerValue];
    NSString* accountNo=[NSString stringWithFormat:@"%d", cell.accountNo];
  cell.count=  [[DataLayer sharedInstance] countUserUnreadMessages:cell.username forAccount:accountNo];


    return cell; 
}

#pragma mark tableview delegate
-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
   [tableView deselectRowAtIndexPath:indexPath animated:NO];
    
    if((indexPath.section==konlineSection) ||
       (indexPath.section==kofflineSection) )
    {
        
        [[_contacts objectAtIndex:indexPath.row] setObject:[NSNumber numberWithInt:0] forKey:@"count"];
        
        //make chat view
        chatViewController* chatVC = [[chatViewController alloc] initWithContact:[_contacts objectAtIndex:indexPath.row] ];
        [self.navigationController pushViewController:chatVC animated:YES];
        
        [tableView beginUpdates];
        [tableView reloadRowsAtIndexPaths:@[indexPath]
                              withRowAnimation:UITableViewRowAnimationNone];
        [tableView endUpdates];
        
        _lastSelectedUser=[_contacts objectAtIndex:indexPath.row];
    }
    
    
}


@end
