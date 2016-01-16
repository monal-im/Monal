//
//  MLContactsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLContactsViewController.h"
#import "MLContactsCell.h"
#import "MLConstants.h"
#import "DataLayer.h"
#import "MLXMPPManager.h"
#import "DDLog.h"
#import "MLMainWindow.h"
#import "MLImageManager.h"

#define kinfoSection 0
#define konlineSection 1
#define kofflineSection 2

#define kContactTab 0
#define kActiveTab 1

@interface MLContactsViewController ()

@property (nonatomic, strong) NSMutableArray* infoCells;
@property (nonatomic, strong) NSMutableArray* contacts;
@property (nonatomic, strong) NSMutableArray* activeChat;
@property (nonatomic, assign) NSInteger currentSegment;

@property (nonatomic, strong) NSMutableArray* searchResults;
@property (nonatomic, strong) NSMutableArray* offlineContacts;

@end

@implementation MLContactsViewController

static const int ddLogLevel = LOG_LEVEL_INFO;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.contactsTable.selectionHighlightStyle =NSTableViewSelectionHighlightStyleSourceList;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshDisplay) name:kMonalWindowVisible object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshDisplay) name:kMonalAccountStatusChanged object:nil];
    
    self.contacts=[[NSMutableArray alloc] init] ;
    self.offlineContacts=[[NSMutableArray alloc] init] ;
    self.infoCells=[[NSMutableArray alloc] init] ;
        
    [MLXMPPManager sharedInstance].contactVC=self;
    self.currentSegment= kContactTab;
    
}

-(void) viewDidAppear
{
    [super viewDidAppear];
    
    if([self.parentViewController isKindOfClass:[NSSplitViewController class]])
    {
        NSArray *splitViewItems = ((NSSplitViewController *) self.parentViewController ).splitViewItems;
        if([splitViewItems count]>1)
        {
            NSSplitViewItem *otherItem = [splitViewItems objectAtIndex:1];
            self.chatViewController = (MLChatViewController *)otherItem.viewController;
        }
    }
    
    MLMainWindow *window =(MLMainWindow *)self.view.window.windowController;
    window.contactSearchField.delegate=self;
    window.contactsViewController= self;
    
}


-(void) viewWillAppear
{
    [super viewWillAppear];
    
    if(self.activeChat)
    {
        [self showActiveChat:YES];
    }
    else {
        [self.contactsTable reloadData];
    }
    
    [self updateAppBadge];
    [self highlightCellForCurrentContact];
  
}


-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


-(void) refreshDisplay
{
    dispatch_async(dispatch_get_main_queue(), ^{
         [self viewWillAppear];
    });
   
}

#pragma mark - update tabs

-(void)toggleContactsTab
{
    self.segmentedControl.selectedSegment=kContactTab;
    [self segmentDidChange:self];
}

-(void)toggleActiveChatTab
{
    self.segmentedControl.selectedSegment=kActiveTab;
    [self segmentDidChange:self];
}


-(IBAction)segmentDidChange:(id)sender
{
    if(self.segmentedControl.selectedSegment!=self.currentSegment)
    {
        self.currentSegment=self.segmentedControl.selectedSegment;
        if(self.segmentedControl.selectedSegment==kActiveTab) {
            [self showActiveChat:YES];
        }
        else {
            [self showActiveChat: NO];
        }
        
        [self highlightCellForCurrentContact];
    }
}


#pragma mark - other UI

-(void) showActiveChat:(BOOL) shouldShow
{
    if (shouldShow) {
        self.activeChat= [[DataLayer sharedInstance] activeBuddies];
    }
    else {
        self.activeChat=nil;
    }
    
    [self.contactsTable reloadData];
}

-(IBAction)deleteItem:(id)sender
{
    
    NSAlert *userDelAlert = [[NSAlert alloc] init];
    userDelAlert.messageText =[NSString stringWithFormat:@"Are you sure you want to remove this contact?"];
    userDelAlert.alertStyle=NSInformationalAlertStyle;
    [userDelAlert addButtonWithTitle:@"No"];
    [userDelAlert addButtonWithTitle:@"Yes"];
    
    if(self.searchResults)
    {
        if(self.contactsTable.selectedRow <self.searchResults.count) {
            NSDictionary *contact =[self.searchResults objectAtIndex:self.contactsTable.selectedRow];
            
            [userDelAlert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
                
                if(returnCode==1001) //YES
                {
                    [[MLXMPPManager sharedInstance] removeContact:contact];
                    [self.searchResults removeObjectAtIndex:self.contactsTable.selectedRow];
                    
                    [self.contactsTable reloadData];
                    
                    NSMutableDictionary *mContact=[contact mutableCopy];
                    [mContact setObject:[mContact objectForKey:kAccountID] forKey:kaccountNoKey];
                    [mContact setObject:[mContact objectForKey:kContactName] forKey:kusernameKey];
                    
                    //remove from contacts as well
                    NSInteger pos = [self positionOfOnlineContact:mContact];
                    if(pos>=0)
                    {
                        [self.contacts removeObjectAtIndex:pos];
                    }
                    else
                    {
                        pos = [self positionOfOfflineContact:mContact];
                        if(pos>=0)
                        {
                            [self.offlineContacts removeObjectAtIndex:pos];
                        }
                    }
                }
                else
                {
                    //do nothing
                }
                
            }];
        }
    }
    else if(self.activeChat)
    {
        if(self.contactsTable.selectedRow <self.activeChat.count) {
            NSDictionary *contact =[self.activeChat objectAtIndex:self.contactsTable.selectedRow];
            
            [ [DataLayer sharedInstance] removeActiveBuddy:[contact objectForKey:kContactName] forAccount:[contact objectForKey:kAccountID]];
            self.activeChat=[[DataLayer sharedInstance] activeBuddies];
            [self.contactsTable reloadData];
        }
    }
    else  {
        if(self.contactsTable.selectedRow <self.contacts.count) {
            NSDictionary *contact =[self.contacts objectAtIndex:self.contactsTable.selectedRow];
            [userDelAlert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
                
                if(returnCode==1001) //YES
                {
                    [[MLXMPPManager sharedInstance] removeContact:contact];
                    [self.contacts removeObjectAtIndex:self.contactsTable.selectedRow];
                    
                    [self.contactsTable reloadData];
                }
                else
                {
                    //do nothing
                }
                
                
            }];
        }
    }
    
}

-(IBAction)startFind:(id)sender
{
    MLMainWindow *windowController =(MLMainWindow *)self.view.window.windowController;
    [self.view.window makeFirstResponder:windowController.contactSearchField];
}

-(void) highlightCellForCurrentContact
{
    if(self.chatViewController.contactDic)
    {
        NSArray *sourceArray;
        if(self.currentSegment==kActiveTab)
        {
            sourceArray= self.activeChat;
            
        } else  {
            sourceArray= self.contacts;
        }
        
        NSInteger pos=0;
        for (NSDictionary *row in sourceArray)
        {
            if([[row objectForKey:kContactName] caseInsensitiveCompare:[self.chatViewController.contactDic objectForKey:kContactName] ]==NSOrderedSame &&
               [[row objectForKey:kAccountID]  integerValue]==[[self.chatViewController.contactDic objectForKey:kAccountID] integerValue] )
            {
                NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:pos];
                [self.contactsTable selectRowIndexes:indexSet byExtendingSelection:NO];
                break;
            }
            pos++;
        }
        
    }
}

-(void) showConversationForContact:(NSDictionary *) user
{
    NSInteger counter=0;
    NSInteger pos=-1;
    NSDictionary *selectedRow;
    
    NSArray *currentTableData= self.contacts;
    if(self.activeChat)
    {
        currentTableData=self.activeChat;
    }
    
    for(NSDictionary* row in currentTableData)
    {
        if([[row objectForKey:kContactName] caseInsensitiveCompare:[user objectForKey:@"actuallyfrom"] ]==NSOrderedSame &&
           [[row objectForKey:kAccountID]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
        {
            pos= counter;
            selectedRow=row;
            [self.contactsTable scrollRowToVisible:pos];
            break;
        }
        counter++;
    }
    
    
    
    if(pos>=0)
    {
        //ensures that it isdefintiely set 
        [self.chatViewController showConversationForContact:selectedRow];
        
        NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:pos];
        [self.contactsTable selectRowIndexes:indexSet byExtendingSelection:NO];
    }
}



#pragma mark - updating user display in table

-(NSInteger) positionOfOnlineContact:(NSDictionary *) user
{
    NSInteger pos=0;
    for(NSDictionary* row in self.contacts)
    {
        if([[row objectForKey:kContactName] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
           [[row objectForKey:kAccountID]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
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
        if([[row objectForKey:kContactName] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
           [[row objectForKey:kAccountID]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
        {
            
            return pos;
        }
        pos++;
    }
    
    return  -1;
    
}

-(void) addOnlineUser:(NSDictionary*) user
{
    //insert into tableview
    // for now just online
    [[DataLayer sharedInstance] contactForUsername:[user objectForKey:kusernameKey] forAccount:[user objectForKey:kaccountNoKey] withCompletion:^(NSArray * contactRow) {
        
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           //check if already there
                           NSInteger pos=-1;
                           NSInteger offlinepos=-1;
                           pos = [self positionOfOnlineContact:user];
                           
                           
                           //offlinepos= [self positionOfOfflineContact:user];
                           
                           //not there
                           if(pos<0)
                           {
                    
                               if(!(contactRow.count>=1))
                               {
                                   DDLogError(@"ERROR:could not find contact row");
                                   return;
                               }
                               
                               NSInteger onlinepos= [self positionOfOnlineContact:user];
                               if(onlinepos>=0)
                               {
                                   
                                   DDLogVerbose(@"user %@ already in list",[user objectForKey:kusernameKey]);
                                   
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
                               NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:kContactName  ascending:YES];
                               NSArray* sortArray =[NSArray arrayWithObjects:descriptor,nil];
                               [_contacts sortUsingDescriptors:sortArray];
                               
                               //find where it is
                               int pos=0;
                               int counter=0;
                               for(NSDictionary* row in _contacts)
                               {
                                   if([[row objectForKey:kContactName] caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
                                      [[row objectForKey:kAccountID]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
                                   {
                                       pos=counter;
                                       break;
                                   }
                                   counter++;
                               }
                               DDLogVerbose(@"sorted contacts %@", _contacts);
                               
                               DDLogVerbose(@"inserting %@ at pos %d", [_contacts objectAtIndex:pos], pos);
                               
                               if(self.searchResults || self.activeChat) {
                                   [self refreshDisplay];
                               }
                               else {
                                   [_contactsTable beginUpdates];
                                   NSIndexSet *indexSet =[[NSIndexSet alloc] initWithIndex:pos] ;
                                   [self.contactsTable insertRowsAtIndexes:indexSet withAnimation:NSTableViewAnimationEffectFade];
                                   
                                   //                                                  if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                                   //                                                  {
                                   //                                                      if(offlinepos>=0 && offlinepos<[_offlineContacts count])
                                   //                                                      {
                                   //                                                          NSIndexPath *path2 = [NSIndexPath indexPathForRow:offlinepos inSection:kofflineSection];
                                   //                                                          [self.contactsTable deleteRowsAtIndexPaths:@[path2]
                                   //                                                                                withRowAnimation:UITableViewRowAnimationFade];
                                   //                                                      }
                                   //                                                  }
                                   [self.contactsTable endUpdates];
                               }
                           }else
                           {
                               DDLogVerbose(@"user %@ already in list %@",[user objectForKey:kusernameKey], self.contacts);
                               if(pos<self.contacts.count) {
                                   if([user objectForKey:kstateKey])
                                       [[_contacts objectAtIndex:pos] setObject:[user objectForKey:kstateKey] forKey:kstateKey];
                                   if([user objectForKey:kstatusKey])
                                       [[_contacts objectAtIndex:pos] setObject:[user objectForKey:kstatusKey] forKey:kstatusKey];
                                   
                                   if([user objectForKey:kfullNameKey])
                                       [[_contacts objectAtIndex:pos] setObject:[user objectForKey:kfullNameKey] forKey:@"full_name"];
                                   
                                   if(self.searchResults || self.activeChat){
                                      [self refreshDisplay];
                                   }
                                   else  {
                                       
                                       [self.contactsTable beginUpdates];
                                       
                                       NSIndexSet *indexSet =[[NSIndexSet alloc] initWithIndex:pos] ;
                                       NSIndexSet *columnIndexSet =[[NSIndexSet alloc] initWithIndex:0] ;
                                       [self.contactsTable reloadDataForRowIndexes:indexSet columnIndexes:columnIndexSet];
                                       [self.contactsTable endUpdates];
                                   }
                               }
                           }
                           
                           
                       });
        
        
    }];
    
    
}

-(void) removeOnlineUser:(NSDictionary*) user
{
    
    [[DataLayer sharedInstance] contactForUsername:[user objectForKey:kusernameKey] forAccount:[user objectForKey:kaccountNoKey] withCompletion:^(NSArray* contactRow) {
        
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           
                           //check if  there
                           NSInteger pos=-1;
                           NSInteger counter=0;
                           NSInteger offlinepos=-1;
                           pos=[self positionOfOnlineContact:user];
                           
                           
                           if((contactRow.count<1))
                           {
                               DDLogError(@"ERROR:could not find contact row");
                               return;
                           }
                           
                           if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                           {
                               
                               counter=0;
                               offlinepos= [self positionOfOfflineContact:user];
                               
                               //in contacts but not in offline.. (not in roster this shouldnt happen)
                               if((offlinepos==-1) &&(pos>=0))
                               {
                                   NSMutableDictionary* row= [contactRow objectAtIndex:0] ;
                                   [_offlineContacts insertObject:row atIndex:0];
                                   
                                   //sort
                                   NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:kContactName  ascending:YES];
                                   NSArray* sortArray =[NSArray arrayWithObjects:descriptor,nil];
                                   [_offlineContacts sortUsingDescriptors:sortArray];
                                   
                                   //find where it is
                                   
                                   counter=0;
                                   offlinepos= [self positionOfOfflineContact:user];
                                   DDLogVerbose(@"sorted contacts %@", _offlineContacts);
                               }
                           }
                           
                           //not there
                           if(pos>=0)
                           {
                               if(self.searchResults || self.activeChat) {
                                   return;
                                
                               } else {
                                   [_contacts removeObjectAtIndex:pos];
                                   
                                   
                                   DDLogVerbose(@"removing %@ at pos %d", [user objectForKey:kusernameKey], pos);
                                   [_contactsTable beginUpdates];
                                   NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:pos];
                                   [_contactsTable removeRowsAtIndexes:indexSet withAnimation:NSTableViewAnimationEffectFade];
                                   
                                   //                                                  if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"] && offlinepos>-1)
                                   //                                                  {
                                   //                                                      NSIndexPath *path2 = [NSIndexPath indexPathForRow:offlinepos inSection:kofflineSection];
                                   //                                                      DDLogVerbose(@"inserting offline at %d", offlinepos);
                                   //                                                      [_contactsTable insertRowsAtIndexPaths:@[path2]
                                   //                                                                            withRowAnimation:UITableViewRowAnimationFade];
                                   //                                                  }
                                   
                                   [_contactsTable endUpdates];
                               }
                           }
                           
                       });
    }];
    
}

-(void) showConnecting:(NSDictionary*) info{
    
}
-(void) updateConnecting:(NSDictionary*) info
{
    
}
-(void) hideConnecting:(NSDictionary*) info{
    
}

-(void) clearContactsForAccount: (NSString*) accountNo
{
    
    //mutex to prevent others from modifying contacts at the same time
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       NSMutableArray* indexPaths =[[NSMutableArray alloc] init];
                       NSMutableIndexSet* indexSet = [[NSMutableIndexSet alloc] init];
                       
                       NSInteger counter=0;
                       for(NSDictionary* row in _contacts)
                       {
                           if([[row objectForKey:@"account_id"]  integerValue]==[accountNo integerValue] )
                           {
                               DDLogVerbose(@"removing  pos %d", counter);
                               [indexSet addIndex:counter];
                               
                           }
                           counter++;
                       }
                       
                       [_contacts removeObjectsAtIndexes:indexSet];
                       
                       if(self.searchResults || self.activeChat) {
                           return;
                           
                       } else {
                           [_contactsTable beginUpdates];
                           [_contactsTable removeRowsAtIndexes:indexSet withAnimation:NSTableViewAnimationEffectFade];
                           [_contactsTable endUpdates];
                       }
                       
                   });
    
}


-(void) showAuthRequestForContact:(NSString *) contactName withCompletion: (void (^)(BOOL))completion
{
    NSAlert *userAddAlert = [[NSAlert alloc] init];
    userAddAlert.messageText =[NSString stringWithFormat:@"%@ wants to add you as a contact", contactName];
    userAddAlert.alertStyle=NSInformationalAlertStyle;
    [userAddAlert addButtonWithTitle:@"Do Not Approve"];
    [userAddAlert addButtonWithTitle:@"Ask me later"];
    [userAddAlert addButtonWithTitle:@"Approve"];

    
    [userAddAlert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
       
        BOOL allowed=NO;
        
        if(returnCode ==1002) {
            allowed=YES;
        }
        
        if(completion)
        {
            completion(allowed);
        }
    }];
    
}


#pragma mark - notification handling

-(void) handleNewMessage:(NSNotification *)notification
{
  
    DDLogVerbose(@"chat view got new message notice %@", notification.userInfo);
 
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                    NSInteger pos=-1;
                       
                       //if current converstion, mark as read if window is visible
                       NSDictionary *contactRow = nil;
                       
                       NSArray *activeArray=self.contacts;
                       if(self.currentSegment==kActiveTab)
                       {
                           //activeArray= self.activeChat;
                           //add 0.2 delay to allow DB to write since this is called at the same time as db write notification
                           dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.2 * NSEC_PER_SEC), dispatch_get_main_queue(),  ^{
                               [self showActiveChat:YES];
                               [self highlightCellForCurrentContact];
                           });
                           
                           return;
                       }
                    
                       if((self.view.window.occlusionState & NSWindowOcclusionStateVisible)) {
                               if(self.contactsTable.selectedRow <activeArray.count) {
                                   contactRow=[activeArray objectAtIndex:self.contactsTable.selectedRow];
                               }
                       }
                       
                       if([[contactRow objectForKey:kContactName] caseInsensitiveCompare:[notification.userInfo objectForKey:@"from"] ]==NSOrderedSame &&
                          [[contactRow objectForKey:kAccountID]  integerValue]==[[notification.userInfo objectForKey:kaccountNoKey] integerValue] ) {
                           
                           if((self.view.window.occlusionState & NSWindowOcclusionStateVisible)) {
                               [[DataLayer sharedInstance] markAsReadBuddy:[contactRow objectForKey:kContactName] forAccount:[contactRow objectForKey:kAccountID]];
                               [self updateAppBadge];
                           }
                           
                           pos=self.contactsTable.selectedRow;
                           
                       }
                       else  {
     
                           int counter=0;
                           for(NSDictionary* row in activeArray)
                           {
                               if([[row objectForKey:kContactName] caseInsensitiveCompare:[notification.userInfo objectForKey:@"from"] ]==NSOrderedSame &&
                                  [[row objectForKey:kAccountID]  integerValue]==[[notification.userInfo objectForKey:kaccountNoKey] integerValue] )
                               {
                                   pos=counter;
                                   break;
                               }
                               counter++;
                           }
                       }
                       
                       if(pos>=0)
                       {
                            if(self.searchResults) return;
                           if(pos<self.contactsTable.numberOfRows) {
                               [self.contactsTable beginUpdates];
                               NSIndexSet *indexSet =[[NSIndexSet alloc] initWithIndex:pos] ;
                               NSIndexSet *columnIndexSet =[[NSIndexSet alloc] initWithIndex:0] ;
                               [self.contactsTable reloadDataForRowIndexes:indexSet columnIndexes:columnIndexSet];
                               [self.contactsTable endUpdates];
                           }
                       }
                   });
    
}

#pragma mark - table view datasource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    if(self.searchResults) {
        return self.searchResults.count;
    }
    else {
        if(self.currentSegment==kActiveTab)
        {
            return [self.activeChat count];
        } else  {
            return [self.contacts count];
        }
    }
}

#pragma mark - table view delegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn  row:(NSInteger)row
{
    
    NSDictionary *contactRow;
    if(self.searchResults)
    {
        contactRow = [self.searchResults objectAtIndex:row];
    } else  {
        if(self.currentSegment==kActiveTab)
        {
            contactRow=[self.activeChat objectAtIndex:row];
        }
        else  {
            contactRow=[self.contacts objectAtIndex:row];
        }
    }
    
    MLContactsCell *cell = [tableView makeViewWithIdentifier:@"OnlineUser" owner:self];
    cell.name.backgroundColor =[NSColor clearColor];
    cell.status.backgroundColor= [NSColor clearColor];
    
    cell.name.stringValue = [contactRow objectForKey:kFullName];
    cell.accountNo= [[contactRow objectForKey:kAccountID] integerValue];
    cell.username =[contactRow objectForKey:kContactName] ;
    
    
    NSString *statusText = [contactRow objectForKey:@"status"];
    if( [statusText isEqualToString:@"(null)"])  {
        statusText = @"";
    }
    cell.status.stringValue =statusText;
    
    NSString *state= [[contactRow objectForKey:@"state"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if(([state isEqualToString:@"away"]) ||
       ([state isEqualToString:@"dnd"])||
       ([state isEqualToString:@"xa"])
       )
    {
        cell.state=kStatusAway;
    }
    else if([state isEqualToString:@"offline"]) {
        cell.state=kStatusOffline;
    }
    else if([state isEqualToString:@"(null)"] || [state isEqualToString:@""]) {
        cell.state=kStatusOnline;
    }
    
    [cell setOrb];

    NSString* accountNo=[NSString stringWithFormat:@"%ld", (long)cell.accountNo];
    
    cell.icon.image= [[MLImageManager sharedInstance] getIconForContact:cell.username andAccount:accountNo];
  
    
    [[DataLayer sharedInstance] countUserUnreadMessages:cell.username forAccount:accountNo withCompletion:^(NSNumber * result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [cell setUnreadCount:[result integerValue]];
        });
    }];

    
    return cell;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    return 60.0f;
}


- (void)tableViewSelectionDidChange:(NSNotification *)notification;
{
    if(self.searchResults && self.contactsTable.selectedRow<self.searchResults.count)
    {
        NSDictionary *contactRow = [self.searchResults objectAtIndex:self.contactsTable.selectedRow];
        [self.chatViewController showConversationForContact:contactRow];
     
           if((self.view.window.occlusionState & NSWindowOcclusionStateVisible)) {
            [[DataLayer sharedInstance] markAsReadBuddy:[contactRow objectForKey:kContactName] forAccount:[contactRow objectForKey:kAccountID]];
            [self updateAppBadge];
        }
        
        [self.contactsTable beginUpdates];
        NSIndexSet *indexSet =[[NSIndexSet alloc] initWithIndex:self.contactsTable.selectedRow] ;
        NSIndexSet *columnIndexSet =[[NSIndexSet alloc] initWithIndex:0] ;
        [self.contactsTable reloadDataForRowIndexes:indexSet columnIndexes:columnIndexSet];
        [self.contactsTable endUpdates];
    }
    else
        if(self.currentSegment==kActiveTab)
        {
            if(self.contactsTable.selectedRow<self.activeChat.count) {
                NSDictionary *contactRow = [self.activeChat objectAtIndex:self.contactsTable.selectedRow];
                [self.chatViewController showConversationForContact:contactRow];
                
                 if((self.view.window.occlusionState & NSWindowOcclusionStateVisible)) {
                    [[DataLayer sharedInstance] markAsReadBuddy:[contactRow objectForKey:kContactName] forAccount:[contactRow objectForKey:kAccountID]];
                    [self updateAppBadge];
                }
                
                [self.contactsTable beginUpdates];
                NSIndexSet *indexSet =[[NSIndexSet alloc] initWithIndex:self.contactsTable.selectedRow] ;
                NSIndexSet *columnIndexSet =[[NSIndexSet alloc] initWithIndex:0] ;
                [self.contactsTable reloadDataForRowIndexes:indexSet columnIndexes:columnIndexSet];
                [self.contactsTable endUpdates];
            }
        }
        else  {
            if(self.contactsTable.selectedRow<self.contacts.count) {
                NSDictionary *contactRow = [self.contacts objectAtIndex:self.contactsTable.selectedRow];
                [self.chatViewController showConversationForContact:contactRow];
                
                if((self.view.window.occlusionState & NSWindowOcclusionStateVisible)) {
                    [[DataLayer sharedInstance] markAsReadBuddy:[contactRow objectForKey:kContactName] forAccount:[contactRow objectForKey:kAccountID]];
                    [self updateAppBadge];
                }
                
                [self.contactsTable beginUpdates];
                NSIndexSet *indexSet =[[NSIndexSet alloc] initWithIndex:self.contactsTable.selectedRow] ;
                NSIndexSet *columnIndexSet =[[NSIndexSet alloc] initWithIndex:0] ;
                [self.contactsTable reloadDataForRowIndexes:indexSet columnIndexes:columnIndexSet];
                [self.contactsTable endUpdates];
                
            }
        }
}


-(void) updateAppBadge
{
    [[DataLayer sharedInstance] countUnreadMessagesWithCompletion:^(NSNumber * result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if([result integerValue]>0) {
                [[[NSApplication sharedApplication] dockTile] setBadgeLabel:[NSString stringWithFormat:@"%@", result]];
            }
            else
            {
                [[[NSApplication sharedApplication] dockTile] setBadgeLabel:nil];
            }
        });
        
    }];
}


#pragma mark search field 

- (void)controlTextDidChange:(NSNotification *)aNotification
{
    NSSearchField *searchField = aNotification.object;

    if(searchField.stringValue.length>0) {
        self.searchResults=[[DataLayer sharedInstance] searchContactsWithString:searchField.stringValue];
    } else  {
        self.searchResults=nil;
    }
    [self.contactsTable reloadData];

}

- (void)controlTextDidBeginEditing:(NSNotification *)aNotification
{
    
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
  
}


@end
