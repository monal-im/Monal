//
//  MLContactsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLContactsViewController.h"
#import "MLContactsCell.h"
#import "monalxmppmac.h"

#import "MLMainWindow.h"
#import "MLImageManager.h"

#import "MLServerDetailsVC.h"
#import "MLCallScreen.h"
#import "MLMAMPref.h"

#import "MLKeyViewController.h"

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

@property (nonatomic, strong) NSMutableIndexSet *expanded;

@property (nonatomic, strong)  NSDateFormatter* destinationDateFormat;
@property (nonatomic, strong)  NSDateFormatter* sourceDateFormat;
@property (nonatomic, strong)  NSCalendar *gregorian;
@property (nonatomic, assign) NSInteger thisyear;
@property (nonatomic, assign) NSInteger thismonth;
@property (nonatomic, assign) NSInteger thisday;

@end

@implementation MLContactsViewController



- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.contactsTable.selectionHighlightStyle =NSTableViewSelectionHighlightStyleSourceList;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshDisplay) name:kMonalWindowVisible object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshDisplay) name:kMonalAccountStatusChanged object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshDisplay) name:kMonalRefreshContacts object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(presentChat:) name:kMonalPresentChat object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(addOnlineUser:) name: kMonalContactOnlineNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(removeOnlineUser:) name: kMonalContactOfflineNotice object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showCallRequest:) name:kMonalCallRequestNotice object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshContact:) name: kMonalContactRefresh object:nil];
    [self setupDateObjects];
    
    self.contacts=[[NSMutableArray alloc] init] ;
    self.offlineContacts=[[NSMutableArray alloc] init] ;
    self.infoCells=[[NSMutableArray alloc] init] ;
    
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

    [self.contactsTable expandItem:@"Online"];
    [self showSSLUpgradeSheet];

}


-(void) viewWillAppear
{
    [super viewWillAppear];
    
    if(self.activeChat)
    {
        [self showActiveChat:YES];
    }
    else {
        [self refreshOnlineContactsWithCompeltion:^(void) {
            [self refreshOfflineContactsWithCompeltion:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                   [self.contactsTable reloadData];
                });
            }];
        }];
    }
    
    [self updateAppBadge];
    [self highlightCellForCurrentContact];
}


-(void) refreshOnlineContactsWithCompeltion:(void (^)(void))completion
{
    if([[NSUserDefaults standardUserDefaults] boolForKey:@"SortContacts"]) //sort by status
    {
        [[DataLayer sharedInstance] onlineContactsSortedBy:@"Status" withCompeltion:^(NSMutableArray *results) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.contacts= results;
                if(completion) completion();
            });
        }];
    }
    else {
        [[DataLayer sharedInstance] onlineContactsSortedBy:@"Name" withCompeltion:^(NSMutableArray *results) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.contacts= results;
                 if(completion) completion();
            });
        }];
    }
}

-(void) refreshOfflineContactsWithCompeltion:(void (^)(void))completion
{
    if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
    {
        [[DataLayer sharedInstance] offlineContactsWithCompletion:^(NSMutableArray *results) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.offlineContacts= results;
                 if(completion) completion();
            });
        }];
        
    }
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
        if(self.currentSegment==kContactTab) {
            self.expanded =[[NSMutableIndexSet alloc] init];
            //get expanded groups
            NSInteger counter=0;
            
            while (counter < [self.contactsTable numberOfChildrenOfItem:nil])
            {
                NSString  *child= [self outlineView:self.contactsTable child:counter ofItem:nil];
                if([self.contactsTable isItemExpanded:child])
                {
                    [self.expanded addIndex:counter];
                }
                
                counter++;
            }
        }
        self.currentSegment=self.segmentedControl.selectedSegment;
        if(self.segmentedControl.selectedSegment==kActiveTab) {
            [self showActiveChat:YES];
        }
        else {
            [self showActiveChat: NO];
            NSInteger counter=0;
            
            while (counter < [self.contactsTable numberOfChildrenOfItem:nil])
            {
                NSString  *child= [self outlineView:self.contactsTable child:counter ofItem:nil];
                
                if([self.expanded containsIndex:counter])
                {
                    [self.contactsTable expandItem:child];
                }
                
                counter++;
            }
        }
        
    }
}


#pragma mark - other UI

-(void) showActiveChat:(BOOL) shouldShow
{
    if (shouldShow) {
        self.contactsTable.accessibilityLabel=@"Active Chats";
        [[DataLayer sharedInstance] activeContactsWithCompletion:^(NSMutableArray *cleanActive) {
            [[MLXMPPManager sharedInstance] cleanArrayOfConnectedAccounts:cleanActive];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.activeChat= cleanActive;
                [self.contactsTable reloadData];
                [self highlightCellForCurrentContact];
            });
        }];
    }
    else {
        self.activeChat=nil;
        [self.contactsTable reloadData];
        self.contactsTable.accessibilityLabel=@"Contacts";
        
        [self highlightCellForCurrentContact];
    }
    
    [self updateAccessabilityCount];
}

-(void) updateAccessabilityCount
{
    [[DataLayer sharedInstance] countUnreadMessagesWithCompletion:^(NSNumber * result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *currentLabel =self.contactsTable.accessibilityLabel;
            
            NSString *formatted= [NSString stringWithFormat:@"%@ (%@ unread)",currentLabel, result];
            self.contactsTable.accessibilityLabel=formatted;
            
        });
        
   
    }];
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
            
            [[DataLayer sharedInstance] removeActiveBuddy:[contact objectForKey:kContactName] forAccount:[contact objectForKey:kAccountID]];

            [[DataLayer sharedInstance] activeContactsWithCompletion:^(NSMutableArray *cleanActive) {
                [[MLXMPPManager sharedInstance] cleanArrayOfConnectedAccounts:cleanActive];
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.activeChat= cleanActive;
                    [self.contactsTable reloadData];
                });
            }];
            
        }
    }
    else  {
        id item =[self.contactsTable itemAtRow:self.contactsTable.selectedRow];
        
        if([item isKindOfClass:[NSDictionary class]]) {
            NSDictionary *contact =(NSDictionary *) item;
            
            BOOL isMUC= [[DataLayer sharedInstance] isBuddyMuc:[contact objectForKey:@"buddy_name"]  forAccount:[contact objectForKey:@"account_id"]];
            
            
            if(isMUC){
                userDelAlert.messageText =[NSString stringWithFormat:@"Are you sure you want to leave this group chat?"];
            }
            
            [userDelAlert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
                
                if(returnCode==1001) //YES
                {
                    
                    if(isMUC) {
                         [[MLXMPPManager sharedInstance] leaveRoom:[contact objectForKey:@"buddy_name"] withNick:[contact objectForKey:@"muc_nick"] forAccountId: [NSString stringWithFormat:@"%@",[contact objectForKey:@"account_id"]]];
                    } else {
                        [[MLXMPPManager sharedInstance] removeContact:contact];
                    }
                 
                    if([self.contacts containsObject:contact]){
                        [self.contacts removeObject:contact];
                    } else  {
                        [self.offlineContacts removeObject:contact];
                    }
                    
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

-(void) toggleMute:(NSDictionary *)contact
{
    [[DataLayer sharedInstance] isMutedJid:[contact objectForKey:kContactName] withCompletion:^(BOOL muted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if(muted) {
                [[DataLayer sharedInstance] unMuteJid:[contact objectForKey:kContactName]];
            }
            else {
                [[DataLayer sharedInstance] muteJid:[contact objectForKey:kContactName]];
            }
            NSDictionary *user = @{kusernameKey:[contact objectForKey:kContactName],
                                   kaccountNoKey:[contact objectForKey:kAccountID],
                                   @"force":@YES
                                   };
            [self refreshRowWithUser:user];
        });
    }];
}

-(IBAction)muteItem:(id)sender
{
    if(self.searchResults)
    {
        if(self.contactsTable.selectedRow <self.searchResults.count) {
            NSDictionary *contact =[self.searchResults objectAtIndex:self.contactsTable.selectedRow];
            [[DataLayer sharedInstance] isMutedJid:[contact objectForKey:kContactName] withCompletion:^(BOOL muted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if(muted) {
                        [[DataLayer sharedInstance] unMuteJid:[contact objectForKey:kContactName]];
                    }
                    else {
                        [[DataLayer sharedInstance] muteJid:[contact objectForKey:kContactName]];
                    }
                    [self.contactsTable reloadData];
                });
            }];
        }
    }
    else if(self.activeChat)
    {
        if(self.contactsTable.selectedRow <self.activeChat.count) {
            NSDictionary *contact =[self.activeChat objectAtIndex:self.contactsTable.selectedRow];
            [self toggleMute:contact];
        }
    }
    else  {
        id item =[self.contactsTable itemAtRow:self.contactsTable.selectedRow];
        
        if([item isKindOfClass:[NSDictionary class]]) {
            NSDictionary *contact =(NSDictionary *) item;
            [self toggleMute:contact];
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
    if(self.currentSegment ==kActiveTab)
    {
        [self.activeChat enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop)
         {
             MLContact *row = (MLContact *) obj;
             if([row.contactJid caseInsensitiveCompare:self.chatViewController.contact.contactDisplayName] ==NSOrderedSame &&
                [row.accountId  integerValue]==[self.chatViewController.contact.accountId integerValue] )
             {
                 NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:idx];
                 [self.contactsTable selectRowIndexes:indexSet byExtendingSelection:NO];
                 *stop=YES;
             }
         }];
        return;
    }
    
    if(self.chatViewController.contact)
    {
        NSInteger offset=0;
       
        offset=1;//0 was root node and there are groups
        
        NSInteger group=0;
        while(group < [self.contactsTable numberOfChildrenOfItem:0])
        {
            
            NSDictionary *item = [self.contactsTable itemAtRow:group];
            if([self outlineView:self.contactsTable isItemExpandable:item])
            {
                NSInteger rowCounter =0;
                while(rowCounter<[self.contactsTable numberOfChildrenOfItem:item]) {
                    id childObject = [self outlineView:self.contactsTable child:rowCounter ofItem:item];
                    if([childObject isKindOfClass:[NSDictionary class]]) {
                        NSDictionary *row= (NSDictionary *) childObject;
                        
                        if([[row objectForKey:kContactName] caseInsensitiveCompare:self.chatViewController.contact.contactDisplayName] ==NSOrderedSame &&
                           [[row objectForKey:kAccountID]  integerValue]==[self.chatViewController.contact.accountId integerValue] )
                        {
                            NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:rowCounter+group+offset];
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [self.contactsTable selectRowIndexes:indexSet byExtendingSelection:NO];
                            });
                            
                            break;
                        }
                        
                    }
                    rowCounter++;
                }
                
            } else  {
                NSDictionary *row=item;
                  if([[row objectForKey:kContactName] caseInsensitiveCompare:self.chatViewController.contact.contactDisplayName] ==NSOrderedSame &&
                          [[row objectForKey:kAccountID]  integerValue]==[self.chatViewController.contact.accountId integerValue] )
                {
                    NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:group+offset];
                    [self.contactsTable selectRowIndexes:indexSet byExtendingSelection:NO];
                    break;
                }
            }
            group++;
        }
  
    }
}

-(void) showConversationForContact:(MLContact *) user
{
    NSInteger counter=0;
    NSInteger pos=-1;
    MLContact *selectedRow;
    
    NSArray *currentTableData= self.contacts;
    if(self.activeChat)
    {
        currentTableData=self.activeChat;
    }
    
    for(MLContact* row in currentTableData)
    {
        if([row.contactJid caseInsensitiveCompare:user.contactJid ]==NSOrderedSame &&
           [row.accountId  integerValue]==[user.accountId integerValue] )
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

-(void) refreshContact:(NSNotification *) notification
{
     NSDictionary* user = notification.userInfo;
    [self refreshRowWithUser:user];
    
    [self updateAccessabilityCount];
}


-(void) refreshRowWithUser:(NSDictionary *) user
{
    dispatch_async(dispatch_get_main_queue(), ^{
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

-(NSInteger) positionOfOnlineContact:(NSDictionary *) user
{
    NSInteger pos=0;
    for(MLContact* row in self.contacts)
    {
        if([row.contactJid caseInsensitiveCompare:[user objectForKey:kusernameKey] ]==NSOrderedSame &&
           [row.accountId  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
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


-(NSInteger) positionOfActiveContact:(NSDictionary *) user
{
    NSInteger pos=0;
    for(NSDictionary* row in self.activeChat)
    {
        if([[row objectForKey:kContactName] caseInsensitiveCompare:[user objectForKey:@"from"] ]==NSOrderedSame &&
           [[row objectForKey:kAccountID]  integerValue]==[[user objectForKey:kaccountNoKey] integerValue] )
        {
            return pos;
        }
        pos++;
    }
    
    return -1;
    
}



-(void)updateContactAt:(NSInteger) pos withInfo:(NSDictionary *) user
{
    NSMutableDictionary *contactrow =[_contacts objectAtIndex:pos];
    BOOL hasChange=NO;
    
    if([user objectForKey:kstateKey] && ![[user objectForKey:kstateKey] isEqualToString:[contactrow  objectForKey:kstateKey]] ) {
        [contactrow setObject:[user objectForKey:kstateKey] forKey:kstateKey];
        hasChange=YES;
    }
    if([user objectForKey:kstatusKey] && ![[user objectForKey:kstatusKey] isEqualToString:[contactrow  objectForKey:kstatusKey]] ) {
        [contactrow setObject:[user objectForKey:kstatusKey] forKey:kstatusKey];
        hasChange=YES;
    }
    
    if([user objectForKey:kfullNameKey] && ![[user objectForKey:kfullNameKey] isEqualToString:[contactrow  objectForKey:kfullNameKey]] &&
       [[user objectForKey:kfullNameKey] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length>0
       ) {
        [contactrow setObject:[user objectForKey:kfullNameKey] forKey:@"full_name"];
        hasChange=YES;
    }
    
    if([user objectForKey:@"force"]) hasChange=YES;
    
    if(hasChange) {
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
    } else  {
        
    }
}


-(void)updateOfflineContactAt:(NSInteger) pos withInfo:(NSDictionary *) user
{
    NSMutableDictionary *contactrow =[_offlineContacts objectAtIndex:pos];
    BOOL hasChange=NO;
    
    if([user objectForKey:kstateKey] && ![[user objectForKey:kstateKey] isEqualToString:[contactrow  objectForKey:kstateKey]] ) {
        [contactrow setObject:[user objectForKey:kstateKey] forKey:kstateKey];
        hasChange=YES;
    }
    if([user objectForKey:kstatusKey] && ![[user objectForKey:kstatusKey] isEqualToString:[contactrow  objectForKey:kstatusKey]] ) {
        [contactrow setObject:[user objectForKey:kstatusKey] forKey:kstatusKey];
        hasChange=YES;
    }
    
    if([user objectForKey:kfullNameKey] && ![[user objectForKey:kfullNameKey] isEqualToString:[contactrow  objectForKey:kfullNameKey]] &&
       [[user objectForKey:kfullNameKey] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length>0
       ) {
        [contactrow setObject:[user objectForKey:kfullNameKey] forKey:@"full_name"];
        hasChange=YES;
    }
    
    if(hasChange) {
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
    } else  {
        
    }
}

-(void) addOnlineUser:(NSNotification *) notification
{
    NSDictionary* user = notification.userInfo;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger initalPos=-1;
        initalPos=[self positionOfOnlineContact:user];
        if(initalPos>=0)
        {
            DDLogVerbose(@"user %@ already in list updating status and nothing else",[user objectForKey:kusernameKey]);
            [self updateContactAt:initalPos withInfo:user];
            return;
        }
        
        if(self.searchResults || self.activeChat) {
            [self refreshDisplay];
            return;
        }
            
            NSArray *oldContacts = [self.contacts copy];
            
            [self refreshOnlineContactsWithCompeltion:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    if(self.contacts.count - oldContacts.count!=1)
                    {
                        if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                        {
                            [self refreshOfflineContactsWithCompeltion:^{
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [self.contactsTable reloadData];
                                });
                            }];
                        } else  {
                            [self.contactsTable reloadData];
                        }
                    }
                    else  {
                        //check if already there
                        NSInteger pos=-1;
                        NSInteger offlinepos=-1;
                        //position of contact in new online
                        pos = [self positionOfOnlineContact:user];
                        if (pos>=0)
                        {
                            [self.contactsTable beginUpdates];
                            
                            NSIndexSet *indexSet =[[NSIndexSet alloc] initWithIndex:pos] ;
                            [self.contactsTable insertItemsAtIndexes:indexSet inParent:@"Online" withAnimation:NSTableViewAnimationEffectFade];
                            
                            //position of contact in old offline
                            if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                            {
                                offlinepos = [self positionOfOfflineContact:user];
                                if(offlinepos>=0 && offlinepos<[self->_offlineContacts count])
                                {
                                    NSIndexSet *offlineSet =[[NSIndexSet alloc] initWithIndex:offlinepos];
                                    [self.contactsTable removeItemsAtIndexes:offlineSet inParent:@"Offline" withAnimation:NSTableViewAnimationEffectFade];
                                }
                                [self refreshOfflineContactsWithCompeltion:nil];
                            }
                            [self.contactsTable endUpdates];
                        }
                        else {
                            DDLogError(@"ERROR:could not find contact row");
                            return;
                        }
                    }
                });
            }];
    });
}

-(void) removeOnlineUser:(NSNotification *) notification
{
    NSDictionary* user = notification.userInfo;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger initalPos=-1;
        initalPos=[self positionOfOnlineContact:user];
        if(initalPos>=0)
        {
            DDLogVerbose(@"user %@ already in list updating status and nothing else",[user objectForKey:kusernameKey]);
            [self updateContactAt:initalPos withInfo:user];
            
            
        }
        else  {
            if(self.searchResults || self.activeChat) {
                [self refreshDisplay];
                return;
            }
            
            NSArray *oldContacts = [self.contacts copy];
            //position of contact in old online
            NSInteger pos = [self positionOfOnlineContact:user];
            if (pos!=-1)
            {
                [self refreshOnlineContactsWithCompeltion:^{
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if( oldContacts.count - self.contacts.count !=1)
                        {
                            if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                            {
                                [self refreshOfflineContactsWithCompeltion:^{
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        [self.contactsTable reloadData];
                                    });
                                }];
                            } else  {
                                [self.contactsTable reloadData];
                            }
                        }
                        else  {
                           
                            [self.contactsTable beginUpdates];
                            
                            NSIndexSet *indexSet =[[NSIndexSet alloc] initWithIndex:pos] ;
                            [self.contactsTable removeItemsAtIndexes:indexSet inParent:@"Online" withAnimation:NSTableViewAnimationEffectFade];
                             [self.contactsTable endUpdates];
                            
                            //position of contact in old offline
                            if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                            {
                                [self refreshOfflineContactsWithCompeltion:^{
                                    NSInteger offlinepos = [self positionOfOfflineContact:user];
                                    if(offlinepos>=0 && offlinepos<[self->_offlineContacts count])
                                    {
                                        dispatch_async(dispatch_get_main_queue(), ^{
                                            [self.contactsTable beginUpdates];
                                            NSIndexSet *offlineSet =[[NSIndexSet alloc] initWithIndex:offlinepos];
                                            [self.contactsTable removeItemsAtIndexes:offlineSet inParent:@"Offline" withAnimation:NSTableViewAnimationEffectFade];
                                            [self.contactsTable endUpdates];
                                        });
                                    }
                                    }];
                                
                            }
                          
                        }
                    });
                }];
            }
            else {
                DDLogError(@"ERROR:could not find online contact row");
                return;
            }

        }
    });
}


-(void) clearContactsForAccount: (NSString*) accountNo
{
    
    //mutex to prevent others from modifying contacts at the same time
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       NSMutableIndexSet* indexSet = [[NSMutableIndexSet alloc] init];
                       
                       NSInteger counter=0;
                       for(NSDictionary* row in self.contacts)
                       {
                           if([[row objectForKey:@"account_id"]  integerValue]==[accountNo integerValue] )
                           {
                               DDLogVerbose(@"removing  pos %ld", counter);
                               [indexSet addIndex:counter];
                           }
                           counter++;
                       }
                       
                       [self.contacts removeObjectsAtIndexes:indexSet];
                       
                       NSMutableIndexSet* offlineIndexSet;
                    
                       if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                       {
                           offlineIndexSet = [[NSMutableIndexSet alloc] init];
                           counter=0;
                           
                           for(NSDictionary* row in self.offlineContacts)
                           {
                               if([[row objectForKey:@"account_id"]  integerValue]==[accountNo integerValue] )
                               {
                                   DDLogVerbose(@"removing  offline pos %ld", counter);
                                   [offlineIndexSet addIndex:counter];
                               }
                               counter++;
                           }
                           
                           [self.offlineContacts removeObjectsAtIndexes:offlineIndexSet];
                       
                       }
                     
                       if(self.searchResults || self.activeChat) {
                           return;
                           
                       } else {
                           [self->_contactsTable beginUpdates];
                           if([self.contactsTable numberOfChildrenOfItem:@"Online"]>=indexSet.count)
                               [self.contactsTable removeItemsAtIndexes:indexSet inParent:@"Online" withAnimation:NSTableViewAnimationEffectFade];
                           
                           if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
                           {
                               if([self.contactsTable numberOfChildrenOfItem:@"Offline"]>=offlineIndexSet.count)
                                   [self.contactsTable removeItemsAtIndexes:offlineIndexSet inParent:@"Offline" withAnimation:NSTableViewAnimationEffectFade];
                           }
                           
                           [self->_contactsTable endUpdates];
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

-(void) showSSLUpgradeSheet
{
//    if(![[NSUserDefaults standardUserDefaults] boolForKey:@"HasSeenSSLMessage"]) {
//        
//        NSAlert *userAddAlert = [[NSAlert alloc] init];
//        userAddAlert.messageText=@"Security Upgrades";
//        userAddAlert.informativeText =[NSString stringWithFormat:@"This version includes a security fix for the way SSL certificates are checked. It is possible settings that previously worked will not now. If you encouter this, you can temporarily disable certificate validation in your account settings while you figure out why macOS does not like your certificate."];
//        userAddAlert.alertStyle=NSInformationalAlertStyle;
//        [userAddAlert addButtonWithTitle:@"Got it!"];
//     
//    
//        [userAddAlert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
//        
//        }];
//        
//        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"HasSeenSSLMessage"];
//    }
}


#pragma mark - jingle

-(void) showCallRequest:(NSNotification *) notification
{
    NSDictionary *dic = notification.object;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *contactName=[dic objectForKey:@"user"];
        NSString *userName=[dic objectForKey:kAccountName];
        NSAlert *userAddAlert = [[NSAlert alloc] init];
        userAddAlert.messageText =[NSString stringWithFormat:@"Incoming audio call to %@ from %@ ",userName,  contactName];
        userAddAlert.alertStyle=NSInformationalAlertStyle;
        [userAddAlert addButtonWithTitle:@"Decline"];
        [userAddAlert addButtonWithTitle:@"Accept"];
        
        
        [userAddAlert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
            
            BOOL allowed=NO;
            
            if(returnCode ==1001) {
                allowed=YES;
            }
            [[MLXMPPManager sharedInstance] handleCall:dic withResponse:allowed];
           
            if(allowed)
            {
                  [self performSegueWithIdentifier:@"CallScreen" sender:dic];
            }
        }];
    });

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
                           
                               NSInteger activePos =  [self positionOfActiveContact:notification.userInfo];
                               
                               if(activePos>=0)
                               {
                                   
                                   if(activePos<self.contactsTable.numberOfRows) {
                                       [self.contactsTable beginUpdates];
                                       NSIndexSet *indexSet =[[NSIndexSet alloc] initWithIndex:activePos] ;
                                       NSIndexSet *columnIndexSet =[[NSIndexSet alloc] initWithIndex:0] ;
                                       [self.contactsTable reloadDataForRowIndexes:indexSet columnIndexes:columnIndexSet];
                                       [self.contactsTable endUpdates];
                                   }
                               }
                            
                               
                               
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
                                   NSDictionary *dic = self.contacts[pos];
                                   NSNumber *muc=[dic objectForKey:@"Muc"];
                                   if(muc.boolValue ==YES)
                                   {
                                       [dic setValue:[notification.userInfo objectForKey:@"muc_subject"] forKey:@"muc_subject"];
                                   }
                                   [self refreshContact:notification];
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

#pragma mark - outline view datasource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    if(self.searchResults) {
        return self.searchResults.count;
    }
    else {
        if(self.currentSegment==kActiveTab)
        {
            return [self.activeChat count];
        } else  {
            if(!item) {
                if([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"]) {
                    return 2;
                }
                else {
                    return 1;
                }
                
            }
            else  {
                if([item isKindOfClass:[NSString class]])
                {
                    NSString *section = (NSString *) item;
                    if([section isEqualToString:@"Online"])
                    {
                         return [self.contacts count];
                    } else  {
                        return [self.offlineContacts count];
                    }
                }  else  {
                    return 0;
                }
              
            }
        }
    }

    
    
}


//- (BOOL)outlineView:(NSOutlineView *)outlineView shouldExpandItem:(id)item
//{
//
//}
//
//- (BOOL)outlineView:(NSOutlineView *)outlineView shouldCollapseItem:(id)item
//{
//
//}


- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    if([item isKindOfClass:[NSString class]]) {
        return YES;
    }
    else {
        return NO;
    }
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    if(self.searchResults) {
        return self.searchResults[index];
    }
    else {
        if(self.currentSegment==kActiveTab)
        {
            return self.activeChat[index];
        } else  {
            if(!item) {
                if(index==0) return @"Online";
                else return @"Offline";
            }
            else  {
                if([item isKindOfClass:[NSString class]])
                {
                    NSString *section = (NSString *) item;
                    if([section isEqualToString:@"Online"])
                    {
                        if(index<self.contacts.count) {
                            return self.contacts[index];
                        }else return @"";
                    } else  {
                        if(index<self.offlineContacts.count) {
                            return self.offlineContacts[index];
                        } else return @"";
                    }
                }  else  {
                    return 0;
                }
                
            }
        }
    }
}


- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
    return item;
}

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item;
{
    if([item isKindOfClass:[NSString class]])
    {
        return 17;
    } else return 60;
}

#pragma mark - outline delegate

-(NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    if([item isKindOfClass:[NSString class]])
    {
        NSString *section = (NSString *) item;
        NSTableCellView *cell= [outlineView makeViewWithIdentifier:@"headerCell" owner:self];
        cell.textField.stringValue=section;
        return cell;
        
    }
    
    MLContact *contactRow =item;
    
    MLContactsCell *cell = [outlineView makeViewWithIdentifier:@"contactCell" owner:self];
    cell.name.backgroundColor =[NSColor clearColor];
    cell.status.backgroundColor= [NSColor clearColor];
     
    cell.name.stringValue=contactRow.contactDisplayName;
    
    cell.accountNo= contactRow.accountId;
    
    if(cell.username)
    {
        [cell setUnreadCount:0];
    }
    
    NSString *statusText ;
 
    cell.username =contactRow.contactJid;
    
    if(contactRow.isGroup ==YES)
    {
        cell.name.stringValue = contactRow.contactJid ;
        cell.status.stringValue =contactRow.groupSubject;
    }
    else  {
        statusText = contactRow.statusMessage;
        if(statusText) {
            if( [statusText isEqualToString:@"(null)"])  {
                statusText = @"";
            }
        }
        cell.status.stringValue=statusText;
    }
   
    
    NSString *state= [contactRow.state stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
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

    NSString* accountNo=contactRow.accountId;
    NSString *cellUser = contactRow.contactJid;
    
    if(self.currentSegment==kActiveTab) {
        NSMutableArray *message = [[DataLayer sharedInstance] lastMessageForContact:cell.username andAccount:accountNo];
        if(message.count>0)
        {
            MLMessage *row = message[0];
            if([row.messageType isEqualToString:kMessageTypeUrl])
            {
                cell.status.stringValue =@"🔗 A Link";
            } else if([row.messageType isEqualToString:kMessageTypeImage])
            {
                cell.status.stringValue =@"📷 An Image";
            } else  {
                cell.status.stringValue =row.messageText;
            }
        }
    }
    
    if(contactRow.lastMessageTime) {
        cell.time.stringValue = [self formattedDateWithSource:contactRow.lastMessageTime];
        cell.time.hidden=NO;
    } else  {
        cell.time.hidden=YES;
    }
    
    [[MLImageManager sharedInstance] getIconForContact:cell.username andAccount:accountNo withCompletion:^(NSImage *image) {
        if([cell.username isEqualToString:cellUser]) {
            cell.icon.image=image;
        }
    }];

    
    [cell setUnreadCount:0];
    [[DataLayer sharedInstance] countUserUnreadMessages:cell.username forAccount:accountNo withCompletion:^(NSNumber * result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [cell setUnreadCount:[result integerValue]];
        });
    }];

    [[DataLayer sharedInstance] isMutedJid:contactRow.contactJid  withCompletion:^(BOOL muted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            cell.muteBadge.hidden=!muted;
        });
    }];
    
    return cell;
}


- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
    if(self.searchResults && self.contactsTable.selectedRow<self.searchResults.count)
    {
        NSDictionary *contactRow = [self.searchResults objectAtIndex:self.contactsTable.selectedRow];
        [self.chatViewController showConversationForContact:contactRow];
     
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if((self.view.window.occlusionState & NSWindowOcclusionStateVisible)) {
                [[DataLayer sharedInstance] markAsReadBuddy:[contactRow objectForKey:kContactName] forAccount:[contactRow objectForKey:kAccountID]];
                [self updateAppBadge];
                [self.contactsTable beginUpdates];
                NSIndexSet *indexSet =[[NSIndexSet alloc] initWithIndex:self.contactsTable.selectedRow] ;
                NSIndexSet *columnIndexSet =[[NSIndexSet alloc] initWithIndex:0] ;
                [self.contactsTable reloadDataForRowIndexes:indexSet columnIndexes:columnIndexSet];
                [self.contactsTable endUpdates];
            }
        });
       
    }
    else
        if(self.currentSegment==kActiveTab)
        {
            if(self.contactsTable.selectedRow<self.activeChat.count) {
                NSDictionary *contactRow = [self.activeChat objectAtIndex:self.contactsTable.selectedRow];
                [self.chatViewController showConversationForContact:contactRow];
                
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(),^{
                    if((self.view.window.occlusionState & NSWindowOcclusionStateVisible)) {
                        [[DataLayer sharedInstance] markAsReadBuddy:[contactRow objectForKey:kContactName] forAccount:[contactRow objectForKey:kAccountID]];
                        [self updateAppBadge];
                    }
                    
                    [self.contactsTable beginUpdates];
                    NSIndexSet *indexSet =[[NSIndexSet alloc] initWithIndex:self.contactsTable.selectedRow] ;
                    NSIndexSet *columnIndexSet =[[NSIndexSet alloc] initWithIndex:0] ;
                    [self.contactsTable reloadDataForRowIndexes:indexSet columnIndexes:columnIndexSet];
                    [self.contactsTable endUpdates];
                });
            }
        }
        else  {
            
            MLContact* contactRow =[self.contactsTable itemAtRow:self.contactsTable.selectedRow];
            
                [self.chatViewController showConversationForContact:contactRow];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    if((self.view.window.occlusionState & NSWindowOcclusionStateVisible)) {
                        if((self.view.window.occlusionState & NSWindowOcclusionStateVisible)) {
                            [[DataLayer sharedInstance] markAsReadBuddy:contactRow.contactJid forAccount:contactRow.accountId];
                            [self updateAppBadge];
                        }
                        
                        [self.contactsTable beginUpdates];
                        NSIndexSet *indexSet =[[NSIndexSet alloc] initWithIndex:self.contactsTable.selectedRow] ;
                        NSIndexSet *columnIndexSet =[[NSIndexSet alloc] initWithIndex:0] ;
                        [self.contactsTable reloadDataForRowIndexes:indexSet columnIndexes:columnIndexSet];
                        [self.contactsTable endUpdates];
                    }
                });
            
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
        self.searchResults=[[[DataLayer sharedInstance] searchContactsWithString:searchField.stringValue] mutableCopy];
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

#pragma mark - server details

-(void)prepareForSegue:(NSStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"showServerDetails"])
    {
        
        NSMenuItem *item = (NSMenuItem *) sender;
        NSInteger accountNo = item.tag-1000;
         xmpp* xmppAccount= [[MLXMPPManager sharedInstance] getConnectedAccountForID:[NSString stringWithFormat:@"%ld", accountNo ]];
        
        MLServerDetailsVC *details =  (MLServerDetailsVC *)segue.destinationController;
        details.xmppAccount=xmppAccount;
        
    }
    
    if([segue.identifier isEqualToString:@"showMAMPref"])
    {
        
        NSMenuItem *item = (NSMenuItem *) sender;
        NSInteger accountNo = item.tag-2000;
        xmpp* xmppAccount= [[MLXMPPManager sharedInstance] getConnectedAccountForID:[NSString stringWithFormat:@"%ld", accountNo ]];
        
        MLMAMPref *details =  (MLMAMPref *)segue.destinationController;
        details.xmppAccount=xmppAccount;
        
    }
    
    if([segue.identifier isEqualToString:@"showKeys"])
    {
        NSMenuItem *item = (NSMenuItem *) sender;
        NSInteger accountNo = item.tag-3000;
        xmpp* xmppAccount= [[MLXMPPManager sharedInstance] getConnectedAccountForID:[NSString stringWithFormat:@"%ld", accountNo ]];
        
        MLKeyViewController *keys = (MLKeyViewController *)segue.destinationController;
        keys.ownKeys=YES;
        keys.contact =@{@"buddy_name":xmppAccount.connectionProperties.identity.jid, @"account_id":[NSNumber numberWithInt:accountNo]};
    }
    
    if([segue.identifier isEqualToString:@"CallScreen"])
    {
        NSDictionary *dic= (NSDictionary *) sender;
        MLCallScreen *call =  (MLCallScreen *)segue.destinationController;
        call.contact=dic;
    }
}

-(IBAction) showServerDetails:(id) sender
{
    [self performSegueWithIdentifier:@"showServerDetails" sender:sender];
}


-(IBAction) showMAMPref:(id) sender
{
    [self performSegueWithIdentifier:@"showMAMPref" sender:sender];
}
    
-(IBAction) showKeys:(id) sender
{
    [self performSegueWithIdentifier:@"showKeys" sender:sender];
}


#pragma mark - date

-(NSString*) formattedDateWithSource:(NSDate*) sourceDate
{
    NSString* dateString;

    NSInteger msgday =[self.gregorian components:NSCalendarUnitDay fromDate:sourceDate].day;
    NSInteger msgmonth=[self.gregorian components:NSCalendarUnitMonth fromDate:sourceDate].month;
    NSInteger msgyear =[self.gregorian components:NSCalendarUnitYear fromDate:sourceDate].year;
    
    BOOL showFullDate=YES;
    
    //if([sourceDate timeIntervalSinceDate:priorDate]<60*60) showFullDate=NO;
    
    if (((self.thisday!=msgday) || (self.thismonth!=msgmonth) || (self.thisyear!=msgyear)) && showFullDate )
    {
        // note: if it isnt the same day we want to show the full  day
        [self.destinationDateFormat setDateStyle:NSDateFormatterMediumStyle];
        //no more need for seconds
        [self.destinationDateFormat setTimeStyle:NSDateFormatterNoStyle];
    }
    else
    {
        //today just show time
        [self.destinationDateFormat setDateStyle:NSDateFormatterNoStyle];
        [self.destinationDateFormat setTimeStyle:NSDateFormatterShortStyle];
    }

    dateString = [self.destinationDateFormat stringFromDate:sourceDate];
    return dateString?dateString:@"";
}

-(void) setupDateObjects
{
    self.destinationDateFormat = [[NSDateFormatter alloc] init];
    [self.destinationDateFormat setLocale:[NSLocale currentLocale]];
    [self.destinationDateFormat setDoesRelativeDateFormatting:YES];
    
    self.sourceDateFormat = [[NSDateFormatter alloc] init];
    [self.sourceDateFormat setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    [self.sourceDateFormat setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    
    self.gregorian = [[NSCalendar alloc]
                      initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDate* now =[NSDate date];
    self.thisday =[self.gregorian components:NSCalendarUnitDay fromDate:now].day;
    self.thismonth =[self.gregorian components:NSCalendarUnitMonth fromDate:now].month;
    self.thisyear =[self.gregorian components:NSCalendarUnitYear fromDate:now].year;
    
    
}

-(IBAction)toggleEncryption:(id)sender
{
    [self.chatViewController toggleEncryption:sender];
}

@end
