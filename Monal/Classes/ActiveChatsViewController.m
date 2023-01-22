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
#import "MLImageManager.h"
#import "ContactsViewController.h"
#import "MLXEPSlashMeHandler.h"
#import "MLNotificationQueue.h"
#import "MLSettingsAboutViewController.h"
#import "MLVoIPProcessor.h"
#import "UIColor+Theme.h"
#import <Monal-Swift.h>

@import QuartzCore.CATransaction;

@interface DZNEmptyDataSetView
@property (atomic, strong) UIView* contentView;
@property (atomic, strong) UIImageView* imageView;
@property (atomic, strong) UILabel* titleLabel;
@property (atomic, strong) UILabel* detailLabel;
@end

@interface UIScrollView () <UIGestureRecognizerDelegate>
@property (nonatomic, readonly) DZNEmptyDataSetView* emptyDataSetView;
@end

@interface ActiveChatsViewController() {
    int _startedOrientation;
    double _portraitTop;
    double _landscapeTop;
}
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
    return self;
}

-(void) configureComposeButton
{
    UIImage* composeImage = [[UIImage systemImageNamed:@"person.2.fill"] imageWithTintColor:UIColor.monalGreen];
    UITapGestureRecognizer* composeTapRecoginzer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showContacts:)];
    self.composeButton.customView = [HelperTools
                                    buttonWithNotificationBadgeForImage:composeImage
                                    hasNotification:[[DataLayer sharedInstance] allContactRequests].count > 0
                                    withTapHandler:composeTapRecoginzer];
}

-(void) viewDidLoad
{
    [super viewDidLoad];
    
    _startedOrientation = 0;
    
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    
    self.view.backgroundColor=[UIColor lightGrayColor];
    self.view.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    
    MonalAppDelegate* appDelegate = (MonalAppDelegate*)[[UIApplication sharedApplication] delegate];
    appDelegate.activeChats = self;
    
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
    [nc addObserver:self selector:@selector(handleDeviceRotation) name:UIDeviceOrientationDidChangeNotification object:nil];
    
    [_chatListTable registerNib:[UINib nibWithNibName:@"MLContactCell" bundle:[NSBundle mainBundle]] forCellReuseIdentifier:@"ContactCell"];
    
    self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
#if !TARGET_OS_MACCATALYST
    self.splitViewController.primaryBackgroundStyle = UISplitViewControllerBackgroundStyleSidebar;
#endif
    self.settingsButton.image = [UIImage systemImageNamed:@"gearshape.fill"];
    [self configureComposeButton];

    UIBarButtonItem* spinnerButton = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
    [self.navigationItem setRightBarButtonItems:@[self.composeButton, spinnerButton] animated:NO];
    
    self.chatListTable.emptyDataSetSource = self;
    self.chatListTable.emptyDataSetDelegate = self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) handleDeviceRotation
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self imageForEmptyDataSet:nil];
        [self.chatListTable setNeedsDisplay];
    });
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
        //make sure we don't display a chat view for a disabled account
        if(self.currentChatViewController != nil && self.currentChatViewController.contact != nil)
        {
            BOOL found = NO;
            for(NSDictionary* accountDict in [[DataLayer sharedInstance] enabledAccountList])
            {
                NSNumber* accountNo = accountDict[kAccountID];
                if(self.currentChatViewController.contact.accountId.intValue == accountNo.intValue)
                    found = YES;
            }
            if(!found)
                [self presentChatWithContact:nil];
        }
        
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
        [self.chatListTable reloadEmptyDataSet];

        MonalAppDelegate* appDelegate = (MonalAppDelegate*)[UIApplication sharedApplication].delegate;
        [appDelegate updateUnread];
    });
}

-(void) refreshContact:(NSNotification*) notification
{
    MLContact* contact = [notification.userInfo objectForKey:@"contact"];
    DDLogInfo(@"Refreshing contact %@ at %@: unread=%lu", contact.contactJid, contact.accountId, (unsigned long)contact.unreadCount);
    
    //update red dot
    dispatch_async(dispatch_get_main_queue(), ^{
        [self configureComposeButton];
    });
    
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
            [self.chatListTable reloadEmptyDataSet];
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
    
    //update red dot
    dispatch_async(dispatch_get_main_queue(), ^{
        [self configureComposeButton];
    });
    
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

-(void) didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void) showAddContactWithJid:(NSString*) jid andPreauthToken:(NSString* _Nullable) preauthToken
{
    UIViewController* addContactMenuView = [[SwiftuiInterface new] makeAddContactViewForJid:jid andPreauthToken:preauthToken withDismisser:^(MLContact* _Nonnull newContact) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentChatWithContact:newContact];
        });
    }];
    [self presentViewController:addContactMenuView animated:YES completion:^{}];
}

-(void) segueToIntroScreensIfNeeded
{
    //open password migration if needed
    NSArray* needingMigration = [[DataLayer sharedInstance] accountListNeedingPasswordMigration];
    if(needingMigration.count > 0)
    {
        UIViewController* passwordMigration = [[SwiftuiInterface new] makePasswordMigration:needingMigration];
        [self presentViewController:passwordMigration animated:YES completion:^{}];
        return;
    }
    // display quick start if the user never seen it or if there are 0 enabled accounts
    if([[DataLayer sharedInstance] enabledAccountCnts].intValue == 0)
    {
        UIViewController* loginViewController = [[SwiftuiInterface new] makeViewWithName:@"WelcomeLogIn"];
        [self presentViewController:loginViewController animated:YES completion:^{}];
        return;
    }
    if(![[HelperTools defaultsDB] boolForKey:@"HasSeenPrivacySettings"])
    {
        [self performSegueWithIdentifier:@"showPrivacySettings" sender:self];
        return;
    }
}

-(void) openConversationPlaceholder:(MLContact*) contact
{
    // only show placeholder if we use a split view
    if([HelperTools deviceUsesSplitView] == YES)
    {
        DDLogVerbose(@"Presenting Chat Placeholder...");
        UIViewController* detailsViewController = [[SwiftuiInterface new] makeViewWithName:@"ChatPlaceholder"];
        [self showDetailViewController:detailsViewController sender:self];
    }
}

-(void) showPrivacySettings
{
    [self performSegueWithIdentifier:@"showPrivacySettings" sender:self];
}

-(void) showSettings
{
   [self performSegueWithIdentifier:@"showSettings" sender:self];
}

-(void) callContact:(MLContact*) contact
{
    MonalAppDelegate* appDelegate = (MonalAppDelegate *)[[UIApplication sharedApplication] delegate];
    MLCall* activeCall = [appDelegate.voipProcessor getActiveCallWithContact:contact];
    if(activeCall != nil)
        [self presentCall:activeCall];
    else
        [self presentCall:[appDelegate.voipProcessor initiateAudioCallToContact:contact]];
}

-(void) presentAccountPickerForContacts:(NSArray<MLContact*>*) contacts
{
    MonalAppDelegate* appDelegate = (MonalAppDelegate *)[[UIApplication sharedApplication] delegate];
    [[appDelegate getTopViewController] dismissViewControllerAnimated:NO completion:^{
        UIViewController* accountPickerController = [[SwiftuiInterface new] makeAccountPickerForContacts:contacts];;
        [self presentViewController:accountPickerController animated:YES completion:^{}];
    }];
}

-(void) presentCall:(MLCall*) call
{
    MonalAppDelegate* appDelegate = (MonalAppDelegate *)[[UIApplication sharedApplication] delegate];
    [[appDelegate getTopViewController] dismissViewControllerAnimated:NO completion:^{
        UIViewController* callViewController = [[SwiftuiInterface new] makeCallScreenForCall:call];
        callViewController.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:callViewController animated:NO completion:^{}];
    }];
}

-(void) presentChatWithContact:(MLContact*) contact
{
    return [self presentChatWithContact:contact andCompletion:nil];
}

-(void) presentChatWithContact:(MLContact*) contact andCompletion:(monal_id_block_t _Nullable) completion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        DDLogVerbose(@"presenting chat with contact: %@", contact);
        MonalAppDelegate* appDelegate = (MonalAppDelegate *)[[UIApplication sharedApplication] delegate];
        [[appDelegate getTopViewController] dismissViewControllerAnimated:YES completion:^{
            // only open contact chat when it is not opened yet (needed for opening via notifications and for macOS)
            if([contact isEqualToContact:[MLNotificationManager sharedInstance].currentContact])
            {
                // make sure the already open chat is reloaded and return
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:nil userInfo:nil];
                if(completion != nil)
                    completion(@YES);
                return;
            }
            
            // clear old chat before opening a new one (but not for splitView == YES)
            if([HelperTools deviceUsesSplitView] == NO)
                [self.navigationController popViewControllerAnimated:NO];
            
            // show placeholder if contact is nil, open chat otherwise
            if(contact == nil)
            {
                [self openConversationPlaceholder:nil];
                if(completion != nil)
                    completion(@NO);
                return;
            }

            //open chat (make sure we have an active buddy for it and add it to our ui, if needed)
            //but don't animate this if the contact is already present in our list
            [[DataLayer sharedInstance] addActiveBuddies:contact.contactJid forAccount:contact.accountId];
            if([[self getChatArrayForSection:pinnedChats] containsObject:contact] || [[self getChatArrayForSection:unpinnedChats] containsObject:contact])
            {
                [self performSegueWithIdentifier:@"showConversation" sender:contact];
                if(completion != nil)
                    completion(@YES);
            }
            else
                [self insertOrMoveContact:contact completion:^(BOOL finished __unused) {
                    [self performSegueWithIdentifier:@"showConversation" sender:contact];
                    if(completion != nil)
                        completion(@YES);
                }];
        }];
    });
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
    return YES;
}

//this is needed to prevent segues invoked programmatically
-(void) performSegueWithIdentifier:(NSString*) identifier sender:(id) sender
{
    [super performSegueWithIdentifier:identifier sender:sender];
}

-(void) prepareForSegue:(UIStoryboardSegue*) segue sender:(id) sender
{
    DDLogInfo(@"Got segue identifier '%@'", segue.identifier);
    if([segue.identifier isEqualToString:@"showConversation"])
    {
        UINavigationController* nav = segue.destinationViewController;
        chatViewController* chatVC = (chatViewController*)nav.topViewController;
        UIBarButtonItem* barButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];
        self.navigationItem.backBarButtonItem = barButtonItem;
        [chatVC setupWithContact:sender];
        self.currentChatViewController = chatVC;
    }
    else if([segue.identifier isEqualToString:@"showDetails"])
    {
        UIViewController* detailsViewController = [[SwiftuiInterface new] makeContactDetails:sender];
        [self presentViewController:detailsViewController animated:YES completion:^{}];
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
            DDLogVerbose(@"Got selected contact from contactlist ui: %@", selectedContact);
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

-(CGFloat) tableView:(UITableView*) tableView heightForRowAtIndexPath:(NSIndexPath*) indexPath
{
    return 60.0f;
}

-(NSString*) tableView:(UITableView*) tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath*) indexPath
{
    return NSLocalizedString(@"Archive chat", @"");
}

-(BOOL) tableView:(UITableView*) tableView canEditRowAtIndexPath:(NSIndexPath*) indexPath
{
    return YES;
}

-(BOOL)tableView:(UITableView*) tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath*) indexPath
{
    return YES;
}

-(void)tableView:(UITableView*) tableView commitEditingStyle:(UITableViewCellEditingStyle) editingStyle forRowAtIndexPath:(NSIndexPath*) indexPath
{
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
        // remove contact from activechats table
        [self refreshDisplay];
        // open placeholder
        [self presentChatWithContact:nil];
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

-(void) tableView:(UITableView*) tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath*) indexPath
{
    MLContact* selected = nil;
    if(indexPath.section == pinnedChats) {
        selected = self.pinnedContacts[indexPath.row];
    } else {
        selected = self.unpinnedContacts[indexPath.row];
    }
    UIViewController* detailsViewController = [[SwiftuiInterface new] makeContactDetails:selected];
    [self presentViewController:detailsViewController animated:YES completion:^{}];
}


#pragma mark - empty data set

-(void) viewWillTransitionToSize:(CGSize) size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>) coordinator
{
    //DDLogError(@"Transitioning to size: %@", NSStringFromCGSize(size));
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}


-(UIImage*) imageForEmptyDataSet:(UIScrollView*) scrollView
{
    int orientation;
    if(self.tableView.frame.size.height > self.tableView.frame.size.width)
    {
        orientation = 1;        //portrait
        _portraitTop = self.navigationController.navigationBar.frame.size.height;
    }
    else
    {
        orientation = 2;        //landscape
        _landscapeTop = self.navigationController.navigationBar.frame.size.height;
    }
    if(_startedOrientation == 0)
        _startedOrientation = orientation;

    //DDLogError(@"started orientation: %@", _startedOrientation == 1 ? @"portrait" : @"landscape");
    //DDLogError(@"current orientation: %@", orientation == 1 ? @"portrait" : @"landscape");
    
    DZNEmptyDataSetView* emptyDataSetView = self.tableView.emptyDataSetView;
    CGRect headerFrame = self.navigationController.navigationBar.frame;
    CGRect tableFrame = self.tableView.frame;
    //CGRect contentFrame = emptyDataSetView.contentView.frame;
    //DDLogError(@"headerFrame: %@", NSStringFromCGRect(headerFrame));
    //DDLogError(@"tableFrame: %@", NSStringFromCGRect(tableFrame));
    //DDLogError(@"contentFrame: %@", NSStringFromCGRect(contentFrame));
    tableFrame.size.height *= 0.5;
    
    //started in landscape, moved to portrait
    if(_startedOrientation == 2 && orientation == 1)
    {
        tableFrame.origin.y += headerFrame.size.height - _landscapeTop - _portraitTop;
    }
    //started in portrait, moved to landscape
    else if(_startedOrientation == 1 && orientation == 2)
    {
        tableFrame.origin.y += (_portraitTop + _landscapeTop * 2);
        tableFrame.size.height -= _portraitTop;
    }
    //sarted in any orientation, moved to same orientation (or just started)
    else
    {
        tableFrame.origin.y += headerFrame.size.height;
    }
    
    emptyDataSetView.contentView.frame = tableFrame;
    emptyDataSetView.imageView.frame = tableFrame;
    [emptyDataSetView.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[imageView]-(32@750)-[titleLabel]-(16@750)-[detailLabel]|" options:0 metrics:nil views:@{
        @"imageView": emptyDataSetView.imageView,
        @"titleLabel": emptyDataSetView.titleLabel,
        @"detailLabel": emptyDataSetView.detailLabel,
    }]];
    emptyDataSetView.imageView.translatesAutoresizingMaskIntoConstraints = YES;
    if(self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark)
        return [UIImage imageNamed:@"chat_dark"];
    return [UIImage imageNamed:@"chat"];
    
    /*
    DZNEmptyDataSetView* emptyDataSetView = self.chatListTable.emptyDataSetView;
    CGRect headerFrame = self.navigationController.navigationBar.frame;
    CGRect tableFrame = self.chatListTable.frame;
    CGRect contentFrame = emptyDataSetView.contentView.frame;
    DDLogError(@"headerFrame: %@", NSStringFromCGRect(headerFrame));
    DDLogError(@"tableFrame: %@", NSStringFromCGRect(tableFrame));
    DDLogError(@"contentFrame: %@", NSStringFromCGRect(contentFrame));
    if(tableFrame.size.height > tableFrame.size.width)
    {
        DDLogError(@"height is bigger");
        tableFrame.size.height *= 0.5;
        tableFrame.origin.y += headerFrame.size.height;
    }
    else
    {
        DDLogError(@"width is bigger");
        tableFrame.size.height *= 2.0;
    }
    //tableFrame.size.height *= (tableFrame.size.width / tableFrame.size.height);
    emptyDataSetView.imageView.frame = tableFrame;
    emptyDataSetView.contentView.frame = tableFrame;
    [emptyDataSetView.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[imageView]-(48@750)-[titleLabel]-(16@750)-[detailLabel]|" options:0 metrics:nil views:@{
        @"imageView": emptyDataSetView.imageView,
        @"titleLabel": emptyDataSetView.titleLabel,
        @"detailLabel": emptyDataSetView.detailLabel,
    }]];
    emptyDataSetView.imageView.translatesAutoresizingMaskIntoConstraints = YES;
    return [UIImage imageNamed:@"chat"];
    */
}

-(CGFloat) spaceHeightForEmptyDataSet:(UIScrollView*) scrollView
{
    return 480.0f;
}

-(NSAttributedString*) titleForEmptyDataSet:(UIScrollView*) scrollView
{
    NSString* text = NSLocalizedString(@"No one is here", @"");
    
    NSDictionary* attributes = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:18.0f],
                                 NSForegroundColorAttributeName: (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor whiteColor] : [UIColor blackColor])};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (NSAttributedString*)descriptionForEmptyDataSet:(UIScrollView*) scrollView
{
    NSString* text = NSLocalizedString(@"When you start talking to someone,\n they will show up here.", @"");
    
    NSMutableParagraphStyle* paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    paragraph.alignment = NSTextAlignmentCenter;
    
    NSDictionary* attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:14.0f],
                                 NSForegroundColorAttributeName: (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor whiteColor] : [UIColor blackColor]),
                                 NSParagraphStyleAttributeName: paragraph};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

-(UIColor*) backgroundColorForEmptyDataSet:(UIScrollView*) scrollView
{
    return [UIColor colorNamed:@"chats"];
}

-(BOOL) emptyDataSetShouldDisplay:(UIScrollView*) scrollView
{
    BOOL toreturn = (self.unpinnedContacts.count == 0 && self.pinnedContacts.count == 0) ? YES : NO;
    if(toreturn)
    {
        // A little trick for removing the cell separators
        self.tableView.tableFooterView = [UIView new];
    }
    return toreturn;
}

#pragma mark - mac menu

-(void) showContacts:(id) sender { // function definition for @selector
    [self showContacts];
}

-(void) showContacts
{
    // Only segue if at least one account is enabled
    if([self showAccountNumberWarningIfNeeded])
        return;
    [self performSegueWithIdentifier:@"showContacts" sender:self];
}

//we can not call this var "completion" because then some dumb comiler check kicks in and tells us "completion handler is never called"
//which is plainly wrong. "callback" on the other hand doesn't seem to be a word in the objc compiler's "bad words" dictionary,
//so this makes it compile again
-(void) showRegisterWithUsername:(NSString*) username onHost:(NSString*) host withToken:(NSString*) token usingCompletion:(monal_id_block_t) callback
{
    MonalAppDelegate* appDelegate = (MonalAppDelegate *)[[UIApplication sharedApplication] delegate];
    [[appDelegate getTopViewController] dismissViewControllerAnimated:YES completion:^{
        UIViewController* registerViewController = [[SwiftuiInterface new] makeAccountRegistration:@{
            @"host": nilWrapper(host),
            @"username": nilWrapper(username),
            @"token": nilWrapper(token),
            @"completion": nilDefault(callback, (^(id accountNo) {
                DDLogWarn(@"Dummy reg completion called for accountNo: %@", accountNo);
            })),
        }];
        [self presentViewController:registerViewController animated:YES completion:^{}];
    }];
}

-(void) showDetails
{
    if([MLNotificationManager sharedInstance].currentContact != nil)
    {
        UIViewController* detailsViewController = [[SwiftuiInterface new] makeContactDetails:[MLNotificationManager sharedInstance].currentContact];
        [self presentViewController:detailsViewController animated:YES completion:^{}];
    }
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
                // remove contact from activechats table
                [self refreshDisplay];
                // open placeholder
                [self presentChatWithContact:nil];
                return;
            }
        }];
    }
}

@end
