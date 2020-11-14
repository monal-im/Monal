//
//  ActiveChatsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "ActiveChatsViewController.h"
#import "DataLayer.h"
#import "xmpp.h"
#import "MLContactCell.h"
#import "chatViewController.h"
#import "MonalAppDelegate.h"
#import "ContactDetails.h"
#import "MLImageManager.h"
#import "MLWelcomeViewController.h"
#import "ContactsViewController.h"
#import "MLNewViewController.h"
#import "MLXEPSlashMeHandler.h"

@interface ActiveChatsViewController ()

@property (nonatomic, strong)  NSDateFormatter* destinationDateFormat;
@property (nonatomic, strong)  NSDateFormatter* sourceDateFormat;
@property (nonatomic, strong)  NSCalendar *gregorian;
@property (nonatomic, assign)  NSInteger thisyear;
@property (nonatomic, assign)  NSInteger thismonth;
@property (nonatomic, assign)  NSInteger thisday;

@property (nonatomic, strong) NSMutableArray* unpinnedContacts;
@property (nonatomic, strong) NSMutableArray* pinnedContacts;

@property (nonatomic, strong) MLContact* lastSelectedUser;
@property (nonatomic, strong) NSIndexPath *lastSelectedIndexPath;

@end

@implementation ActiveChatsViewController

enum activeChatsControllerSections {
    pinnedChats,
    unpinnedChats,
    activeChatsViewControllerSectionCnt
};

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
    self.view.backgroundColor=[UIColor lightGrayColor];
    self.view.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    
    MonalAppDelegate *appDelegte = (MonalAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appDelegte setActiveChatsController:self];
    
     self.chatListTable=[[UITableView alloc] init];
     self.chatListTable.delegate=self;
     self.chatListTable.dataSource=self;
    
    self.view = self.chatListTable;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshDisplay) name:kMonalRefresh object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshContact:) name:kMonalContactRefresh object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(messageSent:) name:kMLMessageSentToContact object:nil];
    
    [_chatListTable registerNib:[UINib nibWithNibName:@"MLContactCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"ContactCell"];
    
    self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeAllVisible;
    if(@available(iOS 13.0, *))
    {
#if !TARGET_OS_MACCATALYST
        self.splitViewController.primaryBackgroundStyle = UISplitViewControllerBackgroundStyleSidebar;
#endif
        self.settingsButton.image = [UIImage systemImageNamed:@"person.crop.circle"];
        self.addButton.image = [UIImage systemImageNamed:@"plus"];
        self.composeButton.image = [UIImage systemImageNamed:@"square.and.pencil"];
    }
    else
    {
        self.settingsButton.image = [UIImage imageNamed:@"973-user"];
        self.addButton.image = [UIImage imageNamed:@"907-plus-rounded-square"];
        self.composeButton.image = [UIImage imageNamed:@"704-compose"];
    }
    
    self.chatListTable.emptyDataSetSource = self;
    self.chatListTable.emptyDataSetDelegate = self;
    [self setupDateObjects];
}


-(void) refreshDisplay
{
    NSMutableArray* activeContactsUnpinned = [[DataLayer sharedInstance] activeContactsWithPinned:NO];
    NSMutableArray* activeContactsPinned = [[DataLayer sharedInstance] activeContactsWithPinned:YES];
    if(!activeContactsUnpinned || ! activeContactsPinned)
        return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if(self.chatListTable.hasUncommittedUpdates)
            return;
        // Remove self chats (contact == self) FIXME
        [[MLXMPPManager sharedInstance] cleanArrayOfConnectedAccounts:activeContactsUnpinned];
        [[MLXMPPManager sharedInstance] cleanArrayOfConnectedAccounts:activeContactsPinned];

        self.unpinnedContacts = activeContactsUnpinned;
        self.pinnedContacts = activeContactsPinned;

        [self.chatListTable reloadData];
        MonalAppDelegate* appDelegate = (MonalAppDelegate*)[UIApplication sharedApplication].delegate;
        [appDelegate updateUnread];
    });
}

-(void) refreshContact:(NSNotification*) notification
{
    MLContact* contact = [notification.userInfo objectForKey:@"contact"];
    
    if([notification.userInfo objectForKey:@"pinningChanged"]) {
        // if pinning changed we have to move the user to a other section
        [self insertOrMoveContact:contact completion:nil];
    } else {
        __block NSIndexPath* indexPath = nil;
        for(size_t section = pinnedChats; section < activeChatsViewControllerSectionCnt && !indexPath; section++) {
            NSMutableArray* curContactArray = [self getChatArrayForSection:section];

            // check if contact is already displayed -> get coresponding indexPath
            [curContactArray enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                MLContact* rowContact = (MLContact*)obj;
                if(
                    [rowContact.contactJid isEqualToString:contact.contactJid] &&
                    [rowContact.accountId isEqualToString:contact.accountId]
                ) {
                    //this MLContact instance is used in various ui parts, not just this file --> update all properties but keep the instance intact
                    [rowContact updateWithContact:contact];
                    indexPath = [NSIndexPath indexPathForRow:idx inSection:section];
                    *stop = YES;
                }
            }];
        }
        // reload contact entry if we found it
        if(indexPath) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.chatListTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            });
        }
    }
}

-(void) messageSent:(NSNotification *) notification
{
    MLContact* contact = [notification.userInfo objectForKey:@"contact"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self insertOrMoveContact:contact completion:nil];
    });
}

-(void) handleNewMessage:(NSNotification*) notification
{
    MLMessage* newMessage = [notification.userInfo objectForKey:@"message"];
    xmpp* msgAccount = (xmpp*)notification.object;
    if([newMessage.messageType isEqualToString:kMessageTypeStatus])
        return;

    if(!msgAccount)
        return;

    NSString* buddyContactJid = newMessage.from;
    if([msgAccount.connectionProperties.identity.jid isEqualToString:newMessage.from]) {
        buddyContactJid = newMessage.to;
    }

    MLContact* contact = [[DataLayer sharedInstance] contactForUsername:buddyContactJid forAccount:newMessage.accountId];
    if(!contact)
        return;
    
    // contact.statusMessage = newMessage;
    [self insertOrMoveContact:contact completion:nil];
}

-(void) insertOrMoveContact:(MLContact *) contact completion:(void (^ _Nullable)(BOOL finished))completion {
    __block NSIndexPath* indexPath = nil;
    for(size_t section = pinnedChats; section < activeChatsViewControllerSectionCnt && !indexPath; section++) {
        NSMutableArray* curContactArray = [self getChatArrayForSection:section];

        // check if contact is already displayed -> get coresponding indexPath
        [curContactArray enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            MLContact* rowContact = (MLContact *) obj;
            if([rowContact.contactJid isEqualToString:contact.contactJid] &&
               [rowContact.accountId isEqualToString:contact.accountId]) {
                indexPath = [NSIndexPath indexPathForRow:idx inSection:section];
                *stop = YES;
            }
        }];
    }

    size_t insertInSection = unpinnedChats;
    if(contact.isPinned) {
        insertInSection = pinnedChats;
    }
    NSMutableArray* insertContactToArray = [self getChatArrayForSection:insertInSection];
    NSIndexPath* insertAtPath = [NSIndexPath indexPathForRow:0 inSection:insertInSection];

    if(indexPath && insertAtPath.section == indexPath.section && insertAtPath.row == indexPath.row) {
        [insertContactToArray replaceObjectAtIndex:insertAtPath.row  withObject:contact];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.chatListTable reloadRowsAtIndexPaths:@[insertAtPath] withRowAnimation:UITableViewRowAnimationNone];
        });
        return;
    } else if(indexPath) {
        // Contact is already in out active chats list
        NSMutableArray* removeContactFromArray = [self getChatArrayForSection:indexPath.section];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.chatListTable performBatchUpdates:^{
                [removeContactFromArray removeObjectAtIndex:indexPath.row];
                [insertContactToArray insertObject:contact atIndex:0];
                [self.chatListTable moveRowAtIndexPath:indexPath toIndexPath:insertAtPath];
            } completion:^(BOOL finished) {
                if(completion) completion(finished);
            }];
        });
    }
    else {
        // Chats does not exists in active Chats yet
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.chatListTable beginUpdates];
            [insertContactToArray insertObject:contact atIndex:0];
            [self.chatListTable insertRowsAtIndexPaths:@[insertAtPath] withRowAnimation:UITableViewRowAnimationRight];
            [self.chatListTable endUpdates];
            if(completion) completion(YES);
        });
    }
}

-(void) viewWillAppear:(BOOL) animated
{
    [super viewWillAppear:animated];
    self.lastSelectedUser = nil;
}

-(void) viewDidAppear:(BOOL) animated
{
    [super viewDidAppear:animated];
    if(self.unpinnedContacts.count == 0) {
        [self refreshDisplay];
    }
  
    if(![[HelperTools defaultsDB] boolForKey:@"HasSeenIntro"]) {
        [self performSegueWithIdentifier:@"showIntro" sender:self];
    }
    else  {
        //for 3->4 release remove later
        if(![[HelperTools defaultsDB] boolForKey:@"HasSeeniOS13Message"]) {
            
            UIAlertController *messageAlert =[UIAlertController alertControllerWithTitle:NSLocalizedString(@"Notification Changes",@ "") message:[NSString stringWithFormat:NSLocalizedString(@"Notifications have changed in iOS 13 because of some iOS changes. For now you will just see something saying there is a new message and not the text or who sent it. I have decided to do this so you have reliable messaging while I work to update Monal to get the old expereince back.",@ "")] preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *acceptAction =[UIAlertAction actionWithTitle:NSLocalizedString(@"Got it!",@ "") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self dismissViewControllerAnimated:YES completion:nil];
                
            }];
            [messageAlert addAction:acceptAction];
            [self.tabBarController presentViewController:messageAlert animated:YES completion:nil];
            [[HelperTools defaultsDB] setBool:YES forKey:@"HasSeeniOS13Message"];
        }
    }
}

-(void) didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void) presentChatWithRow:(MLContact *)row
{
    [self  performSegueWithIdentifier:@"showConversation" sender:row];
}

/*
 * return YES if no enabled account was found && a alert will open
 */
-(BOOL) showAccountNumberWarningIfNeeded
{
    // Only open contacts list / roster if at least one account is enabled
    if([[DataLayer sharedInstance] enabledAccountCnts].intValue == 0) {
        // Show warning
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"No enabled account found", @"") message:NSLocalizedString(@"Please add a new account under settings first. If you already added your account you may need to enable it under settings", @"") preferredStyle:UIAlertControllerStyleActionSheet];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return YES;
    }
    return NO;
}

-(void) prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"showIntro"])
    {
        MLWelcomeViewController* welcome = (MLWelcomeViewController *) segue.destinationViewController;
        welcome.completion = ^(){
            if([[MLXMPPManager sharedInstance].connectedXMPP count] == 0)
            {
                if(![[HelperTools defaultsDB] boolForKey:@"HasSeenLogin"]) {
                    [self performSegueWithIdentifier:@"showLogin" sender:self];
                }
            }
        };
    }
    else if([segue.identifier isEqualToString:@"showConversation"])
    {
        UINavigationController *nav = segue.destinationViewController;
        chatViewController *chatVC = (chatViewController *)nav.topViewController;
        UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];
        self.navigationItem.backBarButtonItem = barButtonItem;
        [chatVC setupWithContact:sender];
    }
    else if([segue.identifier isEqualToString:@"showDetails"])
    {
        UINavigationController* nav = segue.destinationViewController;
        ContactDetails* details = (ContactDetails *)nav.topViewController;
        details.contact= sender;
    }
    else if([segue.identifier isEqualToString:@"showContacts"])
    {
        // Only segue if at least one account is enabled
        if([self showAccountNumberWarningIfNeeded]) {
            return;
        }

        UINavigationController* nav = segue.destinationViewController;
        ContactsViewController* contacts = (ContactsViewController *)nav.topViewController;
        contacts.selectContact = ^(MLContact* selectedContact) {
            [[DataLayer sharedInstance] addActiveBuddies:selectedContact.contactJid forAccount:selectedContact.accountId];
            //no success may mean its already there
            dispatch_async(dispatch_get_main_queue(), ^{
                [self insertOrMoveContact:selectedContact completion:^(BOOL finished) {
                    size_t sectionToUse = unpinnedChats; // Default is not pinned
                    if(selectedContact.isPinned) {
                        sectionToUse = pinnedChats; // Insert in pinned section
                    }
                    NSIndexPath* path = [NSIndexPath indexPathForRow:0 inSection:sectionToUse];
                    [self.chatListTable selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
                    [self presentChatWithRow:selectedContact];
                }];
            });
        };
    }
    else if([segue.identifier isEqualToString:@"showNew"])
      {
          // Only segue if at least one account is enabled
          if([self showAccountNumberWarningIfNeeded]) {
              return;
          }
          UINavigationController* nav = segue.destinationViewController;
          MLNewViewController* newScreen = (MLNewViewController *)nav.topViewController;
          newScreen.selectContact = ^(MLContact *selectedContact) {
              [[DataLayer sharedInstance] addActiveBuddies:selectedContact.contactJid forAccount:selectedContact.accountId];
              //no success may mean its already there
              dispatch_async(dispatch_get_main_queue(), ^{
                  [self insertOrMoveContact:selectedContact completion:^(BOOL finished) {
                      NSIndexPath* path = [NSIndexPath indexPathForRow:0 inSection:unpinnedChats];
                                        [self.chatListTable selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
                                          [self presentChatWithRow:selectedContact];
                  }];
              });
          };
      }
}

-(NSMutableArray*) getChatArrayForSection:(size_t) section
{
    NSMutableArray* chatArray = nil;
    if(section == pinnedChats) {
        chatArray = self.pinnedContacts;
    } else if(section == unpinnedChats) {
        chatArray = self.unpinnedContacts;
    }
    return chatArray;
}
#pragma mark - tableview datasource

-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return activeChatsViewControllerSectionCnt;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if(section == pinnedChats) {
        return [self.pinnedContacts count];
    } else if(section == unpinnedChats) {
        return [self.unpinnedContacts count];
    } else {
        return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    MLContactCell* cell = [tableView dequeueReusableCellWithIdentifier:@"ContactCell"];
    if(!cell)
    {
        cell = [[MLContactCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ContactCell"];
    }
    MLContact* row = nil;
    // Select correct contact array
    if(indexPath.section == pinnedChats) {
        row = [self.pinnedContacts objectAtIndex:indexPath.row];
        // mark pinned chats
        [cell setPinned:YES];
    } else {
        row = [self.unpinnedContacts objectAtIndex:indexPath.row];
        [cell setPinned:NO];
    }
    [cell showDisplayName:row.contactDisplayName];
    
    NSString* state = [row.state stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if(([state isEqualToString:@"away"]) ||
       ([state isEqualToString:@"dnd"])||
       ([state isEqualToString:@"xa"])
       )
    {
        cell.status = kStatusAway;
    }
    else if([state isEqualToString:@"offline"]) {
        cell.status = kStatusOffline;
    }
    else if([state isEqualToString:@"(null)"] || [state isEqualToString:@""]) {
        cell.status = kStatusOnline;
    }
    
    cell.accountNo = row.accountId.integerValue;
    cell.username = row.contactJid;
    cell.count = 0;
    
    NSNumber* unreadMsgCnt = [[DataLayer sharedInstance] countUserUnreadMessages:row.contactJid forAccount:row.accountId];
    dispatch_async(dispatch_get_main_queue(), ^{
        if([cell.username isEqualToString:row.contactJid]){
            cell.count = [unreadMsgCnt integerValue];
        }
    });
    
    NSMutableArray* messages = [[DataLayer sharedInstance] lastMessageForContact:cell.username forAccount:row.accountId];
    dispatch_async(dispatch_get_main_queue(), ^{
        if(messages.count > 0)
        {
            MLMessage *messageRow = messages[0];
            if([messageRow.messageType isEqualToString:kMessageTypeUrl])
            {
                [cell showStatusText:NSLocalizedString(@"🔗 A Link", @"")];
            } else if([messageRow.messageType isEqualToString:kMessageTypeImage])
            {
                [cell showStatusText:NSLocalizedString(@"📷 An Image", @"")];
            } else if ([messageRow.messageType isEqualToString:kMessageTypeMessageDraft]) {
                NSString* draftPreview = [NSString stringWithFormat:NSLocalizedString(@"Draft: %@", @""), messageRow.messageText];
                [cell showStatusTextItalic:draftPreview withItalicRange:NSMakeRange(0, 6)];
            } else if([messageRow.messageType isEqualToString:kMessageTypeGeo])
            {
                [cell showStatusText:NSLocalizedString(@"📍 A Location", @"")];
            } else  {
                //XEP-0245: The slash me Command
                NSString* displayName;
                NSDictionary* accountDict = [[DataLayer sharedInstance] detailsForAccount:row.accountId];
                NSString* ownJid = [NSString stringWithFormat:@"%@@%@",[accountDict objectForKey:@"username"], [accountDict objectForKey:@"domain"]];
                if([messageRow.actualFrom isEqualToString:ownJid])
                    displayName = [MLContact ownDisplayNameForAccountNo:row.accountId andOwnJid:ownJid];
                else
                    displayName = [row contactDisplayName];
                if([messageRow.messageText hasPrefix:@"/me "])
                {
                    NSString* replacedMessageText = [[MLXEPSlashMeHandler sharedInstance] stringSlashMeWithAccountId:row.accountId
                                                                                                         displayName:displayName
                                                                                                          actualFrom:messageRow.actualFrom
                                                                                                             message:messageRow.messageText
                                                                                                             isGroup:row.isGroup];
                    
                    NSRange replacedMsgAttrRange = NSMakeRange(0, replacedMessageText.length);
                    
                    [cell showStatusTextItalic:replacedMessageText withItalicRange:replacedMsgAttrRange];
                }
                else
                {
                    [cell showStatusText:messageRow.messageText];
                }
            }
            if(messageRow.timestamp) {
                cell.time.text = [self formattedDateWithSource:messageRow.timestamp];
                cell.time.hidden = NO;
            } else  {
                cell.time.hidden = YES;
            }
        } else  {
            [cell showStatusText:nil];
            DDLogWarn(NSLocalizedString(@"Active chat but no messages found in history for %@.", @""), row.contactJid);
        }
    });
    [[MLImageManager sharedInstance] getIconForContact:row.contactJid andAccount:row.accountId withCompletion:^(UIImage *image) {
            cell.userImage.image = image;
    }];
    [cell setOrb];
    return cell;
}


#pragma mark - tableview delegate

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 60.0f;
}


-(NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return NSLocalizedString(@"Hide Chat", @"");
}


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
        MLContact* contact = nil;
        // Delete contact from view
        if(indexPath.section == pinnedChats) {
            contact = [self.pinnedContacts objectAtIndex:indexPath.row];
            [self.pinnedContacts removeObjectAtIndex:indexPath.row];
        } else {
            contact = [self.unpinnedContacts objectAtIndex:indexPath.row];
            [self.unpinnedContacts removeObjectAtIndex:indexPath.row];
        }
        [self.chatListTable deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        // removeActiveBuddy in db
        [[DataLayer sharedInstance] removeActiveBuddy:contact.contactJid forAccount:contact.accountId];
    }
}

-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    self.lastSelectedIndexPath = indexPath;
    MLContact* selected = nil;
    if(indexPath.section == pinnedChats) {
        selected = self.pinnedContacts[indexPath.row];
    } else {
        selected = self.unpinnedContacts[indexPath.row];
    }
    // Only open contact chat when it is not opened yet -> macOS
    if(selected.contactJid == self.lastSelectedUser.contactJid) return;
    
    [self presentChatWithRow:selected];
    self.lastSelectedUser = selected;
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary* contactDic = [self.unpinnedContacts objectAtIndex:indexPath.row];

    [self performSegueWithIdentifier:@"showDetails" sender:contactDic];
}


#pragma mark - empty data set

- (UIImage *)imageForEmptyDataSet:(UIScrollView *)scrollView
{
    return [UIImage imageNamed:@"pooh"];
}

- (NSAttributedString *)titleForEmptyDataSet:(UIScrollView *)scrollView
{
    NSString* text = NSLocalizedString(@"No one is here", @"");
    
    NSDictionary* attributes = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:18.0f],
                                 NSForegroundColorAttributeName: [UIColor darkGrayColor]};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (NSAttributedString *)descriptionForEmptyDataSet:(UIScrollView *)scrollView
{
    NSString* text = NSLocalizedString(@"When you start talking to someone,\n they will show up here.", @"");
    
    NSMutableParagraphStyle* paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    paragraph.alignment = NSTextAlignmentCenter;
    
    NSDictionary* attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:14.0f],
                                 NSForegroundColorAttributeName: [UIColor lightGrayColor],
                                 NSParagraphStyleAttributeName: paragraph};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

-(UIColor*) backgroundColorForEmptyDataSet:(UIScrollView*) scrollView
{
    return [UIColor colorNamed:@"chats"];
}

-(BOOL) emptyDataSetShouldDisplay:(UIScrollView*) scrollView
{
    BOOL toreturn = (self.unpinnedContacts.count==0)?YES:NO;
    if(toreturn)
    {
        // A little trick for removing the cell separators
        self.tableView.tableFooterView = [UIView new];
    }
    return toreturn;
}

#pragma mark - date

-(NSString*) formattedDateWithSource:(NSDate*) sourceDate
{
    NSInteger msgday = [self.gregorian components:NSCalendarUnitDay fromDate:sourceDate].day;
    NSInteger msgmonth = [self.gregorian components:NSCalendarUnitMonth fromDate:sourceDate].month;
    NSInteger msgyear = [self.gregorian components:NSCalendarUnitYear fromDate:sourceDate].year;
    
    BOOL showFullDate = YES;
    
    //if([sourceDate timeIntervalSinceDate:priorDate]<60*60) showFullDate=NO;
    
    if (((self.thisday != msgday) || (self.thismonth != msgmonth) || (self.thisyear != msgyear)) && showFullDate )
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
    
    NSString *dateString = [self.destinationDateFormat stringFromDate:sourceDate];
    return dateString ? dateString : @"";
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
    NSDate* now = [NSDate date];
    self.thisday = [self.gregorian components:NSCalendarUnitDay fromDate:now].day;
    self.thismonth = [self.gregorian components:NSCalendarUnitMonth fromDate:now].month;
    self.thisyear = [self.gregorian components:NSCalendarUnitYear fromDate:now].year;
    
    
}

#pragma mark -mac menu
-(void) showNew {
    // Only segue if at least one account is enabled
    if([self showAccountNumberWarningIfNeeded]) {
        return;
    }
    [self performSegueWithIdentifier:@"showContacts" sender:self];
}

-(void) showDetails {
    if(self.lastSelectedUser)
        [self performSegueWithIdentifier:@"showDetails" sender:self.lastSelectedUser];
}

-(void) deleteConversation {
    if(self.lastSelectedIndexPath)
        [self tableView:self.chatListTable commitEditingStyle:UITableViewCellEditingStyleDelete forRowAtIndexPath:self.lastSelectedIndexPath];
}

-(void) showSettings {
   [self performSegueWithIdentifier:@"showSettings" sender:self];
}


-(IBAction) unwindToActiveChatsViewController:(UIStoryboardSegue*) segue
{
    // Show normal navigation bar again
    [[self navigationController] setNavigationBarHidden:NO animated:NO];
    
    // unselected the current user
    self.lastSelectedUser = nil;
}

@end
