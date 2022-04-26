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
#import "MLRegisterViewController.h"
#import "ContactsViewController.h"
#import "MLNewViewController.h"
#import "MLXEPSlashMeHandler.h"
#import "MLNotificationQueue.h"
#import "MLSettingsAboutViewController.h"

@import QuartzCore.CATransaction;

@interface ActiveChatsViewController()
@property (atomic, strong) NSMutableArray* unpinnedContacts;
@property (atomic, strong) NSMutableArray* pinnedContacts;
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
-(id) initWithNibName:(NSString*) nibNameOrNil bundle:(NSBundle*) nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

-(void) viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor=[UIColor lightGrayColor];
    self.view.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    
    MonalAppDelegate* appDelegate = (MonalAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appDelegate setActiveChatsController:self];
    
     self.chatListTable = [[UITableView alloc] init];
     self.chatListTable.delegate = self;
     self.chatListTable.dataSource = self;
    
    self.view = self.chatListTable;
    
    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(handleRefreshDisplayNotification:) name:kMonalRefresh object:nil];
    [nc addObserver:self selector:@selector(handleContactRemoved:) name:kMonalContactRemoved object:nil];
    [nc addObserver:self selector:@selector(handleRefreshDisplayNotification:) name:kMonalMessageFiletransferUpdateNotice object:nil];
    [nc addObserver:self selector:@selector(refreshContact:) name:kMonalContactRefresh object:nil];
    [nc addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    [nc addObserver:self selector:@selector(handleNewMessage:) name:kMonalDeletedMessageNotice object:nil];
    [nc addObserver:self selector:@selector(messageSent:) name:kMLMessageSentToContact object:nil];
    [nc addObserver:self selector:@selector(handleBackgroundChanged) name:kMonalBackgroundChanged object:nil];
    
    [_chatListTable registerNib:[UINib nibWithNibName:@"MLContactCell" bundle:[NSBundle mainBundle]] forCellReuseIdentifier:@"ContactCell"];
    
    self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
#if !TARGET_OS_MACCATALYST
    self.splitViewController.primaryBackgroundStyle = UISplitViewControllerBackgroundStyleSidebar;
#endif
    self.settingsButton.image = [UIImage systemImageNamed:@"gearshape.fill"];
    self.composeButton.image = [UIImage systemImageNamed:@"person.2.fill"];
    
    self.chatListTable.emptyDataSetSource = self;
    self.chatListTable.emptyDataSetDelegate = self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
            for(int i = 0; i < diff; i++)
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
        [CATransaction begin];
        [UIView performWithoutAnimation:^{
            [self.chatListTable beginUpdates];
            resizeSections(self.chatListTable, unpinnedChats, unpinnedCntDiff);
            resizeSections(self.chatListTable, pinnedChats, pinnedCntDiff);
            self.unpinnedContacts = newUnpinnedContacts;
            self.pinnedContacts = newPinnedContacts;
            [self.chatListTable reloadSections:[NSIndexSet indexSetWithIndex:pinnedChats] withRowAnimation:UITableViewRowAnimationNone];
            [self.chatListTable reloadSections:[NSIndexSet indexSetWithIndex:unpinnedChats] withRowAnimation:UITableViewRowAnimationNone];
            [self.chatListTable endUpdates];
        }];
        [CATransaction commit];

        MonalAppDelegate* appDelegate = (MonalAppDelegate*)[UIApplication sharedApplication].delegate;
        [appDelegate updateUnread];
    });
}

-(void) refreshContact:(NSNotification*) notification
{
    MLContact* contact = [notification.userInfo objectForKey:@"contact"];
    DDLogInfo(@"Refreshing contact %@ at %@: unread=%lu", contact.contactJid, contact.accountId, (unsigned long)contact.unreadCount);
    
    // if pinning changed we have to move the user to a other section
    if([notification.userInfo objectForKey:@"pinningChanged"])
        [self insertOrMoveContact:contact completion:nil];
    else
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSIndexPath* indexPath = nil;
            for(size_t section = pinnedChats; section < activeChatsViewControllerSectionCnt && !indexPath; section++)
            {
                NSMutableArray* curContactArray = [self getChatArrayForSection:section];
                // check if contact is already displayed -> get coresponding indexPath
                NSUInteger rowIdx = 0;
                for(MLContact* rowContact in curContactArray)
                {
                    if([rowContact isEqualToContact:contact])
                    {
                        //this MLContact instance is used in various ui parts, not just this file --> update all properties but keep the instance intact
                        [rowContact updateWithContact:contact];
                        indexPath = [NSIndexPath indexPathForRow:rowIdx inSection:section];
                        break;
                    }
                    rowIdx++;
                }
            }
            // reload contact entry if we found it
            if(indexPath)
            {
                    DDLogDebug(@"Reloading row at %@", indexPath);
                    [self.chatListTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            }
        });
    }
}

-(void) handleRefreshDisplayNotification:(NSNotification*) notification
{
    // filter notifcations from within this class
    if([notification.object isKindOfClass:[ActiveChatsViewController class]])
    {
        return;
    }
    [self refreshDisplay];
}

-(void) handleContactRemoved:(NSNotification*) notification
{
    MLContact* removedContact = [notification.userInfo objectForKey:@"contact"];
    if(removedContact == nil)
    {
        unreachable();
    }
    // ignore all removals that aren't in foreground
    if([removedContact isEqualToContact:[MLNotificationManager sharedInstance].currentContact] == NO)
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        DDLogInfo(@"Contact removed, closing chat view...");
        // remove contact from activechats table
        [self refreshDisplay];
        // open placeholder
        [self presentChatWithContact:nil];
    });
}


-(void) messageSent:(NSNotification*) notification
{
    MLContact* contact = [notification.userInfo objectForKey:@"contact"];
    if(!contact)
        unreachable();
    [self insertOrMoveContact:contact completion:nil];
}

-(void) handleNewMessage:(NSNotification*) notification
{
    MLMessage* newMessage = notification.userInfo[@"message"];
    MLContact* contact = notification.userInfo[@"contact"];
    xmpp* msgAccount = (xmpp*)notification.object;
    if(!newMessage || !contact || !msgAccount)
    {
        unreachable();
        return;
    }
    if([newMessage.messageType isEqualToString:kMessageTypeStatus])
        return;

    // contact.statusMessage = newMessage;
    [self insertOrMoveContact:contact completion:nil];
}

// the chat background image is cached in the MLImageManager
// on iphones all background change event will miss the chatView -> reset the image here
-(void) handleBackgroundChanged
{
    [[MLImageManager sharedInstance] resetBackgroundImage];
}

-(void) insertOrMoveContact:(MLContact*) contact completion:(void (^ _Nullable)(BOOL finished)) completion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.chatListTable performBatchUpdates:^{
            __block NSIndexPath* indexPath = nil;
            for(size_t section = pinnedChats; section < activeChatsViewControllerSectionCnt && !indexPath; section++) {
                NSMutableArray* curContactArray = [self getChatArrayForSection:section];

                // check if contact is already displayed -> get coresponding indexPath
                [curContactArray enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    MLContact* rowContact = (MLContact *) obj;
                    if([rowContact isEqualToContact:contact])
                    {
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

            if(indexPath && insertAtPath.section == indexPath.section && insertAtPath.row == indexPath.row)
            {
                [insertContactToArray replaceObjectAtIndex:insertAtPath.row  withObject:contact];
                [self.chatListTable reloadRowsAtIndexPaths:@[insertAtPath] withRowAnimation:UITableViewRowAnimationNone];
                return;
            }
            else if(indexPath)
            {
                // Contact is already in our active chats list
                NSMutableArray* removeContactFromArray = [self getChatArrayForSection:indexPath.section];
                [self.chatListTable deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                [removeContactFromArray removeObjectAtIndex:indexPath.row];
                [insertContactToArray insertObject:contact atIndex:0];
                [self.chatListTable insertRowsAtIndexPaths:@[insertAtPath] withRowAnimation:UITableViewRowAnimationNone];
            }
            else {
                // Chats does not exists in active Chats yet
                [insertContactToArray insertObject:contact atIndex:0];
                [self.chatListTable insertRowsAtIndexPaths:@[insertAtPath] withRowAnimation:UITableViewRowAnimationRight];
            }
        } completion:^(BOOL finished) {
            if(completion) completion(finished);
        }];
    });
}

-(void) viewWillAppear:(BOOL) animated
{
    DDLogDebug(@"active chats view will appear");
    [super viewWillAppear:animated];
    if(self.unpinnedContacts.count == 0 && self.pinnedContacts.count == 0)
        [self refreshDisplay];      // load contacts
    // only check if the login screens have been shown if there are no active chats
    [self segueToIntroScreensIfNeeded];
}

-(void) viewWillDisappear:(BOOL) animated
{
    DDLogDebug(@"active chats view will disappear");
    [super viewWillDisappear:animated];
}

-(void) viewDidAppear:(BOOL) animated
{
    DDLogDebug(@"active chats view did appear");
    [super viewDidAppear:animated];
    
    for(NSDictionary* accountDict in [[DataLayer sharedInstance] enabledAccountList])
    {
        NSNumber* accountNo = accountDict[kAccountID];
        xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:accountNo];
        if(!account)
            @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Connected xmpp* object for accountNo is nil!" userInfo:accountDict];
        if(![_mamWarningDisplayed containsObject:accountNo] && account.accountState >= kStateBound && account.connectionProperties.accountDiscoDone)
        {
            if(!account.connectionProperties.supportsMam2)
            {
                UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Account %@", @""), account.connectionProperties.identity.jid] message:NSLocalizedString(@"Your server does not support MAM (XEP-0313). That means you could frequently miss incoming messages!! You should switch your server or talk to the server admin to enable this!", @"") preferredStyle:UIAlertControllerStyleAlert];
                [messageAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
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
                [messageAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
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
    // display quick start if the user never seen it or if there are 0 enabled accounts
    if(![[HelperTools defaultsDB] boolForKey:@"HasSeenLogin"] || [[DataLayer sharedInstance] enabledAccountCnts].intValue == 0) {
        [self performSegueWithIdentifier:@"showLogin" sender:self];
        return;
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

-(void) openConversationPlaceholder:(MLContact*) contact
{
    // only show placeholder if we use a split view
    if([HelperTools deviceUsesSplitView] == YES)
        [self performSegueWithIdentifier:@"showConversationPlaceholder" sender:contact];
}

-(void) showPrivacySettings
{
    [self performSegueWithIdentifier:@"showPrivacySettings" sender:self];
}

-(void) showSettings
{
   [self performSegueWithIdentifier:@"showSettings" sender:self];
}

-(void) presentChatWithContact:(MLContact*) contact
{
    // clear old chat before opening a new one (but not for splitView == YES)
    if([HelperTools deviceUsesSplitView] == NO)
        [self.navigationController popViewControllerAnimated:NO];
    
    // show placeholder if contact is nil, open chat otherwise
    if(contact == nil)
    {
        [self openConversationPlaceholder:contact];
        return;
    }
    // check if the contact is a buddy
    if([[DataLayer sharedInstance] isContactInList:contact.contactJid forAccount:contact.accountId] == NO)
    {
        DDLogError(@"Contact %@ unkown", contact.contactJid);
        [self openConversationPlaceholder:contact];
        return;
    }
    // only open contact chat when it is not opened yet (needed for opening via notifications and for macOS)
    if([contact isEqualToContact:[MLNotificationManager sharedInstance].currentContact])
    {
        // make sure the already open chat is reloaded and return
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:self userInfo:nil];
        return;
    }

    // open chat
    [self performSegueWithIdentifier:@"showConversation" sender:contact];
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
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction* action __unused) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return YES;
    }
    return NO;
}

-(BOOL) shouldPerformSegueWithIdentifier:(NSString*) identifier sender:(id) sender
{
    if([identifier isEqualToString:@"showDetails"])
    {
        //don't show contact details for mucs (they will get their own muc details later on)
        if(((MLContact*)sender).isGroup)
            return NO;
    }
    return YES;
}

//this is needed to prevent segues invoked programmatically
-(void) performSegueWithIdentifier:(NSString*) identifier sender:(id) sender
{
    if([self shouldPerformSegueWithIdentifier:identifier sender:sender] == NO)
    {
        if([identifier isEqualToString:@"showDetails"])
        {
            // Display warning
            UIAlertController* groupDetailsWarning = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Groupchat/channel details", @"")
                                                                                message:NSLocalizedString(@"Groupchat/channel details are currently not implemented in Monal.", @"") preferredStyle:UIAlertControllerStyleAlert];
            [groupDetailsWarning addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
                [groupDetailsWarning dismissViewControllerAnimated:YES completion:nil];
            }]];
            [self presentViewController:groupDetailsWarning animated:YES completion:nil];
        }
        return;
    }
    [super performSegueWithIdentifier:identifier sender:sender];
}

-(void) prepareForSegue:(UIStoryboardSegue*) segue sender:(id) sender
{
    DDLogInfo(@"Got segue identifier '%@'", segue.identifier);
    if([segue.identifier isEqualToString:@"showRegister"])
    {
        UINavigationController* navigationController = (UINavigationController*)segue.destinationViewController;
        MLRegisterViewController* reg = (MLRegisterViewController*)navigationController.visibleViewController;
        NSDictionary* registerData = (NSDictionary*)sender;
        if(registerData)
        {
            DDLogDebug(@"Feeding MLRegisterViewController withdata: %@", registerData);
            reg.registerServer = nilExtractor(registerData[@"host"]);
            reg.registerUsername = nilExtractor(registerData[@"username"]);
            reg.registerToken = nilExtractor(registerData[@"token"]);
            reg.completionHandler = nilExtractor(registerData[@"completion"]);
        }
    }
    else if([segue.identifier isEqualToString:@"showConversation"])
    {
        UINavigationController* nav = segue.destinationViewController;
        chatViewController* chatVC = (chatViewController*)nav.topViewController;
        UIBarButtonItem* barButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];
        self.navigationItem.backBarButtonItem = barButtonItem;
        [chatVC setupWithContact:sender];
    }
    else if([segue.identifier isEqualToString:@"showDetails"])
    {
        UINavigationController* nav = segue.destinationViewController;
        ContactDetails* details = (ContactDetails*)nav.topViewController;
        details.contact = sender;
    }
    else if([segue.identifier isEqualToString:@"showContacts"])
    {
        // Only segue if at least one account is enabled
        if([self showAccountNumberWarningIfNeeded]) {
            return;
        }

        UINavigationController* nav = segue.destinationViewController;
        ContactsViewController* contacts = (ContactsViewController*)nav.topViewController;
        contacts.selectContact = ^(MLContact* selectedContact) {
            [[DataLayer sharedInstance] addActiveBuddies:selectedContact.contactJid forAccount:selectedContact.accountId];
            //no success may mean its already there
            [self insertOrMoveContact:selectedContact completion:^(BOOL finished __unused) {
                size_t sectionToUse = unpinnedChats; // Default is not pinned
                if(selectedContact.isPinned) {
                    sectionToUse = pinnedChats; // Insert in pinned section
                }
                NSIndexPath* path = [NSIndexPath indexPathForRow:0 inSection:sectionToUse];
                [self.chatListTable selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
                [self presentChatWithContact:selectedContact];
            }];
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
    } else {
        chatContact = [self.unpinnedContacts objectAtIndex:indexPath.row];
    }
    // Display msg draft or last msg
    MLMessage* messageRow = [[DataLayer sharedInstance] lastMessageForContact:chatContact.contactJid forAccount:chatContact.accountId];

    [cell initCell:chatContact withLastMessage:messageRow];

    return cell;
}


#pragma mark - tableview delegate

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 60.0f;
}


-(NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
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

-(void) tableView:(UITableView*) tableView didSelectRowAtIndexPath:(NSIndexPath*) indexPath
{
    MLContact* selected = nil;
    if(indexPath.section == pinnedChats) {
        selected = self.pinnedContacts[indexPath.row];
    } else {
        selected = self.unpinnedContacts[indexPath.row];
    }
    [self presentChatWithContact:selected];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary* contactDic = [self.unpinnedContacts objectAtIndex:indexPath.row];

    [self performSegueWithIdentifier:@"showDetails" sender:contactDic];
}


#pragma mark - empty data set

- (UIImage*)imageForEmptyDataSet:(UIScrollView*)scrollView
{
    return nil;
}

- (NSAttributedString *)titleForEmptyDataSet:(UIScrollView *) scrollView
{
    NSString* text = NSLocalizedString(@"No one is here", @"");
    
    NSDictionary* attributes = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:18.0f],
                                 NSForegroundColorAttributeName: [UIColor darkGrayColor]};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (NSAttributedString*)descriptionForEmptyDataSet:(UIScrollView*) scrollView
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

#pragma mark - mac menu

-(void) showContacts
{
    // Only segue if at least one account is enabled
    if([self showAccountNumberWarningIfNeeded])
        return;
    [self performSegueWithIdentifier:@"showContacts" sender:self];
}

-(void) showRegisterWithUsername:(NSString*) username onHost:(NSString*) host withToken:(NSString*) token usingCompletion:(monal_void_block_t) completion
{
    MonalAppDelegate* appDelegate = (MonalAppDelegate *)[[UIApplication sharedApplication] delegate];
    [appDelegate.window.rootViewController dismissViewControllerAnimated:YES completion:^{
        [self performSegueWithIdentifier:@"showRegister" sender:@{
            @"host": nilWrapper(host),
            @"username": nilWrapper(username),
            @"token": nilWrapper(token),
            @"completion": nilDefault(completion, ^{}),
        }];
        completion();
    }];
}

-(void) showDetails
{
    if([MLNotificationManager sharedInstance].currentContact != nil)
        [self performSegueWithIdentifier:@"showDetails" sender:[MLNotificationManager sharedInstance].currentContact];
}

-(void) deleteConversation
{
    for(size_t section = pinnedChats; section < activeChatsViewControllerSectionCnt; section++)
    {
        NSMutableArray* curContactArray = [self getChatArrayForSection:section];
        // check if contact is already displayed -> get coresponding indexPath
        [curContactArray enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop __unused) {
            MLContact* rowContact = (MLContact*)obj;
            if([rowContact isEqualToContact:[MLNotificationManager sharedInstance].currentContact])
            {
                [self tableView:self.chatListTable commitEditingStyle:UITableViewCellEditingStyleDelete forRowAtIndexPath:[NSIndexPath indexPathForRow:idx inSection:section]];
                return;
            }
        }];
    }
}

@end
