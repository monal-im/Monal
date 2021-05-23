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

@import QuartzCore.CATransaction;

@interface ActiveChatsViewController ()

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
    
    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(refreshDisplay) name:kMonalRefresh object:nil];
    [nc addObserver:self selector:@selector(handleContactRemoved:) name:kMonalContactRemoved object:nil];
    [nc addObserver:self selector:@selector(refreshDisplay) name:kMonalMessageFiletransferUpdateNotice object:nil];
    [nc addObserver:self selector:@selector(refreshContact:) name:kMonalContactRefresh object:nil];
    [nc addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    [nc addObserver:self selector:@selector(handleNewMessage:) name:kMonalDeletedMessageNotice object:nil];
    [nc addObserver:self selector:@selector(messageSent:) name:kMLMessageSentToContact object:nil];
    
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
        self.composeButton.image = [UIImage systemImageNamed:@"person.2.fill"];
    }
    else
    {
        self.settingsButton.image = [UIImage imageNamed:@"973-user"];
        self.composeButton.image = [UIImage imageNamed:@"704-compose"];
    }
    
    self.chatListTable.emptyDataSetSource = self;
    self.chatListTable.emptyDataSetDelegate = self;
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

-(void) handleContactRemoved:(NSNotification*) notification
{
    MLContact* removedContact = [notification.userInfo objectForKey:@"contact"];
    if(removedContact == nil)
    {
        unreachable();
    }
    // ignore all removals that aren't in foreground
    if([self.lastSelectedUser.accountId isEqualToString:removedContact.accountId] == NO || [self.lastSelectedUser.contactJid isEqualToString:removedContact.contactJid] == NO)
        return;
    // remove contact from activechats table
    [self refreshDisplay];
    // open placeholder
    [self presentChatWithContact:nil];
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
    MLMessage* newMessage = notification.userInfo[@"message"];
    MLContact* contact = notification.userInfo[@"contact"];
    xmpp* msgAccount = (xmpp*)notification.object;
    if(!msgAccount)
        return;
    if([newMessage.messageType isEqualToString:kMessageTypeStatus])
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
    // reset account selection on non split view systems
    if([HelperTools deviceUsesSplitView] == NO)
       self.lastSelectedUser = nil;
    // load contacts
    if(self.unpinnedContacts.count == 0 && self.pinnedContacts.count == 0)
    {
        [self refreshDisplay];
        // only check if the login screen has to be shown if there are no active chats
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

-(void) presentChatWithContact:(MLContact*) contact
{
    if(contact == nil)
    {
        // show placeholder
        [self performSegueWithIdentifier:@"showConversationPlaceholder" sender:contact];
    }
    else
    {
        // open chat
        [self performSegueWithIdentifier:@"showConversation" sender:contact];
    }
    self.lastSelectedUser = contact;
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
            [groupDetailsWarning addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                [groupDetailsWarning dismissViewControllerAnimated:YES completion:nil];
            }]];
            [self presentViewController:groupDetailsWarning animated:YES completion:nil];
        }
        return;
    }
    [super performSegueWithIdentifier:identifier sender:sender];
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
                    [self presentChatWithContact:selectedContact];
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
    
    [self presentChatWithContact:selected];
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

#pragma mark -mac menu
-(void) showContacts {
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
