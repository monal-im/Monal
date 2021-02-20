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

static NSMutableSet* _mamWarningDisplayed;
static NSMutableSet* _smacksWarningDisplayed;

+(void) initialize
{
    _mamWarningDisplayed = [[NSMutableSet alloc] init];
    _smacksWarningDisplayed = [[NSMutableSet alloc] init];
}

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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshDisplay) name:kMonalMessageFiletransferUpdateNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshContact:) name:kMonalContactRefresh object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalDeletedMessageNotice object:nil];
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
        self.settingsButton.image = [UIImage systemImageNamed:@"gearshape.fill"];
        self.addButton.image = [UIImage systemImageNamed:@"plus"];
        self.composeButton.image = [UIImage systemImageNamed:@"person.2.fill"];
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
    size_t unpinnedConCntBefore = self.unpinnedContacts.count;
    size_t pinnedConCntBefore = self.pinnedContacts.count;
    NSMutableArray<MLContact*>* newUnpinnedContacts = [[DataLayer sharedInstance] activeContactsWithPinned:NO];
    NSMutableArray<MLContact*>* newPinnedContacts = [[DataLayer sharedInstance] activeContactsWithPinned:YES];
    if(!newUnpinnedContacts || ! newPinnedContacts)
        return;

    int unpinnedCntDiff = (int)unpinnedConCntBefore - (int)newUnpinnedContacts.count;
    int pinnedCntDiff = (int)pinnedConCntBefore - (int)newPinnedContacts.count;

    void (^resizeSections)(UITableView*, size_t, int) = ^void(UITableView* table, size_t section, int diff){
        if(diff > 0)
        {
            // remove rows
            for(size_t i = 0; i < diff; i++)
            {
                NSIndexPath* posInSection = [NSIndexPath indexPathForRow:i inSection:section];
                [table deleteRowsAtIndexPaths:@[posInSection] withRowAnimation:UITableViewRowAnimationNone];
            }
        }
        else if(diff < 0)
        {
            // add rows
            for(size_t i = (-1) * diff; i > 0; i--)
            {
                NSIndexPath* posInSectin = [NSIndexPath indexPathForRow:(i - 1) inSection:section];
                [table insertRowsAtIndexPaths:@[posInSectin] withRowAnimation:UITableViewRowAnimationNone];
            }
        }
    };

    dispatch_async(dispatch_get_main_queue(), ^{
        if(self.chatListTable.hasUncommittedUpdates)
            return;
        [UIView performWithoutAnimation:^{
            [self.chatListTable beginUpdates];
            resizeSections(self.chatListTable, unpinnedChats, unpinnedCntDiff);
            resizeSections(self.chatListTable, pinnedChats, pinnedCntDiff);
            self.unpinnedContacts = newUnpinnedContacts;
            self.pinnedContacts = newPinnedContacts;
            [self.chatListTable reloadData];
            [self.chatListTable endUpdates];
        }];

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
                [self.chatListTable deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                [removeContactFromArray removeObjectAtIndex:indexPath.row];
                [insertContactToArray insertObject:contact atIndex:0];
                [self.chatListTable insertRowsAtIndexPaths:@[insertAtPath] withRowAnimation:UITableViewRowAnimationNone];
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
    // load contacts
    self.lastSelectedUser = nil;
    if(self.unpinnedContacts.count == 0) {
        [self refreshDisplay];
    }
    // only check if the login screen has to be shown if there are no active chats
    if(self.unpinnedContacts.count == 0 && self.pinnedContacts.count == 0)
    {
        [self segueToIntroScreensIfNeeded];
    }
}

-(void) viewDidAppear:(BOOL) animated
{
    [super viewDidAppear:animated];
    
    for(NSDictionary* accountDict in [[DataLayer sharedInstance] enabledAccountList])
    {
        NSString* accountNo = [NSString stringWithFormat:@"%@", accountDict[kAccountID]];
        xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:accountNo];
        if(!account)
            @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Connected xmpp* object for accountNo is nil!" userInfo:accountDict];
        if(![_mamWarningDisplayed containsObject:accountNo] && account.accountState >= kStateBound && account.connectionProperties.accountDiscoDone)
        {
            if(!account.connectionProperties.supportsMam2)
            {
                UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Account %@", @""), account.connectionProperties.identity.jid] message:NSLocalizedString(@"Your server does not support MAM (XEP-0313). That means you could frequently miss incoming messages!! You should switch your server or talk to the server admin to enable this!", @"") preferredStyle:UIAlertControllerStyleAlert];
                [messageAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                    [_mamWarningDisplayed addObject:accountNo];
                }]];
                [self presentViewController:messageAlert animated:YES completion:nil];
            }
            else
                [_mamWarningDisplayed addObject:accountNo];
        }
        if(![_smacksWarningDisplayed containsObject:accountNo] && account.accountState >= kStateBound)
        {
            if(!account.connectionProperties.supportsSM3)
            {
                UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Account %@", @""), account.connectionProperties.identity.jid] message:NSLocalizedString(@"Your server does not support Stream Management (XEP-0198). That means your outgoing messages can get lost frequently!! You should switch your server or talk to the server admin to enable this!", @"") preferredStyle:UIAlertControllerStyleAlert];
                [messageAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                    [_smacksWarningDisplayed addObject:accountNo];
                }]];
                [self presentViewController:messageAlert animated:YES completion:nil];
            }
            else
                [_smacksWarningDisplayed addObject:accountNo];
        }
    }
}

-(void) segueToIntroScreensIfNeeded
{
    if(![[HelperTools defaultsDB] boolForKey:@"HasSeenIntro"]) {
        [self performSegueWithIdentifier:@"showIntro" sender:self];
        return;
    }
    // display quick start if the user never seen it or if there are 0 enabled accounts
    if(![[HelperTools defaultsDB] boolForKey:@"HasSeenLogin"] || [[DataLayer sharedInstance] enabledAccountCnts].intValue == 0) {
        [self performSegueWithIdentifier:@"showLogin" sender:self];
    }
    if(![[HelperTools defaultsDB] boolForKey:@"HasSeenPrivacySettings"]) {
        [self performSegueWithIdentifier:@"showPrivacySettings" sender:self];
        return;
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
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"No enabled account found", @"") message:NSLocalizedString(@"Please add a new account under settings first. If you already added your account you may need to enable it under settings", @"") preferredStyle:UIAlertControllerStyleAlert];
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
    DDLogInfo(@"Got segue identifier '%@'", segue.identifier);
    if([segue.identifier isEqualToString:@"showIntro"])
    {
        // needed for >= ios13
        if(@available(iOS 13.0, *))
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
    MLContactCell* cell = (MLContactCell*)[tableView dequeueReusableCellWithIdentifier:@"ContactCell" forIndexPath:indexPath];

    MLContact* chatContact = nil;
    // Select correct contact array
    if(indexPath.section == pinnedChats) {
        chatContact = [self.pinnedContacts objectAtIndex:indexPath.row];
        // mark pinned chats
        [cell setPinned:YES];
    } else {
        chatContact = [self.unpinnedContacts objectAtIndex:indexPath.row];
        [cell setPinned:NO];
    }
    [cell showDisplayName:chatContact.contactDisplayName];
    
    cell.accountNo = chatContact.accountId.integerValue;
    cell.username = chatContact.contactJid;
    NSNumber* unreadMsgCnt = [[DataLayer sharedInstance] countUserUnreadMessages:chatContact.contactJid forAccount:chatContact.accountId];
    cell.count = [unreadMsgCnt integerValue];
    
    // Display msg draft or last msg
    MLMessage* messageRow = [[DataLayer sharedInstance] lastMessageForContact:cell.username forAccount:chatContact.accountId];
    if(messageRow)
    {
        if([messageRow.messageType isEqualToString:kMessageTypeUrl] && [[HelperTools defaultsDB] boolForKey:@"ShowURLPreview"])
            [cell showStatusText:NSLocalizedString(@"🔗 A Link", @"")];
        else if([messageRow.messageType isEqualToString:kMessageTypeFiletransfer])
        {
            if([messageRow.filetransferMimeType hasPrefix:@"image/"])
                [cell showStatusText:NSLocalizedString(@"📷 An Image", @"")];
            else        //TODO JIM: add support for more mime types
                [cell showStatusText:NSLocalizedString(@"📁 A File", @"")];
        }
        else if ([messageRow.messageType isEqualToString:kMessageTypeMessageDraft])
        {
            NSString* draftPreview = [NSString stringWithFormat:NSLocalizedString(@"Draft: %@", @""), messageRow.messageText];
            [cell showStatusTextItalic:draftPreview withItalicRange:NSMakeRange(0, 6)];
        }
        else if([messageRow.messageType isEqualToString:kMessageTypeGeo])
            [cell showStatusText:NSLocalizedString(@"📍 A Location", @"")];
        else
        {
            NSString* displayName;
            xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:chatContact.accountId];
            if([messageRow.actualFrom isEqualToString:account.connectionProperties.identity.jid])
                displayName = [MLContact ownDisplayNameForAccount:account];
            else
                displayName = [chatContact contactDisplayName];
            if([messageRow.messageText hasPrefix:@"/me "])
            {
                NSString* replacedMessageText = [[MLXEPSlashMeHandler sharedInstance] stringSlashMeWithAccountId:chatContact.accountId
                                                                                                     displayName:displayName
                                                                                                      actualFrom:messageRow.actualFrom
                                                                                                         message:messageRow.messageText
                                                                                                         isGroup:chatContact.isGroup];

                NSRange replacedMsgAttrRange = NSMakeRange(0, replacedMessageText.length);

                [cell showStatusTextItalic:replacedMessageText withItalicRange:replacedMsgAttrRange];
            }
            else
            {
                [cell showStatusText:messageRow.messageText];
            }
        }
        if(messageRow.timestamp)
        {
            cell.time.text = [self formattedDateWithSource:messageRow.timestamp];
            cell.time.hidden = NO;
        }
        else
            cell.time.hidden = YES;
    }
    else
    {
        [cell showStatusText:nil];
        DDLogWarn(@"Active chat but no messages found in history for %@.", chatContact.contactJid);
    }
    [[MLImageManager sharedInstance] getIconForContact:chatContact.contactJid andAccount:chatContact.accountId withCompletion:^(UIImage *image) {
        cell.userImage.image = image;
    }];
    BOOL muted = [[DataLayer sharedInstance] isMutedJid:chatContact.contactJid];
    cell.muteBadge.hidden = !muted;
    return cell;
}


#pragma mark - tableview delegate

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 60.0f;
}


-(NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return NSLocalizedString(@"Archive chat", @"");
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
        [self refreshDisplay];
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
    BOOL toreturn = (self.unpinnedContacts.count == 0 && self.pinnedContacts == 0) ? YES : NO;
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
