//
//  ActiveChatsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#include "metamacros.h"

#import <Contacts/Contacts.h>
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
#import "MLCall.h"      //for MLCallType
#import "XMPPIQ.h"
#import "MLIQProcessor.h"
#import "UIColor+Theme.h"
#import <Monal-Swift.h>

#define prependToViewQueue(firstArg, ...)                           metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))([self prependToViewQueue:firstArg withId:MLViewIDUnspecified andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__])(_prependToViewQueue(firstArg, __VA_ARGS__))
#define _prependToViewQueue(ownId, block)                           [self prependToViewQueue:block withId:ownId andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]
#define appendToViewQueue(firstArg, ...)                            metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))([self appendToViewQueue:firstArg withId:MLViewIDUnspecified andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__])(_appendToViewQueue(firstArg, __VA_ARGS__))
#define _appendToViewQueue(ownId, block)                            [self prependToViewQueue:block withId:ownId andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]
#define appendingReplaceOnViewQueue(firstArg, secondArg, ...)       metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))([self replaceIdOnViewQueue:firstArg withBlock:secondArg havingId:MLViewIDUnspecified andAppendOnUnknown:YES withFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__])(_appendingReplaceOnViewQueue(firstArg, secondArg, __VA_ARGS__))
#define prependingReplaceOnViewQueue(firstArg, secondArg, ...)      metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))([self replaceIdOnViewQueue:firstArg withBlock:secondArg havingId:MLViewIDUnspecified andAppendOnUnknown:NO withFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__])(_prependingReplaceOnViewQueue(firstArg, secondArg, __VA_ARGS__))
#define _appendingReplaceOnViewQueue(replaceId, ownId, block)       [self replaceIdOnViewQueue:replaceId withBlock:block havingId:ownId andAppendOnUnknown:YES withFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]
#define _prependingReplaceOnViewQueue(replaceId, ownId, block)      [self replaceIdOnViewQueue:replaceId withBlock:block havingId:ownId andAppendOnUnknown:NO withFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]
typedef void (^view_queue_block_t)(PMKResolver _Nonnull);

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
    BOOL _loginAlreadyAutodisplayed;
    NSMutableArray* _blockQueue;
    dispatch_semaphore_t _blockQueueSemaphore;
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

typedef NS_ENUM(NSUInteger, MLViewID) {
    MLViewIDUnspecified,
    MLViewIDRegisterView,
    MLViewIDWelcomeLoginView,
};

static NSMutableSet* _mamWarningDisplayed;
static NSMutableSet* _smacksWarningDisplayed;
static NSMutableSet* _pushWarningDisplayed;

+(void) initialize
{
    DDLogDebug(@"initializing active chats class");
    _mamWarningDisplayed = [NSMutableSet new];
    _smacksWarningDisplayed = [NSMutableSet new];
    _pushWarningDisplayed = [NSMutableSet new];
}

-(instancetype)initWithNibName:(NSString*) nibNameOrNil bundle:(NSBundle*) nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    [self commonInit];
    return self;
}

-(instancetype) initWithStyle:(UITableViewStyle) style
{
    self = [super initWithStyle:style];
    [self commonInit];
    return self;
}

-(instancetype) initWithCoder:(NSCoder*) coder
{
    self = [super initWithCoder:coder];
    [self commonInit];
    return self;
}

-(void) commonInit
{
    _blockQueue = [NSMutableArray new];
    _blockQueueSemaphore = dispatch_semaphore_create(1);
}

-(void) resetViewQueue
{
    [_blockQueue removeAllObjects];
}

-(void) prependToViewQueue:(view_queue_block_t) block withId:(MLViewID) viewId andFile:(char*) file andLine:(int) line andFunc:(char*) func
{
    @synchronized(_blockQueue) {
        DDLogDebug(@"Prepending block with id %lu defined in %s at %@:%d to queue...", (unsigned long)viewId, func, [HelperTools sanitizeFilePath:file], line);
        [_blockQueue insertObject:@{@"id":@(viewId), @"block":^(PMKResolver resolve) {
            DDLogDebug(@"Calling block with id %lu defined in %s at %@:%d...", (unsigned long)viewId, func, [HelperTools sanitizeFilePath:file], line);
            block(resolve);
            DDLogDebug(@"Block with id %lu defined in %s at %@:%d finished...", (unsigned long)viewId, func, [HelperTools sanitizeFilePath:file], line);
        }} atIndex:0];
    }
    [self processViewQueue];
}

-(void) appendToViewQueue:(view_queue_block_t) block withId:(MLViewID) viewId andFile:(char*) file andLine:(int) line andFunc:(char*) func
{
    @synchronized(_blockQueue) {
        DDLogDebug(@"Appending block with id %lu defined in %s at %@:%d to queue...", (unsigned long)viewId, func, [HelperTools sanitizeFilePath:file], line);
        [_blockQueue addObject:@{@"id":@(viewId), @"block":^(PMKResolver resolve) {
            DDLogDebug(@"Calling block with id %lu defined in %s at %@:%d...", (unsigned long)viewId, func, [HelperTools sanitizeFilePath:file], line);
            block(resolve);
            DDLogDebug(@"Block with id %lu defined in %s at %@:%d finished...", (unsigned long)viewId, func, [HelperTools sanitizeFilePath:file], line);
        }}];
    }
    [self processViewQueue];
}

-(void) replaceIdOnViewQueue:(MLViewID) previousId withBlock:(view_queue_block_t) block havingId:(MLViewID) viewId andAppendOnUnknown:(BOOL) appendOnUnknown withFile:(char*) file andLine:(int) line andFunc:(char*) func
{
    @synchronized(_blockQueue) {
        DDLogDebug(@"Replacing block with id %lu with new block having id %lu defined in %s at %@:%d to queue...", (unsigned long)previousId, (unsigned long)viewId, func, [HelperTools sanitizeFilePath:file], line);
        
        //search for old block to replace and remove it
        NSInteger index = -1;
        for(NSDictionary* blockInfo in _blockQueue)
        {
            index++;
            if(((NSNumber*)blockInfo[@"id"]).unsignedIntegerValue == previousId)
            {
                DDLogDebug(@"Found blockInfo at index %d: %@", (int)index, blockInfo);
                [self->_blockQueue removeObjectAtIndex:index];
                break;
            }
        }
        if(index == -1)
        {
            if(appendOnUnknown)
            {
                DDLogDebug(@"Did not find block with id %lu on queue, appending block instead...", (unsigned long)previousId);
                [self appendToViewQueue:block withId:viewId andFile:file andLine:line andFunc:func];
            }
            else
            {
                DDLogDebug(@"Did not find block with id %lu on queue, prepending block instead...", (unsigned long)previousId);
                [self prependToViewQueue:block withId:viewId andFile:file andLine:line andFunc:func];
            }
            return;
        }
        
        //add replaement block at right position
        [_blockQueue insertObject:@{@"id":@(viewId), @"block":^(PMKResolver resolve) {
            DDLogDebug(@"Calling block with id %lu defined in %s at %@:%d...", (unsigned long)viewId, func, [HelperTools sanitizeFilePath:file], line);
            block(resolve);
            DDLogDebug(@"Block with id %lu defined in %s at %@:%d finished...", (unsigned long)viewId, func, [HelperTools sanitizeFilePath:file], line);
        }} atIndex:index];
    }
    [self processViewQueue];
}

-(void) processViewQueue
{
    //we are using uikit api all over the place: make sure we always run in the main queue
    [HelperTools dispatchAsync:YES reentrantOnQueue:dispatch_get_main_queue() withBlock:^{
        NSMutableArray* viewControllerHierarchy = [self getCurrentViewControllerHierarchy];
        
        //don't show the next entry if there is still the previous one
        //if(self.splitViewController.collapsed)
        if([viewControllerHierarchy count] > 0)
        {
            DDLogDebug(@"Ignoring call to processViewQueue, already showing: %@", viewControllerHierarchy);
            return;
        }
        
        //don't run the next block if the previous one did not yet complete
        if(dispatch_semaphore_wait(self->_blockQueueSemaphore, DISPATCH_TIME_NOW) != 0)
        {
            DDLogDebug(@"Ignoring call to processViewQueue, block still running, showing: %@", viewControllerHierarchy);
            return;
        }
        
        NSDictionary* blockInfo = nil;
        @synchronized(self->_blockQueue) {
            if(self->_blockQueue.count > 0)
            {
                blockInfo = [self->_blockQueue objectAtIndex:0];
                [self->_blockQueue removeObjectAtIndex:0];
            }
            else
                DDLogDebug(@"Queue is empty...");
        }
        if(blockInfo)
        {
            //DDLogDebug(@"Calling next block, stacktrace: %@", [NSThread callStackSymbols]);
            monal_void_block_t looper = ^{
                dispatch_semaphore_signal(self->_blockQueueSemaphore);
                DDLogDebug(@"Looping to next block...");
                [self processViewQueue];
            };
            [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
                ((view_queue_block_t)blockInfo[@"block"])(resolve);
            }].ensure(^{
                looper();
            });
        }
        else
        {
            DDLogDebug(@"Not calling next block: there is none...");
            dispatch_semaphore_signal(self->_blockQueueSemaphore);
        }
    }];
}

#pragma mark view lifecycle

-(void) configureComposeButton
{
    UIImage* image = [[UIImage systemImageNamed:@"person.2.fill"] imageWithTintColor:UIColor.monalGreen];
    UITapGestureRecognizer* tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showContacts:)];
    self.composeButton.customView = [HelperTools
        buttonWithNotificationBadgeForImage:image
        hasNotification:[[DataLayer sharedInstance] allContactRequests].count > 0
        withTapHandler:tapRecognizer];
    [self.composeButton setIsAccessibilityElement:YES];
    if([[DataLayer sharedInstance] allContactRequests].count > 0)
        [self.composeButton setAccessibilityLabel:NSLocalizedString(@"Open contact list (contact requests pending)", @"")];
    else
        [self.composeButton setAccessibilityLabel:NSLocalizedString(@"Open contact list", @"")];
    [self.composeButton setAccessibilityTraits:UIAccessibilityTraitButton];
}

-(void) viewDidLoad
{
    DDLogDebug(@"active chats view did load");
    [super viewDidLoad];
    
    _loginAlreadyAutodisplayed = NO;
    _startedOrientation = 0;
    
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    
    self.view.backgroundColor = [UIColor lightGrayColor];
    self.view.autoresizingMask = UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    
    MonalAppDelegate* appDelegate = (MonalAppDelegate*)[[UIApplication sharedApplication] delegate];
    appDelegate.activeChats = self;
    
    self.chatListTable = [UITableView new];
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
    [nc addObserver:self selector:@selector(showWarningsIfNeeded) name:kMonalFinishedCatchup object:nil];
    
    [_chatListTable registerNib:[UINib nibWithNibName:@"MLContactCell" bundle:[NSBundle mainBundle]] forCellReuseIdentifier:@"ContactCell"];
    
    self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
#if !TARGET_OS_MACCATALYST
    self.splitViewController.primaryBackgroundStyle = UISplitViewControllerBackgroundStyleSidebar;
#endif
    self.settingsButton.image = [UIImage systemImageNamed:@"gearshape.fill"];
    [self configureComposeButton];

    self.spinnerButton.customView = self.spinner;
    
    self.chatListTable.emptyDataSetSource = self;
    self.chatListTable.emptyDataSetDelegate = self;
    
    //has to be done here to not always prepend intro screens onto our view queue
    //once a fullscreen view is dismissed (or the app is switched to foreground)
    [self segueToIntroScreensIfNeeded];
}

-(void) dealloc
{
    DDLogDebug(@"active chats dealloc");
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
        return;
    [self refresh];
}

-(void) handleContactRemoved:(NSNotification*) notification
{
    MLContact* removedContact = [notification.userInfo objectForKey:@"contact"];
    if(removedContact == nil)
        unreachable();
    
    dispatch_async(dispatch_get_main_queue(), ^{
        DDLogInfo(@"Contact removed, refreshing active chats...");
        
        //update red dot
        [self configureComposeButton];
        
        // remove contact from activechats table
        [self refreshDisplay];
        
        // open placeholder if the removed contact was "in foreground"
        if([removedContact isEqualToContact:[MLNotificationManager sharedInstance].currentContact])
        {
            DDLogInfo(@"Contact removed, closing chat view...");
            [self presentChatWithContact:nil];
        }
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
            else
            {
                // Chats does not exists in active Chats yet
                NSUInteger oldCount = [insertContactToArray count];
                [insertContactToArray insertObject:contact atIndex:0];
                [self.chatListTable insertRowsAtIndexPaths:@[insertAtPath] withRowAnimation:UITableViewRowAnimationRight];
                //make sure to fully refresh to remove the empty dataset (yes this will trigger on first chat pinning, too, but that does no harm)
                if(oldCount == 0)
                    [self refreshDisplay];
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
    
    [self presentSplitPlaceholder];
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
    
    [self refresh];
}

-(void) sheetDismissed
{
    [self refresh];
}

-(void) refresh
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshDisplay];      // load contacts
        [self processViewQueue];
    });
}

-(void) didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

-(void) showAddContactWithJid:(NSString*) jid preauthToken:(NSString* _Nullable) preauthToken prefillAccount:(xmpp* _Nullable) account andOmemoFingerprints:(NSDictionary* _Nullable) fingerprints
{
    //check if contact is already known in any of our accounts and open a chat with the first contact we can find
    for(xmpp* checkAccount in [MLXMPPManager sharedInstance].connectedXMPP)
    {
        MLContact* checkContact = [MLContact createContactFromJid:jid andAccountNo:checkAccount.accountNo];
        if(checkContact.isInRoster)
        {
            [self presentChatWithContact:checkContact];
            return;
        }
    }
    
    appendToViewQueue((^(PMKResolver resolve) {
        UIViewController* addContactMenuView = [[SwiftuiInterface new] makeAddContactViewForJid:jid preauthToken:preauthToken prefillAccount:account andOmemoFingerprints:fingerprints withDismisser:^(MLContact* _Nonnull newContact) {
            [self presentChatWithContact:newContact];
        }];
        addContactMenuView.ml_disposeCallback = ^{
            [self sheetDismissed];
        };
        [self dismissCompleteViewChainWithAnimation:NO andCompletion:^{
            [self presentViewController:addContactMenuView animated:NO completion:^{resolve(nil);}];
        }];
    }));
}

-(void) showAddContact
{
    appendToViewQueue((^(PMKResolver resolve) {
        UIViewController* addContactMenuView = [[SwiftuiInterface new] makeAddContactViewWithDismisser:^(MLContact* _Nonnull newContact) {
            [self presentChatWithContact:newContact];
        }];
        addContactMenuView.ml_disposeCallback = ^{
            [self sheetDismissed];
        };
        [self dismissCompleteViewChainWithAnimation:NO andCompletion:^{
            [self presentViewController:addContactMenuView animated:NO completion:^{resolve(nil);}];
        }];
    }));
}

-(void) segueToIntroScreensIfNeeded
{
    DDLogDebug(@"segueToIntroScreensIfNeeded got called...");
    //prepend in a prepend block to make sure we have prepended everything in order before showing the first view
    //(if we would not do this, the first view prepended would be shown regardless of other views prepended after it)
    //every entry in here is flipped, because we want to prepend all intro screens to our queue
    prependToViewQueue((^(PMKResolver resolve) {
#ifdef IS_QUICKSY
        prependToViewQueue((^(PMKResolver resolve) {
            [self syncContacts];
            resolve(nil);
        }));
#else
        [self showWarningsIfNeeded];
#endif
        
        prependToViewQueue(MLViewIDWelcomeLoginView, (^(PMKResolver resolve) {
#ifdef IS_QUICKSY
            if([[DataLayer sharedInstance] enabledAccountCnts].intValue == 0)
            {
                DDLogDebug(@"Showing account registration view...");
                UIViewController* view = [[SwiftuiInterface new] makeAccountRegistration:@{}];
                if(UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad)
                    view.modalPresentationStyle = UIModalPresentationFullScreen;
                else
                    view.ml_disposeCallback = ^{
                        [self sheetDismissed];
                    };
                [self dismissCompleteViewChainWithAnimation:NO andCompletion:^{
                    [self presentViewController:view animated:NO completion:^{resolve(nil);}];
                }];
            }
            else
                resolve(nil);
#else
            // display quick start if the user never seen it or if there are 0 enabled accounts
            if([[DataLayer sharedInstance] enabledAccountCnts].intValue == 0 && !self->_loginAlreadyAutodisplayed)
            {
                DDLogDebug(@"Showing WelcomeLogIn view...");
                UIViewController* loginViewController = [[SwiftuiInterface new] makeViewWithName:@"WelcomeLogIn"];
                loginViewController.ml_disposeCallback = ^{
                    self->_loginAlreadyAutodisplayed = YES;
                    [self sheetDismissed];
                };
                [self dismissCompleteViewChainWithAnimation:NO andCompletion:^{
                    [self presentViewController:loginViewController animated:YES completion:^{resolve(nil);}];
                }];
            }
            else
                resolve(nil);
#endif
        }));
    
        prependToViewQueue((^(PMKResolver resolve) {
            if(![[HelperTools defaultsDB] boolForKey:@"hasCompletedOnboarding"])
            {
                DDLogDebug(@"Showing onboarding view...");
                UIViewController* view = [[SwiftuiInterface new] makeViewWithName:@"OnboardingView"];
                if(UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad)
                    view.modalPresentationStyle = UIModalPresentationFullScreen;
                else
                    view.ml_disposeCallback = ^{
                        [self sheetDismissed];
                    };
                [self dismissCompleteViewChainWithAnimation:NO andCompletion:^{
                    [self presentViewController:view animated:NO completion:^{resolve(nil);}];
                }];
            }
            else
                resolve(nil);
        }));
        
        prependToViewQueue((^(PMKResolver resolve) {
            //open password migration if needed
            NSArray* needingMigration = [[DataLayer sharedInstance] accountListNeedingPasswordMigration];
            if(needingMigration.count > 0)
            {
                DDLogDebug(@"Showing password migration view...");
                UIViewController* passwordMigration = [[SwiftuiInterface new] makePasswordMigration:needingMigration];
                passwordMigration.ml_disposeCallback = ^{
                    [self sheetDismissed];
                };
                [self dismissCompleteViewChainWithAnimation:NO andCompletion:^{
                    [self presentViewController:passwordMigration animated:YES completion:^{resolve(nil);}];
                }];
            }
            else
                resolve(nil);
        }));
        
        resolve(nil);
    }));
}

#ifdef IS_QUICKSY
-(void) syncContacts
{
    CNContactStore* store = [[CNContactStore alloc] init];
    [store requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError* _Nullable error) {
        if(granted)
        {
            NSString* countryCode = [[HelperTools defaultsDB] objectForKey:@"Quicksy_countryCode"];
            NSCharacterSet* allowedCharacters = [[NSCharacterSet characterSetWithCharactersInString:@"+0123456789"] invertedSet];
            NSMutableDictionary* numbers = [NSMutableDictionary new];
            
            CNContactFetchRequest* request = [[CNContactFetchRequest alloc] initWithKeysToFetch:@[CNContactPhoneNumbersKey, CNContactNicknameKey, CNContactGivenNameKey, CNContactFamilyNameKey]];
            NSError* error;
            [store enumerateContactsWithFetchRequest:request error:&error usingBlock:^(CNContact* _Nonnull contact, BOOL* _Nonnull stop) {
                if(!error)
                {
                    NSString* name = [[NSString stringWithFormat:@"%@ %@", contact.givenName, contact.familyName] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    for(CNLabeledValue<CNPhoneNumber*>* phone in contact.phoneNumbers)
                    {
                        //add country code if missing
                        NSString* number = [[phone.value.stringValue componentsSeparatedByCharactersInSet:allowedCharacters] componentsJoinedByString:@""];
                        if(countryCode != nil && ![number hasPrefix:@"+"] && ![number hasPrefix:@"00"])
                        {
                            DDLogVerbose(@"Adding country code '%@' to number: %@", countryCode, number);
                            number = [NSString stringWithFormat:@"%@%@", countryCode, [number hasPrefix:@"0"] ? [number substringFromIndex:1] : number];
                        }
                        numbers[number] = name;
                    }
                }
                else
                    DDLogWarn(@"Error fetching contacts: %@", error);
            }];
            
            DDLogDebug(@"Got list of contact phone numbers: %@", numbers);
            
            NSArray<xmpp*>* connectedAccounts = [MLXMPPManager sharedInstance].connectedXMPP;
            if(connectedAccounts.count == 0)
            {
                DDLogError(@"No connected account while trying to send quicksy phonebook!");
                return;
            }
            else if(connectedAccounts.count > 1)
                DDLogWarn(@"More than 1 connected account while trying to send quicksy phonebook, using first one!");
            
            XMPPIQ* iqNode = [[XMPPIQ alloc] initWithType:kiqGetType to:@"api.quicksy.im"];
            [iqNode setQuicksyPhoneBook:numbers.allKeys];
            [connectedAccounts[0] sendIq:iqNode withHandler:$newHandler(MLIQProcessor, handleQuicksyPhoneBook, $ID(numbers))];
        }
        else
            DDLogError(@"Access to contacts not granted!");
    }];
}
#endif

-(void) showWarningsIfNeeded
{
    for(NSDictionary* accountDict in [[DataLayer sharedInstance] enabledAccountList])
    {
        NSNumber* accountNo = accountDict[kAccountID];
        xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:accountNo];
        if(!account)
            @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Connected xmpp* object for accountNo is nil!" userInfo:accountDict];
        
        prependToViewQueue((^(PMKResolver resolve) {
            if(![_mamWarningDisplayed containsObject:accountNo] && account.accountState >= kStateBound && account.connectionProperties.accountDiscoDone)
            {
                if(![account.connectionProperties.accountDiscoFeatures containsObject:@"urn:xmpp:mam:2"])
                {
                    DDLogDebug(@"Showing MAM not supported warning...");
                    UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Account %@", @""), account.connectionProperties.identity.jid] message:NSLocalizedString(@"Your server does not support MAM (XEP-0313). That means you could frequently miss incoming messages!! You should switch your server or talk to the server admin to enable this!", @"") preferredStyle:UIAlertControllerStyleAlert];
                    [messageAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
                        [_mamWarningDisplayed addObject:accountNo];
                        resolve(nil);
                    }]];
                    [self dismissCompleteViewChainWithAnimation:NO andCompletion:^{
                        [self presentViewController:messageAlert animated:YES completion:nil];
                    }];
                }
                else
                {
                    [_mamWarningDisplayed addObject:accountNo];
                    resolve(nil);
                }
            }
            else
                resolve(nil);
        }));
        
        prependToViewQueue((^(PMKResolver resolve) {
            if(![_smacksWarningDisplayed containsObject:accountNo] && account.accountState >= kStateBound)
            {
                if(!account.connectionProperties.supportsSM3)
                {
                    DDLogDebug(@"Showing smacks not supported warning...");
                    UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Account %@", @""), account.connectionProperties.identity.jid] message:NSLocalizedString(@"Your server does not support Stream Management (XEP-0198). That means your outgoing messages can get lost frequently!! You should switch your server or talk to the server admin to enable this!", @"") preferredStyle:UIAlertControllerStyleAlert];
                    [messageAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
                        [_smacksWarningDisplayed addObject:accountNo];
                        resolve(nil);
                    }]];
                    [self dismissCompleteViewChainWithAnimation:NO andCompletion:^{
                        [self presentViewController:messageAlert animated:YES completion:nil];
                    }];
                }
                else
                {
                    [_smacksWarningDisplayed addObject:accountNo];
                    resolve(nil);
                }
            }
            else
                resolve(nil);
        }));
        
        prependToViewQueue((^(PMKResolver resolve) {
            if(![_pushWarningDisplayed containsObject:accountNo] && account.accountState >= kStateBound && account.connectionProperties.accountDiscoDone)
            {
                if(![account.connectionProperties.accountDiscoFeatures containsObject:@"urn:xmpp:push:0"])
                {
                    DDLogDebug(@"Showing push not supported warning...");
                    UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Account %@", @""), account.connectionProperties.identity.jid] message:NSLocalizedString(@"Your server does not support PUSH (XEP-0357). That means you have to manually open the app to retrieve new incoming messages!! You should switch your server or talk to the server admin to enable this!", @"") preferredStyle:UIAlertControllerStyleAlert];
                    [messageAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
                        [_pushWarningDisplayed addObject:accountNo];
                        resolve(nil);
                    }]];
                    [self dismissCompleteViewChainWithAnimation:NO andCompletion:^{
                        [self presentViewController:messageAlert animated:YES completion:nil];
                    }];
                }
                else
                {
                    [_pushWarningDisplayed addObject:accountNo];
                    resolve(nil);
                }
            }
            else
                resolve(nil);
        }));
    }
}

-(void) presentSplitPlaceholder
{
    // only show placeholder if we use a split view
    if(!self.splitViewController.collapsed)
    {
        DDLogVerbose(@"Presenting Chat Placeholder...");
        UIViewController* detailsViewController = [[SwiftuiInterface new] makeViewWithName:@"ChatPlaceholder"];
        [self showDetailViewController:detailsViewController sender:self];
    }
}

-(void) showNotificationSettings
{
    [self dismissCompleteViewChainWithAnimation:NO andCompletion:^{
        UIViewController* view = [[SwiftuiInterface new] makeViewWithName:@"ActiveChatsNotificationSettings"];
        view.ml_disposeCallback = ^{
            [self sheetDismissed];
        };
        [self presentViewController:view animated:YES completion:nil];
    }];
}

-(void) prependGeneralSettings
{
    prependToViewQueue((^(PMKResolver resolve) {
        UIViewController* view = [[SwiftuiInterface new] makeViewWithName:@"ActiveChatsGeneralSettings"];
        view.ml_disposeCallback = ^{
            [self sheetDismissed];
        };
        [self dismissCompleteViewChainWithAnimation:NO andCompletion:^{
            [self presentViewController:view animated:YES completion:^{resolve(nil);}];
        }];
    }));
}

-(void) showGeneralSettings
{
    appendToViewQueue((^(PMKResolver resolve) {
        UIViewController* view = [[SwiftuiInterface new] makeViewWithName:@"ActiveChatsGeneralSettings"];
        view.ml_disposeCallback = ^{
            [self sheetDismissed];
        };
        [self dismissCompleteViewChainWithAnimation:NO andCompletion:^{
            [self presentViewController:view animated:YES completion:^{resolve(nil);}];
        }];
    }));
}

-(void) showSettings
{
    appendToViewQueue((^(PMKResolver resolve) {
        [self performSegueWithIdentifier:@"showSettings" sender:self];
        resolve(nil);
    }));
}

-(void) showCallContactNotFoundAlert:(NSString*) jid
{
    UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Contact not found", @"") message:[NSString stringWithFormat:NSLocalizedString(@"You tried to call contact '%@' but this contact could not be found in your contact list.", @""), jid] preferredStyle:UIAlertControllerStyleAlert];
    [messageAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {}]];
    [self dismissCompleteViewChainWithAnimation:NO andCompletion:^{
        [self presentViewController:messageAlert animated:NO completion:nil];
    }];
}

-(void) callContact:(MLContact*) contact withCallType:(MLCallType) callType
{
    MonalAppDelegate* appDelegate = (MonalAppDelegate *)[[UIApplication sharedApplication] delegate];
    MLCall* activeCall = [appDelegate.voipProcessor getActiveCallWithContact:contact];
    if(activeCall != nil)
        [self presentCall:activeCall];
    else
        [self presentCall:[appDelegate.voipProcessor initiateCallWithType:callType toContact:contact]];
}

-(void) callContact:(MLContact*) contact withUIKitSender:(_Nullable id) sender
{
    MonalAppDelegate* appDelegate = (MonalAppDelegate *)[[UIApplication sharedApplication] delegate];
    MLCall* activeCall = [appDelegate.voipProcessor getActiveCallWithContact:contact];
    if(activeCall != nil)
        [self presentCall:activeCall];
    else
    {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Call Type", @"") message:NSLocalizedString(@"What call do you want to place?", @"") preferredStyle:UIAlertControllerStyleActionSheet];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"🎵 Audio", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self dismissViewControllerAnimated:YES completion:nil];
            [self presentCall:[appDelegate.voipProcessor initiateCallWithType:MLCallTypeAudio toContact:contact]];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"🎥 Video", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self dismissViewControllerAnimated:YES completion:nil];
            [self presentCall:[appDelegate.voipProcessor initiateCallWithType:MLCallTypeVideo toContact:contact]];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            [self dismissViewControllerAnimated:YES completion:nil];
        }]];
        UIPopoverPresentationController* popPresenter = [alert popoverPresentationController];
        if(sender != nil)
            popPresenter.sourceItem = sender;
        else
            popPresenter.sourceView = self.view;
        [self presentViewController:alert animated:YES completion:nil];
    }
}

-(void) presentAccountPickerForContacts:(NSArray<MLContact*>*) contacts andCallType:(MLCallType) callType
{
    [self dismissCompleteViewChainWithAnimation:NO andCompletion:^{
        UIViewController* accountPickerController = [[SwiftuiInterface new] makeAccountPickerForContacts:contacts andCallType:callType];
        accountPickerController.ml_disposeCallback = ^{
            [self sheetDismissed];
        };
        [self presentViewController:accountPickerController animated:YES completion:^{}];
    }];
}

-(void) presentCall:(MLCall*) call
{
    [self dismissCompleteViewChainWithAnimation:NO andCompletion:^{
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
    DDLogVerbose(@"presenting chat with contact: %@, stacktrace: %@", contact, [NSThread callStackSymbols]);
    [HelperTools dispatchAsync:YES reentrantOnQueue:dispatch_get_main_queue() withBlock:^{
        [self dismissCompleteViewChainWithAnimation:YES andCompletion:^{
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
            if(self.splitViewController.collapsed)
                [self.navigationController popViewControllerAnimated:NO];
            
            // show placeholder if contact is nil, open chat otherwise
            if(contact == nil)
            {
                [self presentSplitPlaceholder];
                if(completion != nil)
                    completion(@NO);
                return;
            }

            //open chat (make sure we have an active buddy for it and add it to our ui, if needed)
            //but don't animate this if the contact is already present in our list
            [[DataLayer sharedInstance] addActiveBuddies:contact.contactJid forAccount:contact.accountId];
            if([[self getChatArrayForSection:pinnedChats] containsObject:contact] || [[self getChatArrayForSection:unpinnedChats] containsObject:contact])
            {
                [self scrollToContact:contact];
                [self performSegueWithIdentifier:@"showConversation" sender:contact];
                if(completion != nil)
                    completion(@YES);
            }
            else
            {
                [self insertOrMoveContact:contact completion:^(BOOL finished __unused) {
                    [self scrollToContact:contact];
                    [self performSegueWithIdentifier:@"showConversation" sender:contact];
                    if(completion != nil)
                        completion(@YES);
                }];
            }
        }];
    }];
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
        detailsViewController.ml_disposeCallback = ^{
            [self sheetDismissed];
        };
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
            [self presentChatWithContact:selectedContact];
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
    if(indexPath.section == pinnedChats)
        chatContact = [self.pinnedContacts objectAtIndex:indexPath.row];
    else
        chatContact = [self.unpinnedContacts objectAtIndex:indexPath.row];
    
    // Display msg draft or last msg
    MLMessage* messageRow = [[DataLayer sharedInstance] lastMessageForContact:chatContact.contactJid forAccount:chatContact.accountId];

    [cell initCell:chatContact withLastMessage:messageRow];

    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    // Highlight the selected chat
    if([MLNotificationManager sharedInstance].currentContact != nil && [chatContact isEqual:[MLNotificationManager sharedInstance].currentContact])
    {
        cell.backgroundColor = [UIColor lightGrayColor];
        cell.statusText.textColor = [UIColor whiteColor];
    }
    else
    {
        cell.backgroundColor = [UIColor clearColor];
        cell.statusText.textColor = [UIColor lightGrayColor];
    }

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
    detailsViewController.ml_disposeCallback = ^{
        [self sheetDismissed];
    };
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
    //started in any orientation, moved to same orientation (or just started)
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
    NSString* text = NSLocalizedString(@"No active conversations", @"");
    
    NSDictionary* attributes = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:18.0f],
                                 NSForegroundColorAttributeName: (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor whiteColor] : [UIColor blackColor])};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (NSAttributedString*)descriptionForEmptyDataSet:(UIScrollView*) scrollView
{
    NSString* text = NSLocalizedString(@"When you start a conversation\nwith someone, they will\nshow up here.", @"");
    
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
    appendToViewQueue((^(PMKResolver resolve) {
        // Only segue if at least one account is enabled
        if(![self showAccountNumberWarningIfNeeded]);
            [self performSegueWithIdentifier:@"showContacts" sender:self];
        resolve(nil);
    }));
}

//we can not call this var "completion" because then some dumb comiler check kicks in and tells us "completion handler is never called"
//which is plainly wrong. "callback" on the other hand doesn't seem to be a word in the objc compiler's "bad words" dictionary,
//so this makes it compile again
-(void) showRegisterWithUsername:(NSString*) username onHost:(NSString*) host withToken:(NSString*) token usingCompletion:(monal_id_block_t) callback
{
    prependingReplaceOnViewQueue(MLViewIDWelcomeLoginView, MLViewIDRegisterView, (^(PMKResolver resolve) {
        UIViewController* registerViewController = [[SwiftuiInterface new] makeAccountRegistration:@{
            @"host": nilWrapper(host),
            @"username": nilWrapper(username),
            @"token": nilWrapper(token),
            @"completion": nilDefault(callback, (^(id accountNo) {
                DDLogWarn(@"Dummy reg completion called for accountNo: %@", accountNo);
            })),
        }];
        registerViewController.ml_disposeCallback = ^{
            [self sheetDismissed];
        };
        [self dismissCompleteViewChainWithAnimation:NO andCompletion:^{
            [self presentViewController:registerViewController animated:YES completion:^{resolve(nil);}];
        }];
    }));
}

-(void) showDetails
{
    appendToViewQueue((^(PMKResolver resolve) {
        if([MLNotificationManager sharedInstance].currentContact != nil)
        {
            UIViewController* detailsViewController = [[SwiftuiInterface new] makeContactDetails:[MLNotificationManager sharedInstance].currentContact];
            detailsViewController.ml_disposeCallback = ^{
                [self sheetDismissed];
            };
            [self dismissCompleteViewChainWithAnimation:NO andCompletion:^{
                [self presentViewController:detailsViewController animated:YES completion:^{resolve(nil);}];
            }];
        }
        else
            resolve(nil);
    }));
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

-(NSMutableArray*) getCurrentViewControllerHierarchy
{
    MonalAppDelegate* appDelegate = (MonalAppDelegate *)[[UIApplication sharedApplication] delegate];
    UIViewController* rootViewController = appDelegate.window.rootViewController;
    NSMutableArray* viewControllers = [NSMutableArray new];
    while(rootViewController.presentedViewController)
    {
        [viewControllers addObject:rootViewController.presentedViewController];
        rootViewController = rootViewController.presentedViewController;
    }
    return [[[viewControllers reverseObjectEnumerator] allObjects] mutableCopy];
}

-(void) dismissCompleteViewChainWithAnimation:(BOOL) animation andCompletion:(monal_void_block_t _Nullable) completion
{
    NSMutableArray* viewControllers = [self getCurrentViewControllerHierarchy];
    DDLogVerbose(@"Dismissing view controller hierarchy: %@", viewControllers);
    [self dismissRecursorWithViewControllers:viewControllers animation:animation andCompletion:completion];
}

-(void) dismissRecursorWithViewControllers:(NSMutableArray*) viewControllers animation:(BOOL) animation andCompletion:(monal_void_block_t _Nullable) completion
{
    if([viewControllers count] > 0)
    {
        UIViewController* viewController = viewControllers[0];
        [viewControllers removeObjectAtIndex:0];
        DDLogVerbose(@"Dismissing: %@", viewController);
        [viewController dismissViewControllerAnimated:animation completion:^{
            [self dismissRecursorWithViewControllers:viewControllers animation:animation andCompletion:completion];
        }];
    }
    else
    {
        DDLogVerbose(@"View chain completely dismissed...");
        completion();
    }
}

-(void) scrollToContact:(MLContact*) contact
{
    __block NSIndexPath* indexPath = nil;
    for(size_t section = pinnedChats; section < activeChatsViewControllerSectionCnt && !indexPath; section++) {
        NSMutableArray* curContactArray = [self getChatArrayForSection:section];

        // get indexPath
        [curContactArray enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            MLContact* rowContact = (MLContact*)obj;
            if([rowContact isEqualToContact:contact])
            {
                indexPath = [NSIndexPath indexPathForRow:idx inSection:section];
                *stop = YES;
            }
        }];
    }
    [self.chatListTable selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
}

@end
