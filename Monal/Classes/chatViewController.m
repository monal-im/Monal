//
//  chat.m
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "chatViewController.h"
#import "MLChatCell.h"
#import "MLChatImageCell.h"
#import "MLChatMapsCell.h"
#import "MLLinkCell.h"
#import "MLReloadCell.h"
#import "MLUploadQueueCell.h"

#import "ActiveChatsViewController.h"
#import "AESGcm.h"
#import "DataLayer.h"
#import "HelperTools.h"
#import "MBProgressHUD.h"
#import "MLChatInputContainer.h"
#import "MLChatViewHelper.h"
#import "MLConstants.h"
#import "MLFiletransfer.h"
#import "MLImageManager.h"
#import "MLMucProcessor.h"
#import "MLVoIPProcessor.h"
#import "MLNotificationQueue.h"
#import "MLOMEMO.h"
#import "MLSearchViewController.h"
#import "MLXEPSlashMeHandler.h"
#import "MonalAppDelegate.h"
#import "xmpp.h"

#import <Monal-Swift.h>
#import <stdatomic.h>

#define UPLOAD_TYPE_IMAGE @"UploadTypeImage";
#define UPLOAD_TYPE_URL @"UploadTypeURL";

@import AVFoundation;
@import MobileCoreServices;
@import QuartzCore.CATransaction;
@import QuartzCore;
@import UniformTypeIdentifiers.UTCoreTypes;

@class MLEmoji;

@interface chatViewController()<ChatInputActionDelegage, UISearchControllerDelegate>
{
    BOOL _isTyping;
    monal_void_block_t _cancelTypingNotification;
    monal_void_block_t _cancelLastInteractionTimer;
    NSMutableDictionary<NSString*, MLContact*>* _localMLContactCache;
    BOOL _isRecording;
}

@property (nonatomic, strong) NSDateFormatter* destinationDateFormat;
@property (nonatomic, strong) NSCalendar* gregorian;
@property (nonatomic, assign) NSInteger thisyear;
@property (nonatomic, assign) NSInteger thismonth;
@property (nonatomic, assign) NSInteger thisday;
@property (nonatomic, strong) MBProgressHUD* uploadHUD;
@property (nonatomic, strong) MBProgressHUD* gpsHUD;
@property (nonatomic, strong) UIBarButtonItem* callButton;

@property (nonatomic, strong) NSMutableArray<MLMessage*>* messageList;
@property (nonatomic, strong) UIDocumentPickerViewController* filePicker;

@property (nonatomic, assign) BOOL sendLocation; // used for first request

@property (nonatomic, strong) NSDate* lastMamDate;
@property (nonatomic, assign) BOOL hardwareKeyboardPresent;
@property (nonatomic, strong) xmpp* xmppAccount;

@property (nonatomic, strong) NSLayoutConstraint* chatInputConstraintHWKeyboard;
@property (nonatomic, strong) NSLayoutConstraint* chatInputConstraintSWKeyboard;

//infinite scrolling
@property (atomic) BOOL viewDidAppear;
@property (atomic) BOOL viewIsScrolling;
@property (atomic) BOOL isLoadingMam;
@property (atomic) BOOL moreMessagesAvailable;

@property (nonatomic, strong) UIButton *lastMsgButton;
@property (nonatomic, assign) CGFloat lastOffset;

//SearchViewController, SearchResultViewController
@property (nonatomic, strong) MLSearchViewController* searchController;
@property (nonatomic, strong) NSMutableArray* searchResultMessageList;

// Upload Queue
@property (nonatomic, strong) NSMutableOrderedSet<NSDictionary*>* uploadQueue;
@property (nonatomic, strong) NSLayoutConstraint* uploadMenuConstraint;

@property (nonatomic, strong) void (^editingCallback)(NSString* newBody);
@property (nonatomic, strong) NSMutableSet* previewedIds;

@property (atomic) BOOL isAudioMessage;
@property (nonatomic) UILongPressGestureRecognizer* longGestureRecognizer;

@property (nonatomic) UIView* audioRecoderInfoView;

#define lastMsgButtonSize 40.0

@end

@class HelperTools;

@implementation chatViewController

enum chatViewControllerSections {
    reloadBoxSection,
    messagesSection,
    chatViewControllerSectionCnt
};

enum msgSentState {
    msgSent,
    msgErrorAfterSent,
    msgRecevied,
    msgDisplayed
};

-(void) setupWithContact:(MLContact*) contact
{
    self.contact = contact;
    [self setup];
}

-(void) setup
{
    self.hidesBottomBarWhenPushed = YES;

    NSDictionary* accountDict = [[DataLayer sharedInstance] detailsForAccount:self.contact.accountId];
    if(accountDict)
        self.jid = [NSString stringWithFormat:@"%@@%@",[accountDict objectForKey:@"username"], [accountDict objectForKey:@"domain"]];

    self.previewedIds = [NSMutableSet new];

    _localMLContactCache = [[NSMutableDictionary<NSString*, MLContact*> alloc] init];
}

#pragma mark -  view lifecycle

-(void) viewDidLoad
{
    [super viewDidLoad];

    if([[DataLayer sharedInstance] isContactInList:self.contact.contactJid forAccount:self.contact.accountId] == NO)
    {
        DDLogWarn(@"ChatView: Contact %@ is unkown", self.contact.contactJid);
#ifdef IS_ALPHA
        @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Contact is unkown - GUI error" userInfo:nil];
#endif
    }

    [self initNavigationBarItems];

    [self setupDateObjects];
    containerView = self.view;
    self.messageTable.scrollsToTop = YES;
    self.chatInput.scrollsToTop = NO;
    self.editingCallback = nil;

    self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;

    _isTyping = NO;
    self.hidesBottomBarWhenPushed=YES;

    self.chatInput.layer.borderColor = [UIColor lightGrayColor].CGColor;
    self.chatInput.layer.cornerRadius = 3.0f;
    self.chatInput.layer.borderWidth = 0.5f;
    self.chatInput.textContainerInset = UIEdgeInsetsMake(5, 0, 5, 0);

    self.messageTable.rowHeight = UITableViewAutomaticDimension;
    self.messageTable.estimatedRowHeight = UITableViewAutomaticDimension;

#if TARGET_OS_MACCATALYST
    //does not become first responder like in iOS
    [self.view addSubview:self.inputContainerView];

    [self.inputContainerView.leadingAnchor constraintEqualToAnchor:self.inputContainerView.superview.leadingAnchor].active = YES;
    [self.inputContainerView.bottomAnchor constraintEqualToAnchor:self.inputContainerView.superview.bottomAnchor].active = YES;
    [self.inputContainerView.trailingAnchor constraintEqualToAnchor:self.inputContainerView.superview.trailingAnchor].active = YES;
    self.tableviewBottom.constant += 20;
#endif
    self.filePicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem]];
    self.filePicker.allowsMultipleSelection = YES;
    self.filePicker.delegate = self;

    // Set max height of the chatInput (The chat should be still readable while the HW-Keyboard is active
    self.chatInputConstraintHWKeyboard = [NSLayoutConstraint constraintWithItem:self.chatInput attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationLessThanOrEqual toItem:nil attribute:NSLayoutAttributeHeight multiplier:1 constant:self.view.frame.size.height * 0.6];
    self.chatInputConstraintSWKeyboard = [NSLayoutConstraint constraintWithItem:self.chatInput attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationLessThanOrEqual toItem:nil attribute:NSLayoutAttributeHeight multiplier:1 constant:self.view.frame.size.height * 0.4];
    self.uploadMenuConstraint = [NSLayoutConstraint
                                constraintWithItem:self.uploadMenuView
                                attribute:NSLayoutAttributeHeight
                                relatedBy:NSLayoutRelationEqual
                                toItem:nil
                                attribute:NSLayoutAttributeNotAnAttribute
                                multiplier:1.0
                                constant:0]; // Constant will be set through showUploadQueue
    [self.inputContainerView addConstraint:self.chatInputConstraintHWKeyboard];
    [self.inputContainerView addConstraint:self.chatInputConstraintSWKeyboard];
    [self.uploadMenuView addConstraint:self.uploadMenuConstraint];

    [self setChatInputHeightConstraints:YES];

#if !TARGET_OS_MACCATALYST
    [self initAudioRecordButton];
#endif

    // setup refreshControl for infinite scrolling
    UIRefreshControl* refreshControl = [UIRefreshControl new];
    [refreshControl addTarget:self action:@selector(loadOldMsgHistory:) forControlEvents:UIControlEventValueChanged];
    refreshControl.attributedTitle = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Loading more Messages from Server", @"")];
    [self.messageTable setRefreshControl:refreshControl];
    self.moreMessagesAvailable = YES;

    self.uploadQueue = [[NSMutableOrderedSet<NSDictionary*> alloc] init];

    [self.messageTable addInteraction:[[UIDropInteraction alloc] initWithDelegate:self]];
    [self.inputContainerView addInteraction:[[UIDropInteraction alloc] initWithDelegate:self]];

#ifdef DISABLE_OMEMO
    NSMutableArray* rightBarButtons = [NSMutableArray new];
    for(UIBarButtonItem* entry in self.navigationItem.rightBarButtonItems)
        if(entry.action != @selector(toggleEncryption:))
            [rightBarButtons addObject:entry];
    self.navigationItem.rightBarButtonItems = rightBarButtons;
#endif
    
    [self updateCallButtonImage];
}

-(void) updateCallButtonImage
{
    if([HelperTools shouldProvideVoip])
    {
        //this has to be done in the main thread because it's ui related
        //use reentrant dispatch to make sure we update the call button in one shot to not let it flicker
        //this does not matter if we aren't already in the main thread, hence the async dispatch
        [HelperTools dispatchAsync:YES reentrantOnQueue:dispatch_get_main_queue() withBlock:^{
            //these contact types can not be called
            if(self.contact.isGroup || self.contact.isSelfChat)
            {
                self.callButton = nil;
                
                //remove call button, if present
                NSMutableArray* rightBarButtons = [NSMutableArray new];
                for(UIBarButtonItem* entry in self.navigationItem.rightBarButtonItems)
                    if(entry.action != @selector(openCallScreen:))
                        [rightBarButtons addObject:entry];
                self.navigationItem.rightBarButtonItems = rightBarButtons;
                
                return;
            }
            
            if(self.callButton == nil)
            {
                self.callButton = [UIBarButtonItem new];
                [self.callButton setAction:@selector(openCallScreen:)];
            }
            
            MonalAppDelegate* appDelegate = (MonalAppDelegate *)[[UIApplication sharedApplication] delegate];
            MLCall* activeCall = [appDelegate.voipProcessor getActiveCallWithContact:self.contact];
            if(activeCall != nil)
                self.callButton.image = [UIImage systemImageNamed:@"phone.connection.fill"];
            else
                self.callButton.image = [UIImage systemImageNamed:@"phone.fill"];
            
            //add the button to the bar button items if not already present
            BOOL present = NO;
            for(UIBarButtonItem* entry in self.navigationItem.rightBarButtonItems)
                if(entry.action == @selector(openCallScreen:))
                    present = YES;
            if(!present)
            {
                NSMutableArray* rightBarButtons = [self.navigationItem.rightBarButtonItems mutableCopy];
                [rightBarButtons addObject:self.callButton];
                self.navigationItem.rightBarButtonItems = rightBarButtons;
            }
        }];
    }
}

-(void) initNavigationBarItems
{
    UIView* cusView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 120, self.navigationController.navigationBar.frame.size.height)];

    self.navBarIcon = [[UIImageView alloc] initWithFrame:CGRectMake(0, 7, 30, 30)];
    self.navBarContactJid = [[UILabel alloc] initWithFrame:CGRectMake(38, 7, 200, 18)];
    self.navBarLastInteraction = [[UILabel alloc] initWithFrame:CGRectMake(38, 26, 200, 12)];

    [self.navBarContactJid setFont:[UIFont systemFontOfSize:15.0]];
    [self.navBarLastInteraction setFont:[UIFont systemFontOfSize:10.0]];

    [cusView addSubview:self.navBarIcon];
    [cusView addSubview:self.navBarContactJid];
    [cusView addSubview:self.navBarLastInteraction];
    UITapGestureRecognizer* customViewTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(commandIPressed:)];
    [cusView addGestureRecognizer:customViewTapRecognizer];
    self.navigationItem.leftBarButtonItems = @[[[UIBarButtonItem alloc] initWithCustomView:cusView]];
    self.navigationItem.leftItemsSupplementBackButton = YES;
}

-(void) initLastMsgButton
{
    unichar arrowSymbol = 0x2193;

    self.lastMsgButton = [UIButton new];
    [self lastMsgButtonPositionConfigWithSize:self.inputContainerView.bounds.size];
    self.lastMsgButton.layer.cornerRadius = lastMsgButtonSize/2;
    self.lastMsgButton.layer.backgroundColor = [UIColor whiteColor].CGColor;
    [self.lastMsgButton setTitleColor:[UIColor grayColor] forState:UIControlStateNormal];
    [self.lastMsgButton setTitle:[NSString stringWithCharacters:&arrowSymbol length:1] forState:UIControlStateNormal];
    self.lastMsgButton.titleLabel.font = [UIFont systemFontOfSize:30.0];
    self.lastMsgButton.layer.borderColor = [UIColor grayColor].CGColor;
    self.lastMsgButton.userInteractionEnabled = YES;
    [self.lastMsgButton setHidden:YES];
    [self.inputContainerView addSubview:self.lastMsgButton];
    MLChatInputContainer* inputView = (MLChatInputContainer*) self.inputContainerView;
    inputView.chatInputActionDelegate = self;
}

-(void) initAudioRecordButton
{
    self.longGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(recordMessageAudio:)];
    self.longGestureRecognizer.minimumPressDuration = 0.8;
    [self.audioRecordButton addGestureRecognizer:self.longGestureRecognizer];

    [self.sendButton setHidden:YES];
    self.isAudioMessage = YES;
}

-(void) lastMsgButtonPositionConfigWithSize:(CGSize)size
{
    float buttonXPos = (float)(self.inputContainerView.frame.origin.x + self.inputContainerView.frame.size.width - lastMsgButtonSize - 5);
    float buttonYPos = (float)(self.inputContainerView.frame.origin.y - lastMsgButtonSize - 5);
    self.lastMsgButton.frame = CGRectMake(buttonXPos, buttonYPos , lastMsgButtonSize, lastMsgButtonSize);
}
#pragma mark - ChatInputActionDelegage
-(void)doScrollDownAction
{
    [self scrollToBottom];
}

#pragma mark - SearchViewController
-(void) initSearchViewControler
{
    self.searchController = [[MLSearchViewController alloc] initWithSearchResultsController:nil];
    [self.searchController setObscuresBackgroundDuringPresentation:NO];
    self.searchController.searchResultDelegate = self;
    self.searchController.jid = self.jid;
    self.searchResultMessageList = [NSMutableArray new];
}

-(void) initSearchButtonItem
{
    UIBarButtonItem* seachButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSearch
                                                                                 target:self
                                                                                 action:@selector(showSeachButtonAction)];

    NSMutableArray* rightBarButtons = [self.navigationItem.rightBarButtonItems mutableCopy];
    [rightBarButtons addObject:seachButton];
    self.navigationItem.rightBarButtonItems = rightBarButtons;
}

-(void) showSeachButtonAction
{
    self.searchController.contact = self.contact;
    if(!(self.searchController.isViewLoaded && self.searchController.view.window))
        [self presentViewController:self.searchController animated:NO completion:nil];
}

-(void) dismissSearchViewControllerAction
{
    [self.searchController dismissViewControllerAnimated:NO completion:nil];
}

#pragma mark - SearchResultVCActionDelegate

-(void) doGoSearchResultAction:(NSNumber*)nextDBId
{
    NSNumber* messagePathIdx = [self.searchController getMessageIndexPathForDBId:nextDBId];
    if (messagePathIdx != nil)
    {
        long nextPathIdx = [messagePathIdx longValue];
        NSIndexPath* msgIdxPath = [NSIndexPath indexPathForRow:nextPathIdx inSection:messagesSection];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.messageTable scrollToRowAtIndexPath:msgIdxPath atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
            MLBaseCell* selectedCell = [self.messageTable cellForRowAtIndexPath:msgIdxPath];
            UIColor* originColor = [selectedCell.backgroundColor copy];
            selectedCell.backgroundColor = [UIColor lightGrayColor];

            [UIView animateWithDuration:0.2 delay:0.2 options:UIViewAnimationOptionCurveLinear animations:^{
                selectedCell.backgroundColor = originColor;
            } completion:nil];
        });
    }
}

-(void) doReloadHistoryForSearch
{
    [self loadOldMsgHistory];
}

- (void) doReloadActionForAllTableView
{
    [self.messageTable reloadData];
}

- (void) doGetMsgData
{
    for (unsigned int idx = 0; idx < self.messageList.count; idx++)
    {
        MLMessage* msg = [self.messageList objectAtIndex:idx];
        [self doSetMsgPathIdx:idx withDBId:msg.messageDBId];
    }
}

-(void) doSetNotLoadingHistory
{
    if (self.searchController.isActive)
    {
        self.searchController.isLoadingHistory = NO;
        [self.searchController setResultToolBar];
    }
    [self doGetMsgData];
}

-(void)doShowLoadingHistory:(NSString *)title
{
    UIAlertController *loadingWarning = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Hint", @"")
                                                                        message:title preferredStyle:UIAlertControllerStyleAlert];

    [self presentViewController:loadingWarning animated:YES completion:^{
        dispatch_queue_t queue = dispatch_get_main_queue();
        dispatch_after(2.0, queue, ^{
            [loadingWarning dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}


-(void) doSetMsgPathIdx:(NSInteger) pathIdx withDBId:(NSNumber *) messageDBId
{
    if(messageDBId != nil)
        [self.searchController setMessageIndexPath:[NSNumber numberWithInteger:pathIdx] withDBId:messageDBId];
}

-(BOOL) isContainKeyword:(NSNumber *) messageDBId
{
    if([self.searchController getMessageIndexPathForDBId:messageDBId] != nil)
        return YES;
    return NO;
}

-(void) resetHistoryAttributeForCell:(MLBaseCell*) cell
{
    if(!cell.messageBody.text)
        return;

    NSMutableAttributedString *defaultAttrString = [[NSMutableAttributedString alloc] initWithString:cell.messageBody.text];
    NSInteger textLength = (cell.messageBody.text == nil) ? 0: cell.messageBody.text.length;
    NSRange defaultTextRange = NSMakeRange(0, textLength);
    [defaultAttrString addAttribute:NSBackgroundColorAttributeName value:[UIColor clearColor] range:defaultTextRange];
    cell.messageBody.attributedText = defaultAttrString;
    cell.textLabel.backgroundColor = [UIColor clearColor];
}


-(void) setChatInputHeightConstraints:(BOOL) hwKeyboardPresent
{
    if(!self.chatInputConstraintHWKeyboard || !self.chatInputConstraintSWKeyboard)
        return;
    
    // activate / disable constraints depending on keyboard type
    self.chatInputConstraintHWKeyboard.active = hwKeyboardPresent;
    self.chatInputConstraintSWKeyboard.active = !hwKeyboardPresent;
    
    [self.inputContainerView layoutIfNeeded];
}

-(void) handleForeGround
{
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized(self->_localMLContactCache) {
            [self->_localMLContactCache removeAllObjects];
        }
        [self refreshData];
        [self reloadTable];
    });
}

-(void) openCallScreen:(id) sender
{
    MLAssert(sender != nil || self.callButton != nil, @"We need at least one ui source (e.g. button) to base the popover controller upon!");
    if(sender == nil)
        sender = self.callButton;
    
    MonalAppDelegate* appDelegate = (MonalAppDelegate *)[[UIApplication sharedApplication] delegate];
    MLCall* activeCall = [appDelegate.voipProcessor getActiveCallWithContact:self.contact];
    if(activeCall == nil && ![[DataLayer sharedInstance] checkCap:@"urn:xmpp:jingle-message:0" forUser:self.contact.contactJid onAccountNo:self.contact.accountId])
    {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Missing Call Support", @"") message:NSLocalizedString(@"Your contact may not support calls. Your call might never reach its destination.", @"") preferredStyle:UIAlertControllerStyleActionSheet];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Try nevertheless", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self dismissViewControllerAnimated:YES completion:nil];
            
            //now initiate call
            MonalAppDelegate* appDelegate = (MonalAppDelegate*)[[UIApplication sharedApplication] delegate];
            [appDelegate.activeChats callContact:self.contact withUIKitSender:sender];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            [self dismissViewControllerAnimated:YES completion:nil];
        }]];
        UIPopoverPresentationController* popPresenter = [alert popoverPresentationController];
        if(@available(iOS 16.0, macCatalyst 16.0, *))
            popPresenter.sourceItem = sender;
        else
            popPresenter.barButtonItem = sender;
        [self presentViewController:alert animated:YES completion:nil];
    }
    else
    {
        MonalAppDelegate* appDelegate = (MonalAppDelegate*)[[UIApplication sharedApplication] delegate];
        [appDelegate.activeChats callContact:self.contact withUIKitSender:sender];
    }
}

-(IBAction) toggleEncryption:(id) sender
{
    if([HelperTools isContactBlacklistedForEncryption:self.contact])
        return;
#ifndef DISABLE_OMEMO
    if(self.contact.isEncrypted)
    {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Disable encryption?", @"") message:NSLocalizedString(@"Do you really want to disable encryption for this contact?", @"") preferredStyle:UIAlertControllerStyleActionSheet];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Yes, deactivate encryption", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [MLChatViewHelper<chatViewController*> toggleEncryptionForContact:self.contact withSelf:self afterToggle:^() {
                [self displayEncryptionStateInUI];
            }];
            [self dismissViewControllerAnimated:YES completion:nil];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"No, keep encryption activated", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            [self dismissViewControllerAnimated:YES completion:nil];
        }]];
        UIPopoverPresentationController* popPresenter = [alert popoverPresentationController];
        if(@available(iOS 16.0, macCatalyst 16.0, *))
            popPresenter.sourceItem = sender;
        else
            popPresenter.barButtonItem = sender;
        [self presentViewController:alert animated:YES completion:nil];
    }
    else
        [MLChatViewHelper<chatViewController*> toggleEncryptionForContact:self.contact withSelf:self afterToggle:^() {
            [self displayEncryptionStateInUI];
        }];
#endif
}

-(void) observeValueForKeyPath:(NSString*) keyPath ofObject:(id) object change:(NSDictionary *) change context:(void*) context
{
    if([keyPath isEqualToString:@"isEncrypted"] && object == self.contact)
        [self displayEncryptionStateInUI];
}

-(void) displayEncryptionStateInUI
{
    if(self.contact.isEncrypted)
        [self.navBarEncryptToggleButton setImage:[UIImage imageNamed:@"744-locked-received"]];
    else
        [self.navBarEncryptToggleButton setImage:[UIImage imageNamed:@"745-unlocked"]];
    //disable encryption button on unsupported muc types
    if(self.contact.isGroup && [self.contact.mucType isEqualToString:@"group"] == NO)
        [self.navBarEncryptToggleButton setEnabled:NO];
    //disable encryption button for special jids
    if([HelperTools isContactBlacklistedForEncryption:self.contact])
        [self.navBarEncryptToggleButton setEnabled:NO];
}

-(void) handleContactRemoved:(NSNotification*) notification
{
    MLContact* contact = [notification.userInfo objectForKey:@"contact"];
    if(self.contact && [self.contact isEqualToContact:contact])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            DDLogInfo(@"Closing chat view, contact was removed...");
            [self.navigationController popToRootViewControllerAnimated:YES];
        });
    }
}

-(void) refreshContact:(NSNotification*) notification
{
    @synchronized(_localMLContactCache) {
        [_localMLContactCache removeAllObjects];
    }
    MLContact* contact = [notification.userInfo objectForKey:@"contact"];
    if(self.contact && [self.contact isEqualToContact:contact])
        [self updateUIElements];
}

-(void) updateUIElements
{
    if(self.contact.accountId == nil)
        return;

    NSString* jidLabelText = nil;
    BOOL sendButtonEnabled = NO;

    NSString* contactDisplayName = self.contact.contactDisplayName;
    if(!contactDisplayName)
        contactDisplayName = @"";

    //send button is always enabled, except if the account is permanently disabled
    sendButtonEnabled = YES;
    if(![[DataLayer sharedInstance] isAccountEnabled:self.contact.accountId])
        sendButtonEnabled = NO;

    jidLabelText = contactDisplayName;

    if(self.contact.isGroup)
    {
        NSArray* members = [[DataLayer sharedInstance] getMembersAndParticipantsOfMuc:self.contact.contactJid forAccountId:self.xmppAccount.accountNo];
        if(members.count > 0)
            jidLabelText = [NSString stringWithFormat:@"%@ (%ld)", contactDisplayName, members.count];
    }
    // change text values
    dispatch_async(dispatch_get_main_queue(), ^{
        self.navBarContactJid.text = jidLabelText;
        self.sendButton.enabled = sendButtonEnabled;
        [[MLImageManager sharedInstance] getIconForContact:self.contact withCompletion:^(UIImage *image) {
            self.navBarIcon.image=image;
        }];
        
        [self updateCallButtonImage];
    });
}

-(void) updateUIElementsOnAccountChange:(NSNotification* _Nullable) notification
{
    if(notification)
    {
        NSDictionary* userInfo = notification.userInfo;
        // Check if all objects of the notification are present
        NSString* accountNo = [userInfo objectForKey:kAccountID];
        NSNumber* accountState = [userInfo objectForKey:kAccountState];

        // Only parse account changes for our current opened account
        if(accountNo.intValue != self.xmppAccount.accountNo.intValue)
            return;

        if(accountNo && accountState)
            [self updateUIElements];
    }
    else
    {
        [self updateUIElements];
    }
}

-(void) stopLastInteractionTimer
{
    @synchronized(self) {
        if(_cancelLastInteractionTimer)
            _cancelLastInteractionTimer();
        _cancelLastInteractionTimer = nil;
    }
}

-(void) updateTypingTime:(NSDate* _Nullable) lastInteractionDate
{
    DDLogVerbose(@"LastInteraction updateTime() called: %@", lastInteractionDate);
    NSString* lastInteractionString = @"";      //unknown last interaction because not supported by any remote resource
    if(lastInteractionDate != nil)
        lastInteractionString = [HelperTools formatLastInteraction:lastInteractionDate];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.navBarLastInteraction.text = lastInteractionString;
    });

    @synchronized(self) {
        [self stopLastInteractionTimer];
        // this timer will be called only if needed and makes sure the "last active: xx minutes ago" text gets updated every minute
        if(lastInteractionDate != nil && lastInteractionDate.timeIntervalSince1970 > 0)
            _cancelLastInteractionTimer = createTimer(60.0, ^{
                [self updateTypingTime:lastInteractionDate];
            });
    }
}

-(void) updateNavBarLastInteractionLabel:(NSNotification*) notification
{
    NSDate* lastInteractionDate = nil;
    NSString* jid = self.contact.contactJid;
    // use supplied data from notification...
    if(notification)
    {
        NSDictionary* data = notification.userInfo;
        NSString* notifcationAccountNo = data[@"accountNo"];
        if(![jid isEqualToString:data[@"jid"]] || self.contact.accountId.intValue != notifcationAccountNo.intValue)
            return;     // ignore other accounts or contacts
        if([data[@"isTyping"] boolValue] == YES)
        {
            [self stopLastInteractionTimer];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.navBarLastInteraction.text = NSLocalizedString(@"Typing...", @"");
            });
            return;
        }
        // this is nil for a "not typing" (aka typing ended) notification or if no "urn:xmpp:idle:1" is supported by any devices of this contact
        lastInteractionDate = nilExtractor(data[@"lastInteraction"]);
    }
    // ...or load the latest interaction timestamp from db
    else
        // this is nil if no "urn:xmpp:idle:1" is supported by any devices of this contact
        lastInteractionDate = self.contact.lastInteractionTime;

    // make timestamp human readable (lastInteractionDate will be captured by this block and automatically used by our timer)
    [self updateTypingTime:lastInteractionDate];
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    //throw on empty contacts
    MLAssert(self.contact.contactJid != nil, @"can not open chat for empty contact jid");
    MLAssert(self.contact.accountId != nil, @"can not open chat for empty account id");

    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    [nc addObserver:self selector:@selector(handleDeletedMessage:) name:kMonalDeletedMessageNotice object:nil];
    [nc addObserver:self selector:@selector(handleSentMessage:) name:kMonalSentMessageNotice object:nil];
    [nc addObserver:self selector:@selector(handleMessageError:) name:kMonalMessageErrorNotice object:nil];


    [nc addObserver:self selector:@selector(dismissKeyboard:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(handleForeGround) name:kMonalRefresh object:nil];

    [nc addObserver:self selector:@selector(keyboardDidShow:) name:UIKeyboardDidShowNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardDidHide:) name:UIKeyboardDidHideNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardWillDisappear:) name:UIKeyboardWillHideNotification object:nil];

    [nc addObserver:self selector:@selector(handleReceivedMessage:) name:kMonalMessageReceivedNotice object:nil];
    [nc addObserver:self selector:@selector(handleDisplayedMessage:) name:kMonalMessageDisplayedNotice object:nil];
    [nc addObserver:self selector:@selector(handleFiletransferMessageUpdate:) name:kMonalMessageFiletransferUpdateNotice object:nil];

    [nc addObserver:self selector:@selector(refreshContact:) name:kMonalContactRefresh object:nil];
    [nc addObserver:self selector:@selector(handleContactRemoved:) name:kMonalContactRemoved object:nil];
    [nc addObserver:self selector:@selector(updateUIElementsOnAccountChange:) name:kMonalAccountStatusChanged object:nil];
    [nc addObserver:self selector:@selector(updateNavBarLastInteractionLabel:) name:kMonalLastInteractionUpdatedNotice object:nil];

    [nc addObserver:self selector:@selector(handleBackgroundChanged) name:kMonalBackgroundChanged object:nil];
    
    [nc addObserver:self selector:@selector(updateCallButtonImage) name:kMonalCallAdded object:nil];
    [nc addObserver:self selector:@selector(updateCallButtonImage) name:kMonalCallRemoved object:nil];

    self.viewDidAppear = NO;
    self.viewIsScrolling = YES;
    //stop editing (if there is some)
    [self stopEditing];
    self.xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId];
    if(!self.xmppAccount) DDLogDebug(@"Disabled account detected");

    [MLNotificationManager sharedInstance].currentContact = self.contact;

    [self handleForeGround];
    [self updateUIElements];
    [self updateNavBarLastInteractionLabel:nil];
    [self displayEncryptionStateInUI];

    [self handleBackgroundChanged];

    self.placeHolderText.text = [NSString stringWithFormat:NSLocalizedString(@"Message from %@", @""), self.jid];
    // Load message draft from db
    NSString* messageDraft = [[DataLayer sharedInstance] loadMessageDraft:self.contact.contactJid forAccount:self.contact.accountId];
    if(messageDraft && [messageDraft length] > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.chatInput.text = messageDraft;
            self.placeHolderText.hidden = YES;
        });
    }
    self.hardwareKeyboardPresent = YES; //default to YES and when keybaord will appears is called, this may be set to NO
    [self setSendButtonIconWithTextLength:[self.chatInput.text length]];

    // Set correct chatInput height constraints
    [self setChatInputHeightConstraints:self.hardwareKeyboardPresent];
    [self scrollToBottom];

    [self tempfreezeAutoloading];
    
    [self.contact addObserver:self forKeyPath:@"isEncrypted" options:NSKeyValueObservingOptionNew context:nil];
}


-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
#ifndef DISABLE_OMEMO
    if(self.xmppAccount) {
        BOOL omemoDeviceForContactFound = [self.xmppAccount.omemo knownDevicesForAddressName:self.contact.contactJid].count > 0;
        if(!omemoDeviceForContactFound) {
            if(self.contact.isEncrypted && [[DataLayer sharedInstance] isAccountEnabled:self.xmppAccount.accountNo] && self.contact.isGroup && ![self.contact.mucType isEqualToString:@"group"])
            {
                // a group that does not support OMEMO has encryption enabled
                // disable it
                self.contact.isEncrypted = NO;
                [[DataLayer sharedInstance] disableEncryptForJid:self.contact.contactJid andAccountNo:self.contact.accountId];
            }
            else if(self.contact.isEncrypted && [[DataLayer sharedInstance] isAccountEnabled:self.xmppAccount.accountNo] && (!self.contact.isGroup || (self.contact.isGroup && ![self.contact.mucType isEqualToString:@"group"])))
            {
                UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"No OMEMO keys found", @"") message:NSLocalizedString(@"This contact may not support OMEMO encrypted messages. Please try again in a few seconds.", @"") preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Disable Encryption", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    // Disable encryption
                    self.contact.isEncrypted = NO;
                    [self updateUIElements];
                    [[DataLayer sharedInstance] disableEncryptForJid:self.contact.contactJid andAccountNo:self.contact.accountId];
                    [alert dismissViewControllerAnimated:YES completion:nil];
                }]];
                [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Ignore", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                    [alert dismissViewControllerAnimated:YES completion:nil];
                }]];

                [self presentViewController:alert animated:YES completion:nil];
            }
        }
    }
#endif
    [self refreshCounter];

    //init the floating last message button
    [self initLastMsgButton];

    self.viewDidAppear = YES;

    [self initSearchViewControler];
}

-(void) viewWillDisappear:(BOOL)animated
{
    //stop editing (if there is some)
    [self stopEditing];
    
    //stop audio recording, if currently running
    if(self->_isRecording)
    {
        [[MLAudioRecoderManager sharedInstance] stop:NO];
        self->_isRecording = NO;
    }

    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self];
        @try
    {
        [self.contact removeObserver:self forKeyPath:@"isEncrypted"];
    }
    @catch(id theException)
    {
        //do nothing
    }

    // Save message draft
    BOOL success = [self saveMessageDraft];
    if(success) {
        // Update status message for contact to show current draft
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:self.xmppAccount userInfo:@{@"contact": self.contact}];
    }
    [super viewWillDisappear:animated];
    [MLNotificationManager sharedInstance].currentContact = nil;

    [self sendChatState:NO];
    [self stopLastInteractionTimer];

    [_lastMsgButton removeFromSuperview];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if(self.messageTable.contentSize.height > self.messageTable.bounds.size.height)
        [self.messageTable setContentOffset:CGPointMake(0, self.messageTable.contentSize.height - self.messageTable.bounds.size.height) animated:NO];
}

-(BOOL) saveMessageDraft
{
    // Save message draft
    return [[DataLayer sharedInstance] saveMessageDraft:self.contact.contactJid forAccount:self.contact.accountId withComment:self.chatInput.text];
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    @try
    {
        [self.contact removeObserver:self forKeyPath:@"isEncrypted"];
    }
    @catch(id theException)
    {
        //do nothing
    }
    [self stopLastInteractionTimer];
}

-(void) handleBackgroundChanged
{
    dispatch_async(dispatch_get_main_queue(), ^{
        DDLogVerbose(@"Loading background image for %@", self.contact);
        self.backgroundImage.image = [[MLImageManager sharedInstance] getBackgroundFor:self.contact];
        //use default background if this contact does not have its own
        if(self.backgroundImage.image == nil)
            self.backgroundImage.image = [[MLImageManager sharedInstance] getBackgroundFor:nil];
        self.backgroundImage.hidden = self.backgroundImage.image == nil;
        DDLogVerbose(@"Background is now: %@", self.backgroundImage.image);
    });
}

#pragma mark rotation
-(void) viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [self stopEditing];
    [self.chatInput resignFirstResponder];

    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        //[self lastMsgButtonPositionConfigWithSize:self.inputContainerView.bounds.size];
        [self lastMsgButtonPositionConfigWithSize:size];
    }];
}

#pragma mark gestures

-(IBAction)dismissKeyboard:(id)sender
{
    [self stopEditing];
    [self saveMessageDraft];
    [self.chatInput resignFirstResponder];
    [self sendChatState:NO];
}

#pragma mark message signals

-(void) refreshCounter
{
    if(self.navigationController.topViewController == self)
    {
        if(![self.contact isEqualToContact:[MLNotificationManager sharedInstance].currentContact])
            return;

        if(![HelperTools isNotInFocus])
        {
            //don't block the main thread while writing to the db (another thread could hold a write transaction already, slowing down the main thread)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                //get list of unread messages
                NSArray* unread = [[DataLayer sharedInstance] markMessagesAsReadForBuddy:self.contact.contactJid andAccount:self.contact.accountId tillStanzaId:nil wasOutgoing:NO];

                //send displayed marker for last unread message (XEP-0333)
                //but only for 1:1 or group-type mucs,not for channe-type mucs (privacy etc.)
                MLMessage* lastUnreadMessage = [unread lastObject];
                if(lastUnreadMessage && (!self.contact.isGroup || [@"group" isEqualToString:self.contact.mucType]))
                {
                    DDLogDebug(@"Sending XEP-0333 displayed marker for message '%@'", lastUnreadMessage.messageId);
                    [self.xmppAccount sendDisplayMarkerForMessage:lastUnreadMessage];
                }

                //now switch back to the main thread, we are reading only (and self.contact should only be accessed from the main thread)
                dispatch_async(dispatch_get_main_queue(), ^{
                    //remove notifications of all read messages (this will cause the MLNotificationManager to update the app badge, too)
                    [[MLNotificationQueue currentQueue] postNotificationName:kMonalDisplayedMessagesNotice object:self.xmppAccount userInfo:@{@"messagesArray":unread}];

                    // update unread counter
                    [self.contact updateUnreadCount];

                    //refresh contact in active contacts view
                    [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:self.xmppAccount userInfo:@{@"contact": self.contact}];
                });
            });

        }
        else
            DDLogDebug(@"Not marking messages as read because we are still in background: %@ notInFokus: %@", bool2str([HelperTools isInBackground]), bool2str([HelperTools isNotInFocus]));
    }
}

-(void) refreshData
{
    if(!self.contact.contactJid)
        return;

    NSMutableArray<MLMessage*>* messages = [[DataLayer sharedInstance] messagesForContact:self.contact.contactJid forAccount: self.contact.accountId];
    NSNumber* unreadMsgCnt = [[DataLayer sharedInstance] countUserUnreadMessages:self.contact.contactJid forAccount: self.contact.accountId];

    if([unreadMsgCnt integerValue] == 0)
        self->_firstmsg = YES;

    if(!self.jid)
        return;

    //TODO: use a factory method for this!!
    MLMessage* unreadStatus = [MLMessage new];
    unreadStatus.messageType = kMessageTypeStatus;
    unreadStatus.messageText = NSLocalizedString(@"Unread Messages Below", @"");
    unreadStatus.actualFrom = self.jid;
    unreadStatus.isMuc = self.contact.isGroup;

    NSInteger unreadPos = (NSInteger)messages.count - 1;
    while(unreadPos >= 0)
    {
        MLMessage* row = [messages objectAtIndex:unreadPos];
        if(!row.unread)
        {
            unreadPos++; //move back down one
            break;
        }
        unreadPos--; //move up the list
    }

    if(unreadPos <= (NSInteger)messages.count - 1 && unreadPos > 0) {
        [messages insertObject:unreadStatus atIndex:unreadPos];
    }

    self.messageList = messages;
    [self doSetNotLoadingHistory];
    [self refreshCounter];
}

#pragma mark - textview
-(void) sendMessage:(NSString*) messageText withType:(NSString*) messageType
{
    [self sendMessage:messageText andMessageID:nil withType:messageType];
}

-(void) sendMessage:(nonnull NSString*) messageText andMessageID:(NSString*) messageID withType:(NSString*) messageType
{
    DDLogVerbose(@"Sending message");
    NSString* newMessageID = messageID ? messageID : [[NSUUID UUID] UUIDString];
    //dont readd it, use the exisitng
    NSDictionary* accountDict = [[DataLayer sharedInstance] detailsForAccount:self.contact.accountId];
    if(accountDict == nil)
    {
        DDLogError(@"AccountNo %@ not found!", self.contact.accountId);
        return;
    }
    if(self.contact.contactJid == nil || [[DataLayer sharedInstance] isContactInList:self.contact.contactJid forAccount:self.contact.accountId] == NO)
    {
        DDLogError(@"Can not send message to unkown contact %@ on accountNo %@ - GUI Error", self.contact.contactJid, self.contact.accountId);
        return;
    }
    if(!messageID && !messageType) {
        DDLogError(@"message id and type both cant be empty");
        return;
    }

    if(!messageID)
    {
        [self addMessageto:self.contact.contactJid withMessage:messageText andId:newMessageID messageType:messageType mimeType:nil size:nil];
        [[MLXMPPManager sharedInstance] sendMessage:messageText toContact:self.contact isEncrypted:self.contact.isEncrypted isUpload:NO messageId:newMessageID
                            withCompletionHandler:nil];
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:self.xmppAccount userInfo:@{@"contact": self.contact}];
    }
    else
    {
        //clean error because this seems to be a retry (to be filled again, if error persists)
        [[DataLayer sharedInstance] clearErrorOfMessageId:newMessageID];
        for(size_t msgIdx = [self.messageList count]; msgIdx > 0; msgIdx--)
        {
            // find msg that should be updated
            MLMessage* msg = [self.messageList objectAtIndex:(msgIdx - 1)];
            if([msg.messageId isEqualToString:newMessageID])
            {
                msg.errorType = @"";
                msg.errorReason = @"";
            }
        }
        [[MLXMPPManager sharedInstance]
                      sendMessage:messageText
                        toContact:self.contact
                      isEncrypted:self.contact.isEncrypted
                         isUpload:NO
                        messageId:newMessageID
            withCompletionHandler:nil
        ];
    }

    [[MLNotificationQueue currentQueue] postNotificationName:kMLMessageSentToContact object:self userInfo:@{@"contact":self.contact}];
}

-(void) sendChatState:(BOOL) isTyping
{
    if(!self.sendButton.enabled)
    {
        DDLogWarn(@"Account disabled, ignoring chatstate update");
        return;
    }

    // Do not send when the user disabled the feature
    if(![[HelperTools defaultsDB] boolForKey: @"SendLastChatState"])
        return;

    if(isTyping != _isTyping)       //changed state? --> send typing notification
    {
        DDLogVerbose(@"Sending chatstate isTyping=%@", bool2str(isTyping));
        [[MLXMPPManager sharedInstance] sendChatState:isTyping toContact:self.contact];
    }

    //set internal state
    _isTyping = isTyping;

    //cancel old timer if existing
    if(_cancelTypingNotification)
        _cancelTypingNotification();

    //start new timer if we are currently typing
    if(isTyping)
        _cancelTypingNotification = createTimer(5.0, (^{
            //no typing interaction in 5 seconds? --> send out active chatstate (e.g. typing ended)
            if(self->_isTyping)
            {
                self->_isTyping = NO;
                DDLogVerbose(@"Sending chatstate isTyping=NO");
                [[MLXMPPManager sharedInstance] sendChatState:NO toContact:self.contact];
            }
        }));
}

-(void) resignTextView
{
    [self tempfreezeAutoloading];

    // Trim leading spaces
    NSString* cleanString = [self.chatInput.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // Only send msg that have at least one character
    if(cleanString.length > 0)
    {
        // Reset chatInput -> remove draft from db so that macOS will show the newly sent message
        [self.chatInput setText:@""];
        [self saveMessageDraft];

        [self setSendButtonIconWithTextLength:0];

        if(self.editingCallback)
            self.editingCallback(cleanString);
        else
        {
            // Send trimmed message
            NSString* lowercaseCleanString = [cleanString lowercaseString];
            if([lowercaseCleanString rangeOfString:@" "].location == NSNotFound && [lowercaseCleanString hasPrefix:@"https://"])
                [self sendMessage:cleanString withType:kMessageTypeUrl];
            else
                [self sendMessage:cleanString withType:kMessageTypeText];
        }
    }
    [self sendChatState:NO];
    [self emptyUploadQueue];
}

-(IBAction) sendMessageText:(id)sender
{
    [self resignTextView];
}

-(IBAction) record:(id) sender
{
    dispatch_async(dispatch_get_main_queue(), ^{
        DDLogInfo(@"Record button pressed...");
        [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
            if(granted)
            {
                if(!self->_isRecording)
                {
                    DDLogInfo(@"Starting to record audio...");
                    [[MLAudioRecoderManager sharedInstance] setRecoderManagerDelegate:self];
                    [[MLAudioRecoderManager sharedInstance] start];
                    self->_isRecording = YES;
                }
                else
                {
                    DDLogInfo(@"Stopping audio recording...");
                    [[MLAudioRecoderManager sharedInstance] stop:YES];
                    self->_isRecording = NO;
                }
            }
            else
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertController *messageAlert =[UIAlertController alertControllerWithTitle:NSLocalizedString(@"Please Allow Audio Access", @"") message:NSLocalizedString(@"If you want to use audio message you will need to allow access in Settings-> Privacy-> Microphone.", @"") preferredStyle:UIAlertControllerStyleAlert];

                    UIAlertAction *closeAction =[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {

                    }];

                    [messageAlert addAction:closeAction];
                    [self presentViewController:messageAlert animated:YES completion:nil];
                });
            }
        }];
    });
}

-(void) recordMessageAudio:(UILongPressGestureRecognizer*) gestureRecognizer
{
    DDLogInfo(@"Gesture recognizer called...");
    if(gestureRecognizer.state == UIGestureRecognizerStateBegan && _isRecording)
    {
        DDLogInfo(@"Long press began, aborting audio recording...");
        [[MLAudioRecoderManager sharedInstance] stop:NO];
        _isRecording = NO;
    }
}

-(BOOL) shouldPerformSegueWithIdentifier:(NSString*) identifier sender:(id) sender
{
    return YES;
}

-(void) performSegueWithIdentifier:(NSString*) identifier sender:(id) sender
{
    //this is needed to prevent segues invoked programmatically
    if([self shouldPerformSegueWithIdentifier:identifier sender:sender] == NO)
        return;
    if([identifier isEqualToString:@"showDetails"])
    {
        UIViewController* detailsViewController = [[SwiftuiInterface new] makeContactDetails: self.contact];
        [self presentViewController:detailsViewController animated:YES completion:^{}];
        return;
    }
    [super performSegueWithIdentifier:identifier sender:sender];
}


-(void) prepareForSegue:(UIStoryboardSegue*) segue sender:(id) sender
{
    [self sendChatState:NO];
}


#pragma mark - doc picker
-(IBAction) attachfile:(id) sender
{
    [self stopEditing];
    [self.chatInput resignFirstResponder];

    [self presentViewController:self.filePicker animated:YES completion:nil];

    return;
}

-(void) documentPicker:(UIDocumentPickerViewController*) controller didPickDocumentsAtURLs:(NSArray<NSURL*>*) urls
{
    DDLogDebug(@"Picked files at urls: %@", urls);
    if(urls.count == 0)
        return;
    for(NSURL* url in urls)
    {
        [url startAccessingSecurityScopedResource];     //call to stopAccessingSecurityScopedResource will be done in addUploadItemPreviewForItem
        [HelperTools addUploadItemPreviewForItem:url provider:nil andPayload:[@{
            @"type": @"file",
            @"filename": [url lastPathComponent],
            @"data": [MLFiletransfer prepareFileUpload:url],
        } mutableCopy] withCompletionHandler:^(NSMutableDictionary* payload) {
            [self addToUIQueue:@[payload]];
        }];
    }
}

#pragma mark  - location delegate
-(void) locationManagerDidChangeAuthorization:(CLLocationManager*) manager
{
    CLAuthorizationStatus gpsStatus = [manager authorizationStatus];
    if(gpsStatus == kCLAuthorizationStatusAuthorizedAlways || gpsStatus == kCLAuthorizationStatusAuthorizedWhenInUse)
    {
        if(self.sendLocation)
        {
            self.sendLocation = NO;
            [self.locationManager requestLocation];
        }
    }
    else if(gpsStatus == kCLAuthorizationStatusDenied || gpsStatus == kCLAuthorizationStatusRestricted)
    {
        // Display warning
        UIAlertController* gpsWarning = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Missing permission", @"")
                                                                            message:NSLocalizedString(@"You did not grant Monal to access your location.", @"") preferredStyle:UIAlertControllerStyleAlert];
        [gpsWarning addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* _Nonnull action) {
            [gpsWarning dismissViewControllerAnimated:YES completion:nil];
        }]];
        [gpsWarning addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Settings", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction* _Nonnull action) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
        }]];
        [self presentViewController:gpsWarning animated:YES completion:nil];
    }
}

-(void) locationManager:(CLLocationManager*) manager didUpdateLocations:(NSArray<CLLocation*>*) locations
{
    [self.locationManager stopUpdatingLocation];

    // Only send geo message if gpsHUD is visible
    if(self.gpsHUD.hidden == YES) {
        return;
    }

    // Check last location
    CLLocation* gpsLoc = [locations lastObject];
    if(gpsLoc == nil) {
        return;
    }
    self.gpsHUD.hidden = YES;
    // Send location
    [self sendMessage:[NSString stringWithFormat:@"geo:%f,%f", gpsLoc.coordinate.latitude, gpsLoc.coordinate.longitude] withType:kMessageTypeGeo];
}

- (void) locationManager:(CLLocationManager*) manager didFailWithError:(NSError*) error
{
    DDLogError(@"Error while fetching location %@", error);
}

-(void) makeLocationManager
{
    if(self.locationManager == nil)
    {
        self.locationManager = [CLLocationManager new];
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        self.locationManager.delegate = self;
    }
}

-(void) displayGPSHUD
{
    // Setup HUD
    if(!self.gpsHUD) {
        self.gpsHUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        self.gpsHUD.removeFromSuperViewOnHide=NO;
        self.gpsHUD.label.text = NSLocalizedString(@"GPS", @"");
        self.gpsHUD.detailsLabel.text = NSLocalizedString(@"Waiting for GPS signal", @"");
    }
    // Display HUD
    self.gpsHUD.hidden = NO;

    // Trigger warning when no gps location was received
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if(self.gpsHUD.hidden == NO) {
            // Stop locationManager & hide gpsHUD screen
            [self.locationManager stopUpdatingLocation];
            self.gpsHUD.hidden = YES;

            // Display warning
            UIAlertController* gpsWarning = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"No GPS location received", @"")
                                                                                message:NSLocalizedString(@"Monal did not received a gps location. Please try again later.", @"") preferredStyle:UIAlertControllerStyleAlert];
            [gpsWarning addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* _Nonnull action) {
                [gpsWarning dismissViewControllerAnimated:YES completion:nil];
            }]];
            [self presentViewController:gpsWarning animated:YES completion:nil];
        }
    });
}

-(PHPickerViewController*) generatePHPickerViewController
{
    PHPickerConfiguration* phConf = [PHPickerConfiguration new];
    phConf.selectionLimit = 0;
    phConf.filter = [PHPickerFilter anyFilterMatchingSubfilters:@[PHPickerFilter.imagesFilter, PHPickerFilter.videosFilter]];
    PHPickerViewController* picker = [[PHPickerViewController alloc] initWithConfiguration:phConf];
    picker.delegate = self;
    return picker;
}

#pragma mark - attachment picker

-(void) showCameraPermissionWarning
{
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Camera permissions missing", @"Camera permissions missing warning") message:NSLocalizedString(@"Monal is not allowed to access the camera", @"Camera permissions missing warning") preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {}];

    UIAlertAction* monalIosSettings = [UIAlertAction actionWithTitle:NSLocalizedString(@"Settings", @"Camera permissions missing warning") style:UIAlertActionStyleDefault handler:^(UIAlertAction* _Nonnull action) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
    }];

    [alert addAction:defaultAction];
    [alert addAction:monalIosSettings];
    [self presentViewController:alert animated:YES completion:nil];
}

-(IBAction) attach:(id) sender
{
    [self stopEditing];
    [self.chatInput resignFirstResponder];

    UIAlertController* actionControll = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Select Action", @"")
                                                                            message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    // Check for http upload support
    if(!self.xmppAccount.connectionProperties.supportsHTTPUpload)
    {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", @"")
                                                                       message:NSLocalizedString(@"This server does not appear to support HTTP file uploads (XEP-0363). Please ask the administrator to enable it.", @"") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];

        return;
    } else {
#if TARGET_OS_MACCATALYST
        UIAlertAction* fileAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Files", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self attachfile:sender];
        }];

        [fileAction setValue:[[UIImage systemImageNamed:@"doc"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        [actionControll addAction:fileAction];
#else
        UIImagePickerController* mediaPicker = [UIImagePickerController new];
        mediaPicker.delegate = self;

        UIAlertAction* cameraAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Camera", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction* _Nonnull action __unused) {
            @try {
                mediaPicker.sourceType = UIImagePickerControllerSourceTypeCamera;
                mediaPicker.mediaTypes = @[UTTypeImage.identifier, UTTypeMovie.identifier];

                switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo])
                {
                    case AVAuthorizationStatusAuthorized:
                    {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self presentViewController:mediaPicker animated:YES completion:nil];
                        });
                        break;
                    }
                    case AVAuthorizationStatusNotDetermined:
                    {
                        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted)
                        {
                            if(granted == YES)
                            {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [self presentViewController:mediaPicker animated:YES completion:nil];
                                });
                            }
                            else
                                DDLogWarn(@"Camera access not granted. AV Permissions now set to denied");
                        }];
                        break;
                    }
                    case AVAuthorizationStatusDenied:
                    case AVAuthorizationStatusRestricted:
                    {
                        DDLogWarn(@"Camera access denied");
                        [self showCameraPermissionWarning];
                        break;
                    }
                }
            } @catch(id ex) {
                DDLogError(@"catched exception while opening camera: %@", ex);
                [self showCameraPermissionWarning];
            }
        }];

        UIAlertAction* photosAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Photos", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action __unused) {
            [self presentViewController:[self generatePHPickerViewController] animated:YES completion:nil];
        }];

        UIAlertAction* fileAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"File", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self attachfile:sender];
        }];

        // Set image
        [cameraAction setValue:[[UIImage systemImageNamed:@"camera"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        [photosAction setValue:[[UIImage systemImageNamed:@"photo"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        [fileAction setValue:[[UIImage systemImageNamed:@"doc"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        
        [actionControll addAction:cameraAction];
        [actionControll addAction:photosAction];
        [actionControll addAction:fileAction];
#endif
    }

    UIAlertAction* gpsAlert = [UIAlertAction actionWithTitle:NSLocalizedString(@"Send Location", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction* _Nonnull action) {
        // GPS
        CLLocationManager* gpsManager = [CLLocationManager new];
        CLAuthorizationStatus gpsStatus = [gpsManager authorizationStatus];
        if(gpsStatus == kCLAuthorizationStatusAuthorizedAlways || gpsStatus == kCLAuthorizationStatusAuthorizedWhenInUse) {
            [self displayGPSHUD];
            [self makeLocationManager];
            [self.locationManager startUpdatingLocation];
        }
        else if(gpsStatus == kCLAuthorizationStatusNotDetermined || gpsStatus == kCLAuthorizationStatusRestricted)
        {
#if TARGET_OS_MACCATALYST
            UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Location Access Needed", @"") message:NSLocalizedString(@"Monal uses your location when you send a location message in a conversation.", @"") preferredStyle:UIAlertControllerStyleAlert];

            [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* _Nonnull action) {
                [alert dismissViewControllerAnimated:YES completion:nil];
            }]];

            UIAlertAction* allow = [UIAlertAction actionWithTitle:NSLocalizedString(@"Allow", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction* _Nonnull action) {
                [self makeLocationManager];
                self.sendLocation=YES;
                [self.locationManager requestWhenInUseAuthorization];
            }];
            [alert addAction:allow];

            [self presentViewController:alert animated:YES completion:nil];
#else
            [self makeLocationManager];
            self.sendLocation = YES;
            [self.locationManager requestWhenInUseAuthorization];
#endif
        }
        else
        {
            UIAlertController *permissionAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Location Access Needed", @"")
                                                                                     message:NSLocalizedString(@"Monal does not have access to your location. Please update the location access in your device's Privacy Settings.", @"") preferredStyle:UIAlertControllerStyleAlert];
            [self presentViewController:permissionAlert animated:YES completion:nil];
            [permissionAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* _Nonnull action __unused) {
                [permissionAlert dismissViewControllerAnimated:YES completion:nil];
            }]];
        }
    }];

    // Set image
    [gpsAlert setValue:[[UIImage systemImageNamed:@"location"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    [actionControll addAction:gpsAlert];
    [actionControll addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* _Nonnull action) {
        [actionControll dismissViewControllerAnimated:YES completion:nil];
    }]];

    actionControll.popoverPresentationController.sourceView = sender;
    [self presentViewController:actionControll animated:YES completion:nil];
}

-(void) picker:(PHPickerViewController*) picker didFinishPicking:(NSArray<PHPickerResult*>*) results
{
    [self dismissViewControllerAnimated:YES completion:nil];
    for(PHPickerResult* userSelection in results)
    {
        DDLogDebug(@"Handling asset with identifier: %@", userSelection.assetIdentifier);
        NSItemProvider* provider = userSelection.itemProvider;
        MLAssert(provider != nil, @"Expected a NSItemProvider");
        [HelperTools handleUploadItemProvider:provider withCompletionHandler:^(NSMutableDictionary* payload) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if(payload == nil || payload[@"error"] != nil)
                {
                    DDLogError(@"Could not save payload for sending: %@", payload[@"error"]);
                    NSString* message = NSLocalizedString(@"Monal was not able to send your attachment!", @"");
                    if(payload[@"error"] != nil)
                        message = [NSString stringWithFormat:NSLocalizedString(@"Monal was not able to send your attachment: %@", @""), [payload[@"error"] localizedDescription]];
                    UIAlertController* unknownItemWarning = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Could not send", @"")
                                                                                message:message preferredStyle:UIAlertControllerStyleAlert];
                    [unknownItemWarning addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Abort", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                        [unknownItemWarning dismissViewControllerAnimated:YES completion:nil];
                        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
                    }]];
                    [self presentViewController:unknownItemWarning animated:YES completion:nil];
                }
                else
                {
                    DDLogDebug(@"Adding payload to UI upload queue: %@", payload);
                    [self addToUIQueue:@[payload]];
                }
            });
        }];
    }
}

-(void) imagePickerController:(UIImagePickerController*) picker didFinishPickingMediaWithInfo:(NSDictionary<NSString*, id>*) info
{
    [self dismissViewControllerAnimated:YES completion:nil];
    if(info[UIImagePickerControllerMediaType] == nil)
        return;
    
    if([info[UIImagePickerControllerMediaType] isEqualToString:UTTypeImage.identifier])
    {
        UIImage* selectedImage = info[UIImagePickerControllerEditedImage];
        if(!selectedImage)
            selectedImage = info[UIImagePickerControllerOriginalImage];
        [self addToUIQueue:@[@{
            @"type": @"image",
            @"preview": selectedImage,
            @"data": [MLFiletransfer prepareUIImageUpload:selectedImage],
        }]];
    }
    else if([info[UIImagePickerControllerMediaType] isEqualToString:UTTypeMovie.identifier])
    {
        NSURL* url = info[UIImagePickerControllerMediaURL];
        [url startAccessingSecurityScopedResource];     //call to stopAccessingSecurityScopedResource will be done in addUploadItemPreviewForItem
        [HelperTools addUploadItemPreviewForItem:url provider:nil andPayload:[@{
            @"type": @"audiovisual",
            @"filename": [url lastPathComponent],
            @"data": [MLFiletransfer prepareFileUpload:url],
        } mutableCopy] withCompletionHandler:^(NSMutableDictionary* payload) {
            [self addToUIQueue:@[payload]];
        }];
    }
    else
    {
        DDLogWarn(@"Created MediaType: %@ without handler", info[UIImagePickerControllerMediaType]);
        unreachable();
    }
}

-(void) imagePickerControllerDidCancel:(UIImagePickerController*) picker
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - handling notfications

-(void) reloadTable
{
    if(self.messageTable.hasUncommittedUpdates)
        return;
    [self.messageTable reloadData];
}

//only for messages going out
-(MLMessage* _Nullable) addMessageto:(NSString *)to withMessage:(nonnull NSString *) message andId:(nonnull NSString *) messageId messageType:(nonnull NSString *) messageType mimeType:(NSString *) mimeType size:(NSNumber *) size
{
    if(!self.jid || !message)
    {
        DDLogError(@"not ready to send messages");
        return nil;
    }

    NSNumber* messageDBId = [[DataLayer sharedInstance] addMessageHistoryTo:to forAccount:self.contact.accountId withMessage:message actuallyFrom:(self.contact.isGroup ? self.contact.accountNickInGroup : self.jid) withId:messageId encrypted:self.contact.isEncrypted messageType:messageType mimeType:mimeType size:size];
    if(messageDBId != nil)
    {
        DDLogVerbose(@"added message");
        NSArray* msgList = [[DataLayer sharedInstance] messagesForHistoryIDs:@[messageDBId]];
        if(![msgList count])
        {
            DDLogError(@"Could not find msg for history ID %@!", messageDBId);
            return nil;
        }
        MLMessage* messageObj = msgList[0];

        [self tempfreezeAutoloading];

        //update message list in ui
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.messageTable performBatchUpdates:^{
                if(!self.messageList)
                    self.messageList = [NSMutableArray new];
                [self.messageList addObject:messageObj];
                NSInteger bottom = [self.messageList count]-1;
                if(bottom>=0)
                {
                    NSIndexPath* path1 = [NSIndexPath indexPathForRow:bottom inSection:messagesSection];
                    [self->_messageTable insertRowsAtIndexPaths:@[path1]
                                                withRowAnimation:UITableViewRowAnimationNone];
                }
            } completion:^(BOOL finished) {
                [self scrollToBottom];
            }];
        });

        // make sure its in active chats list
        if(_firstmsg == YES)
        {
            [[DataLayer sharedInstance] addActiveBuddies:to forAccount:self.contact.accountId];
            _firstmsg = NO;
        }
        
        //create and donate interaction to allow for ios 15 suggestions
        if(@available(iOS 15.0, macCatalyst 15.0, *))
            [[MLNotificationManager sharedInstance] donateInteractionForOutgoingDBId:messageDBId];
        
        return messageObj;
    }
    else
        DDLogError(@"failed to add message to history db");
    return nil;
}

-(void) handleNewMessage:(NSNotification *)notification
{
    DDLogVerbose(@"chat view got new message notice %@", notification.userInfo);

    MLMessage* message = [notification.userInfo objectForKey:@"message"];
    if(!message)
        DDLogError(@"Notification without message");

    if([message isEqualToContact:self.contact])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            if(!self.messageList)
                self.messageList = [NSMutableArray new];

            //update already existent message
            for(size_t msgIdx = [self.messageList count]; msgIdx > 0; msgIdx--)
            {
                // find msg that should be updated
                MLMessage* msgInList = [self.messageList objectAtIndex:(msgIdx - 1)];
                if([msgInList.messageDBId intValue] == [message.messageDBId intValue])
                {
                    //update message in our list
                    [msgInList updateWithMessage:message];

                    //update table entry
                    NSIndexPath* indexPath = [NSIndexPath indexPathForRow:(msgIdx - 1) inSection:messagesSection];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self->_messageTable beginUpdates];
                        [self->_messageTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                        [self->_messageTable endUpdates];
                    });
                    return;
                }
            }
            [CATransaction begin];
            [self.messageList addObject:message];   //do not insert based on delay timestamp because that would make it possible to fake history entries

            [self->_messageTable beginUpdates];
            NSIndexPath *path1;
            NSInteger bottom =  self.messageList.count-1;
            if(bottom >= 0) {
                path1 = [NSIndexPath indexPathForRow:bottom  inSection:messagesSection];
                [self->_messageTable insertRowsAtIndexPaths:@[path1]
                                           withRowAnimation:UITableViewRowAnimationBottom];
            }
            [self->_messageTable endUpdates];

            [self scrollToBottom];
            [CATransaction commit];

            if (self.searchController.isActive)
            {
                [self doSetMsgPathIdx:bottom withDBId:message.messageDBId];
                [self.searchController getSearchData:self.self.searchController.searchBar.text];
                [self.searchController setResultToolBar];
            }

            [self refreshCounter];
        });
    }
}

-(void) handleDeletedMessage:(NSNotification*) notification
{
    NSDictionary* dic = notification.userInfo;
    MLMessage* msg = dic[@"message"];

    DDLogDebug(@"Got deleted message notice for history id %ld and message id %@", (long)[msg.messageDBId intValue], msg.messageId);

    for(size_t msgIdx = [self.messageList count]; msgIdx > 0; msgIdx--)
    {
        // find msg that should be deleted
        MLMessage* msgInList = [self.messageList objectAtIndex:(msgIdx - 1)];
        if([msgInList.messageDBId intValue] == [msg.messageDBId intValue])
        {
            //update message in our list
            [msgInList updateWithMessage:msg];
            
            //update table entry
            NSIndexPath* indexPath = [NSIndexPath indexPathForRow:(msgIdx - 1) inSection:messagesSection];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_messageTable beginUpdates];
                [self->_messageTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                [self->_messageTable endUpdates];
            });
            break;
        }
    }
}

-(void) updateMsgState:(NSString *) messageId withEvent:(size_t) event withOptDic:(NSDictionary*) dic
{
    NSIndexPath* indexPath;
    for(size_t msgIdx = [self.messageList count]; msgIdx > 0; msgIdx--)
    {
        // find msg that should be updated
        MLMessage* msg = [self.messageList objectAtIndex:(msgIdx - 1)];
        if([msg.messageId isEqualToString:messageId])
        {
            // Set correct flags
            if(event == msgSent) {
                DDLogVerbose(@"got msgSent event for messageid: %@", messageId);
                msg.hasBeenSent = YES;
            } else if(event == msgRecevied) {
                DDLogVerbose(@"got msgRecevied event for messageid: %@", messageId);
                msg.hasBeenSent = YES;
                msg.hasBeenReceived = YES;
            } else if(event == msgDisplayed) {
                DDLogVerbose(@"got msgDisplayed event for messageid: %@", messageId);
                msg.hasBeenSent = YES;
                msg.hasBeenReceived = YES;
                msg.hasBeenDisplayed = YES;
            } else if(event == msgErrorAfterSent) {
                DDLogVerbose(@"got msgErrorAfterSent event for messageid: %@", messageId);
                //we don't want to show errors if the message has been received at least once
                if(!msg.hasBeenReceived)
                {
                    msg.errorType = [dic objectForKey:@"errorType"];
                    msg.errorReason = [dic objectForKey:@"errorReason"];

                    //ping muc to self-heal cases where we aren't joined anymore without noticing it
                    if(self.contact.isGroup)
                        [self.xmppAccount.mucProcessor ping:self.contact.contactJid];
                }
            }

            indexPath = [NSIndexPath indexPathForRow:(msgIdx - 1) inSection:messagesSection];

            //update table entry
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_messageTable beginUpdates];
                [self->_messageTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                [self->_messageTable endUpdates];
            });

            break;
        }
    }
}


-(void) handleSentMessage:(NSNotification*) notification
{
    NSDictionary* dic = notification.userInfo;
    [self updateMsgState:[dic objectForKey:kMessageId] withEvent:msgSent withOptDic:nil];
}

-(void) handleMessageError:(NSNotification*) notification
{
    NSDictionary* dic = notification.userInfo;
    [self updateMsgState:[dic objectForKey:kMessageId] withEvent:msgErrorAfterSent withOptDic:dic];
}

-(void) handleReceivedMessage:(NSNotification*) notification
{
    NSDictionary *dic = notification.userInfo;
    [self updateMsgState:[dic objectForKey:kMessageId] withEvent:msgRecevied withOptDic:nil];
}

-(void) handleDisplayedMessage:(NSNotification*) notification
{
    NSDictionary *dic = notification.userInfo;
    [self updateMsgState:[dic objectForKey:kMessageId] withEvent:msgDisplayed withOptDic:nil];
}

-(void) handleFiletransferMessageUpdate:(NSNotification*) notification
{
    NSDictionary* dic = notification.userInfo;
    MLMessage* msg = dic[@"message"];

    DDLogDebug(@"Got filetransfer message update for history id %ld: %@ (%@)", (long)[msg.messageDBId intValue], msg.filetransferMimeType, msg.filetransferSize);

    NSIndexPath* indexPath;
    for(size_t msgIdx = [self.messageList count]; msgIdx > 0; msgIdx--)
    {
        // find msg that should be updated
        MLMessage* msgInList = [self.messageList objectAtIndex:(msgIdx - 1)];
        if([msgInList.messageDBId intValue] == [msg.messageDBId intValue])
        {
            //update message in our list (this will copy filetransferMimeType and filetransferSize fields)
            [msgInList updateWithMessage:msg];

            //update table entry
            indexPath = [NSIndexPath indexPathForRow:(msgIdx - 1) inSection:messagesSection];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_messageTable beginUpdates];
                [self->_messageTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                [self->_messageTable endUpdates];
            });
            break;
        }
    }
}

-(void) scrollToBottom
{
    if(self.messageList.count == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger bottom = [self.messageTable numberOfRowsInSection:messagesSection];
        if(bottom > 0)
        {
            NSIndexPath* path1 = [NSIndexPath indexPathForRow:bottom-1  inSection:messagesSection];
          //  if(![self.messageTable.indexPathsForVisibleRows containsObject:path1])
            {
                [self.messageTable scrollToRowAtIndexPath:path1 atScrollPosition:UITableViewScrollPositionTop animated:YES];
            }
        }
    });
}

#pragma mark - date time

-(void) setupDateObjects
{
    self.destinationDateFormat = [NSDateFormatter new];
    [self.destinationDateFormat setLocale:[NSLocale currentLocale]];
    [self.destinationDateFormat setDoesRelativeDateFormatting:YES];

    self.gregorian = [[NSCalendar alloc]
                      initWithCalendarIdentifier:NSCalendarIdentifierGregorian];

    NSDate* now =[NSDate date];
    self.thisday = [self.gregorian components:NSCalendarUnitDay fromDate:now].day;
    self.thismonth = [self.gregorian components:NSCalendarUnitMonth fromDate:now].month;
    self.thisyear = [self.gregorian components:NSCalendarUnitYear fromDate:now].year;
}


-(NSString*) formattedDateWithSource:(NSDate *) sourceDate  andPriorDate:(NSDate *) priorDate
{
    NSString* dateString;
    if(sourceDate!=nil)
    {
        NSInteger msgday =[self.gregorian components:NSCalendarUnitDay fromDate:sourceDate].day;
        NSInteger msgmonth=[self.gregorian components:NSCalendarUnitMonth fromDate:sourceDate].month;
        NSInteger msgyear =[self.gregorian components:NSCalendarUnitYear fromDate:sourceDate].year;

        NSInteger priorDay = 0;
        NSInteger priorMonth = 0;
        NSInteger priorYear = 0;

        if(priorDate) {
            priorDay = [self.gregorian components:NSCalendarUnitDay fromDate:priorDate].day;
            priorMonth = [self.gregorian components:NSCalendarUnitMonth fromDate:priorDate].month;
            priorYear = [self.gregorian components:NSCalendarUnitYear fromDate:priorDate].year;
        }

        if (priorDate && ((priorDay != msgday) || (priorMonth != msgmonth) || (priorYear != msgyear))  )
        {
            //divider, hide time
            [self.destinationDateFormat setTimeStyle:NSDateFormatterNoStyle];
            // note: if it isnt the same day we want to show the full  day
            [self.destinationDateFormat setDateStyle:NSDateFormatterMediumStyle];
            dateString = [self.destinationDateFormat stringFromDate:sourceDate];
        }
    }
    return dateString;
}

-(NSString*) formattedTimeStampWithSource:(NSDate *) sourceDate
{
    NSString* dateString;
    if(sourceDate != nil)
    {
        [self.destinationDateFormat setDateStyle:NSDateFormatterNoStyle];
        [self.destinationDateFormat setTimeStyle:NSDateFormatterShortStyle];

        dateString = [self.destinationDateFormat stringFromDate:sourceDate];
    }
    return dateString;
}



-(void) retry:(id) sender
{
    NSInteger msgHistoryID = ((UIButton*) sender).tag;
    NSArray* msgArray = [[DataLayer sharedInstance] messagesForHistoryIDs:@[[NSNumber numberWithInteger:msgHistoryID]]];
    if(![msgArray count])
    {
        DDLogError(@"Called retry for non existing message with history id %ld", (long)msgHistoryID);
        return;
    }
    MLMessage* msg = msgArray[0];
    DDLogDebug(@"Called retry for message with history id %ld: %@", (long)msgHistoryID, msg);

    UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Retry sending message?", @"") message:[NSString stringWithFormat:NSLocalizedString(@"This message failed to send (%@): %@", @""), msg.errorType, msg.errorReason] preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Retry", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self sendMessage:msg.messageText andMessageID:msg.messageId withType:nil];     //type not needed for messages already in history db
        //[self setMessageId:msg.messageId sent:YES]; // for the UI, db will be set in the notification
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    alert.popoverPresentationController.sourceView = sender;

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - tableview datasource

-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return chatViewControllerSectionCnt;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case reloadBoxSection:
            return 1;
            break;
        case messagesSection:
        {
            return [self.messageList count];
            break;
        }
        default:
            break;
    }
    return 0;
}

-(nullable __kindof UITableViewCell*) messageTableCellWithIdentifier:(NSString*) identifier andInbound:(BOOL) inboundDirection fromTable:(UITableView*) tableView
{
    NSString* direction = @"In";
    if(!inboundDirection)
    {
        direction = @"Out";
    }
    NSString* fullIdentifier = [NSString stringWithFormat:@"%@%@Cell", identifier, direction];
    return [tableView dequeueReusableCellWithIdentifier:fullIdentifier];
}

-(void) tableView:(UITableView*) tableView willDisplayCell:(nonnull UITableViewCell *)cell forRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    if(indexPath.section == messagesSection && indexPath.row == 0) {
        if(self.moreMessagesAvailable && !self.viewIsScrolling) {
            self.viewIsScrolling = YES;     //don't load the next messages immediately
            [self loadOldMsgHistory];
            // Allow loading of more messages after a few seconds
            createTimer(8, (^{
                self.viewIsScrolling = NO;
            }));
        }
    }
}

-(UITableViewCell*) tableView:(UITableView*) tableView cellForRowAtIndexPath:(NSIndexPath*) indexPath
{
    if(indexPath.section == reloadBoxSection)
    {
        MLReloadCell* cell = (MLReloadCell*)[tableView dequeueReusableCellWithIdentifier:@"reloadBox" forIndexPath:indexPath];
#if TARGET_OS_MACCATALYST
            // "Pull" could be a bit misleading on a mac
            cell.reloadLabel.text = NSLocalizedString(@"Scroll down to load more messages", @"mac only string");
#endif

        // Remove selection style (if cell is pressed)
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    MLBaseCell* cell;

    MLMessage* row;
    if((NSUInteger)indexPath.row < self.messageList.count) {
        row = [self.messageList objectAtIndex:indexPath.row];
    } else {
        DDLogError(@"Attempt to access beyond bounds");
    }

    //cut text after kMonalChatMaxAllowedTextLen chars to make the message cell work properly (too big texts don't render the text in the cell at all)
    NSString* messageText = row.messageText;
    MLAssert(messageText != nil, @"Message text must not be nil!", (@{@"row": nilWrapper(row)}));
    if([messageText length] > kMonalChatMaxAllowedTextLen)
        messageText = [NSString stringWithFormat:@"%@\n[...]", [messageText substringToIndex:kMonalChatMaxAllowedTextLen]];
    BOOL inboundDir = row.inbound;

    if([row.messageType isEqualToString:kMessageTypeStatus])
    {
        DDLogVerbose(@"got status cell cell: %@", messageText);
        cell = [tableView dequeueReusableCellWithIdentifier:@"StatusCell"];
        cell.messageBody.text = messageText;
        cell.link = nil;
        cell.parent = self;
        return cell;
    }
    if(cell == nil && [row.messageType isEqualToString:kMessageTypeFiletransfer])
    {
        DDLogVerbose(@"got filetransfer chat cell: %@ (%@)", row.filetransferMimeType, row.filetransferSize);
        NSDictionary* info = [MLFiletransfer getFileInfoForMessage:row];

        if(![info[@"needsDownloading"] boolValue])
        {
            DDLogVerbose(@"Filetransfer already downloaded: %@", info);
            cell = [self fileTransferCellCheckerWithInfo:info direction:inboundDir tableView:tableView andMsg:row];
        }
        else if([info[@"needsDownloading"] boolValue])
        {
            DDLogVerbose(@"Filetransfer needs downloading: %@", info);
            MLFileTransferDataCell* fileTransferCell = (MLFileTransferDataCell*)[self messageTableCellWithIdentifier:@"fileTransferCheckingData" andInbound:inboundDir fromTable:tableView];
            NSString* fileSize = info[@"size"] ? info[@"size"] : @"0";
            [fileTransferCell initCellForMessageId:row.messageDBId andFilename:info[@"filename"] andMimeType:info[@"mimeType"] andFileSize:fileSize.longLongValue];
            cell = fileTransferCell;
        }
    }
    if(cell == nil && [row.messageType isEqualToString:kMessageTypeUrl] && [[HelperTools defaultsDB] boolForKey:@"ShowURLPreview"])
    {
        DDLogVerbose(@"got link preview cell: %@", messageText);
        MLLinkCell* toreturn = (MLLinkCell*)[self messageTableCellWithIdentifier:@"link" andInbound:inboundDir fromTable: tableView];

        NSString* cleanLink = [messageText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSArray* parts = [cleanLink componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        toreturn.link = parts[0];
        row.url = [NSURL URLWithString:toreturn.link];
        toreturn.messageBody.text = toreturn.link;
        toreturn.messageHistoryId = row.messageDBId;

        if(row.previewText != nil || row.previewImage != nil)
        {
            if((row.previewText == nil || row.previewText.length == 0) && (row.previewImage == nil || row.previewImage.absoluteString.length == 0))
            {
                DDLogWarn(@"Not showing preview for %@, preview unavailable: row.previewText=%@, row.previewImage=%@", messageText, row.previewText, row.previewImage);
                toreturn = nil;     //no preview available: use default MLChatCell for this
            }
            else
            {
                DDLogVerbose(@"Using db cached preview for %@", toreturn.link);
                toreturn.imageUrl = row.previewImage;
                toreturn.messageTitle.text = row.previewText;
                [toreturn loadImageWithCompletion:^{}];
            }
        }
        else
        {
            DDLogVerbose(@"Loading link preview for %@", toreturn.link);
            [self loadPreviewWithUrlForRow:indexPath withResultHandler:^{
                DDLogVerbose(@"Reloading row for preview: %@", messageText);
                [[DataLayer sharedInstance] setMessageId:row.messageId previewText:[row.previewText copy] andPreviewImage:[row.previewImage.absoluteString copy]];
                //reload cells
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self->_messageTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                });
            }];
        }
        cell = toreturn;
    }
    if(cell == nil && [row.messageType isEqualToString:kMessageTypeGeo])
    {
        DDLogVerbose(@"got geo cell: %@", messageText);
        // Parse latitude and longitude
        NSError* error = NULL;
        NSRegularExpression* geoRegex = [NSRegularExpression regularExpressionWithPattern:geoPattern
        options:NSRegularExpressionCaseInsensitive
          error:&error];

        if(error != NULL) {
            DDLogError(@"Error while loading geoPattern");
        }

        NSTextCheckingResult* geoMatch = [geoRegex firstMatchInString:messageText options:0 range:NSMakeRange(0, [messageText length])];

        if(geoMatch.numberOfRanges > 0) {
            NSRange latitudeRange = [geoMatch rangeAtIndex:1];
            NSRange longitudeRange = [geoMatch rangeAtIndex:2];
            NSString* latitude = [messageText substringWithRange:latitudeRange];
            NSString* longitude = [messageText substringWithRange:longitudeRange];

            // Display inline map
            if([[HelperTools defaultsDB] boolForKey: @"ShowGeoLocation"]) {
                MLChatMapsCell* mapsCell = (MLChatMapsCell*)[self messageTableCellWithIdentifier:@"maps" andInbound:inboundDir fromTable: tableView];

                // Set lat / long used for map view and pin
                mapsCell.latitude = [latitude doubleValue];
                mapsCell.longitude = [longitude doubleValue];

                [mapsCell loadCoordinatesWithCompletion:^{}];
                cell = mapsCell;
            } else {
                // Default to text cell
                cell = [self messageTableCellWithIdentifier:@"text" andInbound:inboundDir fromTable: tableView];
                NSMutableAttributedString* geoString = [[NSMutableAttributedString alloc] initWithString:messageText];
                [geoString addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:[geoMatch rangeAtIndex:0]];

                cell.messageBody.attributedText = geoString;
                NSInteger zoomLayer = 15;
                cell.link = [NSString stringWithFormat:@"https://www.openstreetmap.org/?mlat=%@&mlon=%@&zoom=%ldd", latitude, longitude, zoomLayer];
            }
        } else {
            DDLogWarn(@"msgs of type kMessageTypeGeo should contain a geo location");
        }
    }
    if(cell == nil)
    {
        DDLogVerbose(@"got normal text cell: %@", messageText);
        // Use default text cell
        cell = (MLChatCell*)[self messageTableCellWithIdentifier:@"text" andInbound:inboundDir fromTable: tableView];

        //make sure everything is set to defaults
        cell.bubbleImage.hidden=NO;
        UIFont* originalFont = [UIFont systemFontOfSize:17.0f];
        [cell.messageBody setFont:originalFont];

        // Check if message contains a url
        NSString* lowerCase = [messageText lowercaseString];
        NSRange pos = [lowerCase rangeOfString:@"https://"];
        if(pos.location == NSNotFound) {
            pos = [lowerCase rangeOfString:@"http://"];
        }
        if(pos.location == NSNotFound) {
            pos = [lowerCase rangeOfString:@"xmpp:"];
        }

        NSRange pos2;
        if(pos.location != NSNotFound)
        {
            NSString* urlString = [messageText substringFromIndex:pos.location];
            pos2 = [urlString rangeOfString:@" "];
            if(pos2.location == NSNotFound) {
                pos2 = [urlString rangeOfString:@">"];
            }

            if(pos2.location != NSNotFound) {
                urlString = [urlString substringToIndex:pos2.location];
            }
            NSArray* parts = [urlString componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            cell.link = parts[0];

            if(cell.link) {
                NSMutableAttributedString *formattedString = [[NSMutableAttributedString alloc] initWithString:messageText];
                [formattedString addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:NSMakeRange(pos.location, cell.link.length)];
                cell.messageBody.text = nil;
                cell.messageBody.attributedText= formattedString;
            }
        }
        else // Default case
        {
            if(row.retracted)
            {
                NSString* stringToAttribute = NSLocalizedString(@"This message got retracted", @"");
                UIFont* italicFont = [UIFont italicSystemFontOfSize:cell.messageBody.font.pointSize];
                NSMutableAttributedString* attributedMsgString = [[NSMutableAttributedString alloc] initWithString:stringToAttribute];
                [attributedMsgString addAttribute:NSFontAttributeName value:italicFont range:NSMakeRange(0, stringToAttribute.length)];
                [cell.messageBody setAttributedText:attributedMsgString];
            }
            else if([MLEmoji containsEmojiWithText:messageText])
            {
                UIFont* originalFont = [UIFont systemFontOfSize:cell.messageBody.font.pointSize*3];
                [cell.messageBody setFont:originalFont];
                [cell.messageBody setAttributedText:nil];
                [cell.messageBody setText:messageText];
                cell.bubbleImage.hidden=YES;
            }
            else if([messageText hasPrefix:@"/me "])
            {
                UIFont* italicFont = [UIFont italicSystemFontOfSize:cell.messageBody.font.pointSize];

                NSMutableAttributedString* attributedMsgString = [[MLXEPSlashMeHandler sharedInstance] attributedStringSlashMeWithMessage:row andFont:italicFont];

                [cell.messageBody setAttributedText:attributedMsgString];
            }
            else
            {
                // Reset attributes
                UIFont* originalFont = [UIFont systemFontOfSize:cell.messageBody.font.pointSize];
                [cell.messageBody setFont:originalFont];
                [cell.messageBody setAttributedText:nil];
                [cell.messageBody setText:messageText];
            }
            cell.link = nil;
        }
    }
    MLMessage* priorRow = nil;
    if(indexPath.row > 0)
        priorRow = [self.messageList objectAtIndex:indexPath.row-1];
    // Only display names for groups
    BOOL hideName = YES;
    if(self.contact.isGroup)
    {
        if([@"group" isEqualToString:self.contact.mucType] && row.participantJid)
            hideName = (priorRow != nil && [priorRow.participantJid isEqualToString:row.participantJid]);
        else
            hideName = (priorRow != nil && [priorRow.actualFrom isEqualToString:row.actualFrom]);
        //((MLMessage*)row).contactDisplayName will automatically use row.actualFrom as fallback for group-type mucs
        //if no roster name or XEP-0172 nickname could be found and always use row.actualFrom for channel-type mucs
        cell.name.text = hideName == YES ? nil : row.contactDisplayName;
    }
    // remove hidden text for better constraints
    if(hideName == YES)
        cell.name.text = nil;
    cell.name.hidden = hideName;

    if(row.hasBeenDisplayed)
        cell.messageStatus.text = kDisplayed;
    else if(row.hasBeenReceived)
        cell.messageStatus.text = kReceived;
    else if(row.hasBeenSent)
        cell.messageStatus.text = kSent;
    else
        cell.messageStatus.text = kSending;

    cell.messageHistoryId = row.messageDBId;
    BOOL newSender = NO;
    if(indexPath.row > 0)
    {
        if(priorRow.inbound != row.inbound)
            newSender = YES;
    }
    cell.date.text = [self formattedTimeStampWithSource:row.timestamp];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    cell.dividerDate.text = [self formattedDateWithSource:row.timestamp andPriorDate:priorRow.timestamp];

    // Do not hide the lockImage if the message was encrypted
    cell.lockImage.hidden = !row.encrypted;
    // Set correct layout in/Outbound
    cell.outBound = !inboundDir;
    // Hide messageStatus on inbound messages
    cell.messageStatus.hidden = inboundDir;

    cell.parent = self;

    if(cell.outBound && ([row.errorType length] > 0 || [row.errorReason length] > 0) && !row.hasBeenReceived && row.hasBeenSent)
    {
        cell.messageStatus.text = NSLocalizedString(@"Error", @"");
        cell.deliveryFailed = YES;
    }

    [cell updateCellWithNewSender:newSender];

    if(!cell.link)
        [self resetHistoryAttributeForCell:cell];
    if(self.searchController.isActive && row.messageDBId)
    {
        if([self.searchController isDBIdExistent:row.messageDBId])
        {
            NSMutableAttributedString *attributedMsgString = [self.searchController doSearchKeyword:self.searchController.searchBar.text
                                                                                             onText:messageText
                                                                                         andInbound:inboundDir];
            [cell.messageBody setAttributedText:attributedMsgString];
        }
    }

    return cell;
}

-(MLContact*) getMLContactForJid:(NSString*) jid andAccount:(NSNumber*) accountNo
{
    NSString* cacheKey = [NSString stringWithFormat:@"%@|%@", jid, accountNo];
    @synchronized(_localMLContactCache) {
        if(_localMLContactCache[cacheKey])
            return _localMLContactCache[cacheKey];
        return _localMLContactCache[cacheKey] = [MLContact createContactFromJid:jid andAccountNo:accountNo];
    }
}

#pragma mark - tableview delegate
-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self stopEditing];
    [self.chatInput resignFirstResponder];
    if(indexPath.section == reloadBoxSection) {
        [self loadOldMsgHistory];
    } else if(indexPath.section == messagesSection) {
        MLBaseCell* cell = [tableView cellForRowAtIndexPath:indexPath];
        if(cell.link)
        {
            if([cell respondsToSelector:@selector(openlink:)]) {
                DDLogVerbose(@"Trying to open link in chat cell");
                [(MLChatCell *)cell openlink:self];
            } else  {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSDictionary* info = [MLFiletransfer getFileInfoForMessage:[self.messageList objectAtIndex:indexPath.row]];
                    UIViewController* imageViewer = [[SwiftuiInterface new] makeImageViewerForInfo:info];
                    imageViewer.modalPresentationStyle = UIModalPresentationOverFullScreen;
                    [self presentViewController:imageViewer animated:YES completion:^{}];
                });
            }
        }
    }
}

-(void) closePhotos {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark tableview datasource

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    if(indexPath.section == reloadBoxSection) {
        return NO;
    } else {
        return YES; // for now
    }
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
    if(indexPath.section == reloadBoxSection) {
        return NO;
    } else {
        return YES;
    }
}

-(UISwipeActionsConfiguration*) tableView:(UITableView*) tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath*) indexPath
{
    //stop editing (if there is some) on new swipe
    [self stopEditing];

    //don't allow swipe actions for our reload box
    if(indexPath.section == reloadBoxSection)
        return [UISwipeActionsConfiguration configurationWithActions:@[]];

    //do some sanity checks
    MLMessage* message;
    if((NSUInteger)indexPath.row < self.messageList.count)
        message = [self.messageList objectAtIndex:indexPath.row];
    else
    {
        DDLogError(@"Attempt to access beyond bounds");
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    if(message.messageDBId == nil)
        return [UISwipeActionsConfiguration configurationWithActions:@[]];

    //configure swipe actions

    UIContextualAction* LMCEditAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:NSLocalizedString(@"Edit", @"Chat msg action") handler:^(UIContextualAction* action, UIView* sourceView, void (^completionHandler)(BOOL actionPerformed)) {
        [self.chatInput setText:message.messageText];       //we want to begin editing using the old message
        self.placeHolderText.hidden = YES;
        weakify(self);
        self.editingCallback = ^(NSString* newBody) {
            strongify(self);
            self.editingCallback = nil;
            if(newBody != nil)
            {
                message.messageText = newBody;

                [self.xmppAccount sendMessage:newBody toContact:self.contact isEncrypted:(self.contact.isEncrypted || message.encrypted) isUpload:NO andMessageId:[[NSUUID UUID] UUIDString] withLMCId:message.messageId];
                [[DataLayer sharedInstance] updateMessageHistory:message.messageDBId withText:newBody];

                [self->_messageTable beginUpdates];
                [self->_messageTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                [self->_messageTable endUpdates];

                //update active chats if necessary
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:self.xmppAccount userInfo:@{@"contact": self.contact}];
            }
            else
            {
                self.placeHolderText.hidden = NO;
                [self.chatInput setText:@""];
            }
        };
        // We don't know yet if the editingCallback will complete successful. Pretend anyway
        return completionHandler(YES);
    }];
    LMCEditAction.backgroundColor = UIColor.systemYellowColor;
    LMCEditAction.image = [[[UIImage systemImageNamed:@"pencil.circle.fill"] imageWithHorizontallyFlippedOrientation] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAutomatic];

    UIContextualAction* quoteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:NSLocalizedString(@"Quote", @"Chat msg action") handler:^(UIContextualAction* action, UIView* sourceView, void (^completionHandler)(BOOL actionPerformed)) {
        NSMutableString* filteredString = [NSMutableString new];
        //first of all: filter out already quoted text
        [message.messageText enumerateLinesUsingBlock:^(NSString* _Nonnull line, BOOL* _Nonnull stop) {
            if(line.length > 0 && [[line substringToIndex:1] isEqualToString:@">"])
                return;
            [filteredString appendFormat:@"%@\n", line];
        }];
        NSMutableString* quoteString = [NSMutableString new];
        //add datetime before quoting message if message is older than 15 minutes and 8 messages
        NSDate* timestamp = [[DataLayer sharedInstance] returnTimestampForQuote:message.messageDBId];
        if(timestamp != nil)
        {
            [self.destinationDateFormat setDateStyle:NSDateFormatterMediumStyle];
            [self.destinationDateFormat setTimeStyle:NSDateFormatterShortStyle];
            [quoteString appendFormat:@"%@:\n", [self.destinationDateFormat stringFromDate:timestamp]];
        }
        //then: make sure we quote only trimmed message contents
        [[filteredString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] enumerateLinesUsingBlock:^(NSString* _Nonnull line, BOOL* _Nonnull stop) {
            [quoteString appendFormat:@"> %@\n", line];
        }];
        //Append new empty line after quote
        [quoteString appendString:@"\n"];
        //add already typed in text back in
        if(self.chatInput.text.length > 0) {
            [quoteString appendString:self.chatInput.text];
        }
        self.chatInput.text = quoteString;
        self.placeHolderText.hidden = YES;
        return completionHandler(YES);
    }];
    quoteAction.backgroundColor = UIColor.systemGreenColor;
    quoteAction.image = [[[UIImage systemImageNamed:@"quote.bubble.fill"] imageWithHorizontallyFlippedOrientation] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAutomatic];

    UIContextualAction* retractAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:NSLocalizedString(@"Retract", @"Chat msg action") handler:^(UIContextualAction* action, UIView* sourceView, void (^completionHandler)(BOOL actionPerformed)) {
        [self.xmppAccount retractMessage:message.messageId toContact:self.contact];
        [[DataLayer sharedInstance] deleteMessageHistory:message.messageDBId];
        [message updateWithMessage:[[[DataLayer sharedInstance] messagesForHistoryIDs:@[message.messageDBId]] firstObject]];

        //update table entry
        [self->_messageTable beginUpdates];
        [self->_messageTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        [self->_messageTable endUpdates];
        
        //update active chats if necessary
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:self.xmppAccount userInfo:@{@"contact": self.contact}];

        return completionHandler(YES);
    }];
    retractAction.backgroundColor = UIColor.systemRedColor;
    retractAction.image = [[[UIImage systemImageNamed:@"arrow.uturn.backward.circle.fill"] imageWithHorizontallyFlippedOrientation] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAutomatic];

    UIContextualAction* localDeleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:NSLocalizedString(@"Delete", @"Chat msg action") handler:^(UIContextualAction* action, UIView* sourceView, void (^completionHandler)(BOOL actionPerformed)) {
        [[DataLayer sharedInstance] deleteMessageHistoryLocally:message.messageDBId];

        [self->_messageTable beginUpdates];
        [self.messageList removeObjectAtIndex:indexPath.row];
        [self->_messageTable deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationRight];
        [self->_messageTable endUpdates];

        //update active chats if necessary
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:self.xmppAccount userInfo:@{@"contact": self.contact}];

        return completionHandler(YES);
    }];
    localDeleteAction.backgroundColor = UIColor.systemYellowColor;
    localDeleteAction.image = [[[UIImage systemImageNamed:@"trash.circle.fill"] imageWithHorizontallyFlippedOrientation] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAutomatic];

    UIContextualAction* copyAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:NSLocalizedString(@"Copy", @"Chat msg action") handler:^(UIContextualAction* action, UIView* sourceView, void (^completionHandler)(BOOL actionPerformed)) {
        UIPasteboard* pasteboard = [UIPasteboard generalPasteboard];
        MLBaseCell* selectedCell = [self.messageTable cellForRowAtIndexPath:indexPath];
        if([selectedCell isKindOfClass:[MLChatImageCell class]])
            pasteboard.image = [(MLChatImageCell*)selectedCell getDisplayedImage];
        else if([selectedCell isKindOfClass:[MLLinkCell class]])
            pasteboard.URL = [NSURL URLWithString:((MLLinkCell*)selectedCell).link];
        else
            pasteboard.string = message.messageText;
        return completionHandler(YES);
    }];
    copyAction.backgroundColor = UIColor.systemGreenColor;
    copyAction.image = [[[UIImage systemImageNamed:@"doc.on.doc.fill"] imageWithHorizontallyFlippedOrientation] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAutomatic];

    //only allow editing for the 3 newest message && only on outgoing messages
    if(!message.inbound && [[DataLayer sharedInstance] checkLMCEligible:message.messageDBId encrypted:(message.encrypted || self.contact.isEncrypted) historyBaseID:nil])
        return [UISwipeActionsConfiguration configurationWithActions:@[
            quoteAction,
            copyAction,
            LMCEditAction,
            retractAction,
        ]];
    //only allow retraction for outgoing messages
    else if(!message.inbound)
        return [UISwipeActionsConfiguration configurationWithActions:@[
            quoteAction,
            copyAction,
            retractAction,
        ]];
    else
        return [UISwipeActionsConfiguration configurationWithActions:@[
            quoteAction,
            copyAction,
            localDeleteAction,
        ]];
}

-(MLBaseCell*) fileTransferCellCheckerWithInfo:(NSDictionary*)info direction:(BOOL)inDirection tableView:(UITableView*)tableView andMsg:(MLMessage*)row{
    MLBaseCell *cell = nil;
    if([info[@"mimeType"] hasPrefix:@"image/"])
    {
        MLChatImageCell* imageCell = (MLChatImageCell *)[self messageTableCellWithIdentifier:@"image" andInbound:inDirection fromTable:tableView];
        [imageCell initCellWithMLMessage:row];
        cell = imageCell;
    }
    else if([info[@"mimeType"] hasPrefix:@"video/"])
    {
        MLFileTransferVideoCell* videoCell = (MLFileTransferVideoCell *) [self messageTableCellWithIdentifier:@"fileTransferVideo" andInbound:inDirection fromTable:tableView];
        NSString* videoStr = info[@"cacheFile"];
        NSString* videoFileName = info[@"filename"];
        [videoCell avplayerConfigWithUrlStr:videoStr andMimeType:info[@"mimeType"] fileName:videoFileName andVC:self];

        cell = videoCell;
    }
    else if([info[@"mimeType"] hasPrefix:@"audio/"])
    {
        //we may wan to make a new kind later but for now this is perfectly functional
        MLFileTransferVideoCell* audioCell = (MLFileTransferVideoCell *) [self messageTableCellWithIdentifier:@"fileTransferAudio" andInbound:inDirection fromTable:tableView];
        NSString *audioStr = info[@"cacheFile"];
        NSString *audioFileName = info[@"filename"];
        [audioCell avplayerConfigWithUrlStr:audioStr andMimeType:info[@"mimeType"] fileName:audioFileName andVC:self];

        cell = audioCell;
    }
    else
    {
        MLFileTransferTextCell* textCell = (MLFileTransferTextCell *) [self messageTableCellWithIdentifier:@"fileTransferText" andInbound:inDirection fromTable:tableView];

        NSString *fileSizeStr = info[@"size"];
        long long fileSizeLongLongValue = fileSizeStr.longLongValue;
        NSString *readableFileSize = [NSByteCountFormatter stringFromByteCount:fileSizeLongLongValue
                                                                    countStyle:NSByteCountFormatterCountStyleFile];
        NSString *hintStr = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"Open", @""), info[@"filename"]];
        NSString *fileCacheUrlStr = info[@"cacheFile"];
        textCell.fileCacheUrlStr = fileCacheUrlStr;

        NSUInteger countOfMimtTypeComponent = [info[@"mimeType"] componentsSeparatedByString:@";"].count;
        NSString* fileMimeType = @"";
        NSString* fileCharSet = @"";
        NSString* fileEncodeName = @"utf-8";
        if (countOfMimtTypeComponent > 1)
        {
            fileMimeType = [info[@"mimeType"] componentsSeparatedByString:@";"].firstObject;
            fileCharSet = [info[@"mimeType"] componentsSeparatedByString:@";"].lastObject;
        }
        else
        {
            fileMimeType = info[@"mimeType"];
        }

        if (fileCharSet != nil && fileCharSet.length > 0)
        {
            fileEncodeName = [fileCharSet componentsSeparatedByString:@"="].lastObject;
        }

        textCell.fileMimeType = fileMimeType;
        textCell.fileName = info[@"filename"];
        textCell.fileEncodeName = fileEncodeName;
        [textCell.fileTransferHint setText:hintStr];
        [textCell.sizeLabel setText:readableFileSize];
        textCell.openFileDelegate = self;
        cell = textCell;
    }

    return cell;
}

//dummy function needed to remove warnign
-(void) openlink: (id) sender {

}

-(void) scrollViewDidScroll:(UIScrollView *)scrollView
{
    // Only load old msgs if the view appeared
    if(!self.viewDidAppear)
        return;

    // get current scroll position (y-axis)
    CGFloat curOffset = scrollView.contentOffset.y;

    if (self.lastOffset > curOffset)
    {
        [self.lastMsgButton setHidden:NO];
    }

    CGFloat bottomLength = scrollView.frame.size.height + curOffset;

    if (scrollView.contentSize.height <= bottomLength)
    {
        [self.lastMsgButton setHidden:YES];
    }

    self.lastOffset = curOffset;
}

-(void) loadOldMsgHistory
{
    [self.messageTable.refreshControl beginRefreshing];
    [self loadOldMsgHistory:self.messageTable.refreshControl];
}

-(void) loadOldMsgHistory:(id) sender
{
    // Load older messages from db
    NSMutableArray* oldMessages = nil;
    NSNumber* beforeId = nil;
    if(self.messageList.count > 0)
        beforeId = ((MLMessage*)[self.messageList objectAtIndex:0]).messageDBId;
    oldMessages = [[DataLayer sharedInstance] messagesForContact:self.contact.contactJid forAccount:self.contact.accountId beforeMsgHistoryID:beforeId];

    if(!self.isLoadingMam && [oldMessages count] < kMonalBackscrollingMsgCount)
    {
        self.isLoadingMam = YES;        //don't allow multiple parallel mam fetches

        //not all messages in history db have a stanzaId (messages sent by this monal instance won't have one for example)
        //--> search for the oldest message having a stanzaId and use that one
        NSString* oldestStanzaId;
        for(MLMessage* msg in oldMessages)
            if(msg.stanzaId)
            {
                DDLogVerbose(@"Found oldest stanzaId in messages returned from db: %@", msg.stanzaId);
                oldestStanzaId = msg.stanzaId;
                break;
            }
        if(!oldestStanzaId)
        {
            for(MLMessage* msg in self.messageList)
            {
                if(msg.stanzaId)
                {
                    DDLogVerbose(@"Found oldest stanzaId in messages already displayed: %@", msg.stanzaId);
                    oldestStanzaId = msg.stanzaId;
                    break;
                }
            }
        }
        
        //history database for this contact is completely empty, use global last stanza id for this mam archive
        if(oldestStanzaId == nil)
        {
            if(self.contact.isGroup)
                oldestStanzaId = [[DataLayer sharedInstance] lastStanzaIdForMuc:self.contact.contactJid andAccount:self.contact.accountId];
            else
                oldestStanzaId = [[DataLayer sharedInstance] lastStanzaIdForAccount:self.contact.accountId];
        }

        //now load more (older) messages from mam
        DDLogVerbose(@"Loading more messages from mam before stanzaId %@", oldestStanzaId);
        weakify(self);
        [self.xmppAccount setMAMQueryMostRecentForContact:self.contact before:oldestStanzaId withCompletion:^(NSArray* _Nullable messages, NSString* _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                strongify(self);
                if(!messages && !error)
                {
                    //xmpp account got reconnected
                    DDLogError(@"Got backscrolling mam error: nil (possible reconnect while querying)");
                    UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Could not fetch messages", @"") message:NSLocalizedString(@"The connection to the server was interrupted and no old messages could be fetched for this chat. Please try again later.", @"") preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        [alert dismissViewControllerAnimated:YES completion:nil];
                    }]];
                    [self presentViewController:alert animated:YES completion:nil];
                }
                else if(!messages)
                {
                    NSString* errorText = error;
                    if(!error)
                        errorText = NSLocalizedString(@"Unknown error!", @"");
                    DDLogError(@"Got backscrolling mam error: %@", errorText);
                    UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Could not fetch messages", @"") message:[NSString stringWithFormat:NSLocalizedString(@"Could not fetch (all) old messages for this chat from your server archive. Please try again later. %@", @""), errorText] preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        [alert dismissViewControllerAnimated:YES completion:nil];
                    }]];
                    [self presentViewController:alert animated:YES completion:nil];
                }
                else
                {
                    DDLogVerbose(@"Got backscrolling mam response: %lu", (unsigned long)[messages count]);
                    if([messages count] == 0)
                    {
                        self.moreMessagesAvailable = NO;
                        
                        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Finished fetching messages", @"") message:NSLocalizedString(@"All messages fetched successfully, there are no more left on the server!", @"") preferredStyle:UIAlertControllerStyleAlert];
                        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                            [alert dismissViewControllerAnimated:YES completion:nil];
                        }]];
                        [self presentViewController:alert animated:YES completion:nil];
                    }
                    else
                        [self insertOldMessages:[[messages reverseObjectEnumerator] allObjects]];
                }
                //allow next mam fetch
                self.isLoadingMam = NO;
                if(sender)
                    [(UIRefreshControl*)sender endRefreshing];
            });
        }];
    }
    else if(!self.isLoadingMam && [oldMessages count] >= kMonalBackscrollingMsgCount)
    {
        if(sender)
            [(UIRefreshControl*)sender endRefreshing];
    }

    //insert everything we got from the db so far
    if(oldMessages && [oldMessages count] > 0)
    {
        //use reverse order to insert messages from newest to oldest (bottom to top in chatview)
        [self insertOldMessages:[[oldMessages reverseObjectEnumerator] allObjects]];
    }
    else
    {
        [self doSetNotLoadingHistory];
    }
}

-(void) insertOldMessages:(NSArray*) oldMessages
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if(!self.messageList)
            self.messageList = [NSMutableArray new];

        CGSize sizeBeforeAddingMessages = [self->_messageTable contentSize];
        // Insert old messages into messageTable
        NSMutableArray* indexArray = [NSMutableArray array];
        for(size_t msgIdx = 0; msgIdx < [oldMessages count]; msgIdx++)
        {
            MLMessage* msg = [oldMessages objectAtIndex:msgIdx];
            [self.messageList insertObject:msg atIndex:0];
            NSIndexPath* newIndexPath = [NSIndexPath indexPathForRow:msgIdx inSection:messagesSection];
            [indexArray addObject:newIndexPath];
        }
        [self->_messageTable beginUpdates];
        [self->_messageTable insertRowsAtIndexPaths:indexArray withRowAnimation:UITableViewRowAnimationNone];
        // keep old position - scrolling may stop
        CGSize sizeAfterAddingMessages = [self->_messageTable contentSize];
        CGPoint contentOffset = self->_messageTable.contentOffset;
        CGPoint newOffset = CGPointMake(contentOffset.x, contentOffset.y + sizeAfterAddingMessages.height - sizeBeforeAddingMessages.height);
        self->_messageTable.contentOffset = newOffset;
        [self->_messageTable endUpdates];

        [self doSetNotLoadingHistory];
    });
}

-(BOOL) canBecomeFirstResponder
{
    return YES;
}

-(UIView *) inputAccessoryView
{
    return self.inputContainerView;
}

// Add new line to chatInput with 'shift + enter'
-(void) shiftEnterKeyPressed:(UIKeyCommand*)keyCommand
{
    if([self.chatInput isFirstResponder]) {
        // Get current cursor postion
        NSRange pos = [self.chatInput selectedRange];
        // Insert \n
        self.chatInput.text = [self.chatInput.text stringByReplacingCharactersInRange:pos withString:@"\n"];
    }
}

// Send message with 'enter' if chatInput is first repsonder
-(void) enterKeyPressed:(UIKeyCommand*)keyCommand
{
    if([self.chatInput isFirstResponder]) {
        [self resignTextView];
    }
}

// Open contact details
-(void) commandIPressed:(UIKeyCommand*)keyCommand
{
    [self performSegueWithIdentifier:@"showDetails" sender:self];
}

// Open search ViewController
-(void) commandFPressed:(UIKeyCommand*)keyCommand
{
    [self showSeachButtonAction];
}

// List of custom hardware key commands
- (NSArray<UIKeyCommand *> *)keyCommands {
    // shift + enter
    UIKeyCommand* shiftEnterKey = [UIKeyCommand keyCommandWithInput:@"\r" modifierFlags:UIKeyModifierShift action:@selector(shiftEnterKeyPressed:)];
    // enter
    UIKeyCommand* enterKey = [UIKeyCommand keyCommandWithInput:@"\r" modifierFlags:0 action:@selector(enterKeyPressed:)];
    UIKeyCommand* escapeKey = [UIKeyCommand
                               keyCommandWithInput:UIKeyInputEscape modifierFlags:0 action:@selector(closePhotos)];
    // prefer our key commands over the system defaults
    if (@available(iOS 15.0, macCatalyst 15.0, *)) {
        shiftEnterKey.wantsPriorityOverSystemBehavior = true;
        enterKey.wantsPriorityOverSystemBehavior = true;
    }
    return @[
            shiftEnterKey,
            enterKey,
            escapeKey,
            // command + i
            [UIKeyCommand keyCommandWithInput:@"i" modifierFlags:UIKeyModifierCommand action:@selector(commandIPressed:)],
            // command + f
            [UIKeyCommand keyCommandWithInput:@"f" modifierFlags:UIKeyModifierCommand action:@selector(commandFPressed:)]
    ];
}

# pragma mark - Textview delegate functions

- (void)textViewDidBeginEditing:(UITextView *)textView
{
    [self scrollToBottom];
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    BOOL shouldInsert = YES;

    // Notify that we are typing
    [self sendChatState:YES];

    // Limit text length to kMonalChatMaxAllowedTextLen
    if([text isEqualToString:@""]) {
        shouldInsert &= YES;
    } else {
        shouldInsert &= (range.location + range.length < kMonalChatMaxAllowedTextLen);
    }
    shouldInsert &= ([textView.text length] + [text length] - range.length <= kMonalChatMaxAllowedTextLen);

    return shouldInsert;
}

- (void)textViewDidChange:(UITextView *)textView
{
    if(textView.text.length > 0)
        self.placeHolderText.hidden = YES;
    else
        self.placeHolderText.hidden = NO;

    [self setSendButtonIconWithTextLength:[textView.text length]];
}

-(void) setSendButtonIconWithTextLength:(NSUInteger)txtLength
{
#if TARGET_OS_MACCATALYST
    self.isAudioMessage = NO;
    [self.audioRecordButton setHidden:YES];
    [self.sendButton setHidden:NO];
#else
    if ((txtLength == 0) && (self.uploadQueue.count == 0))
    {
        self.isAudioMessage = YES;
        [self.audioRecordButton setHidden:NO];
        [self.sendButton setHidden:YES];
    }
    else
    {
        self.isAudioMessage = NO;
        [self.audioRecordButton setHidden:YES];
        [self.sendButton setHidden:NO];
    }
#endif
}

#pragma mark - link preview

-(void) loadPreviewWithUrlForRow:(NSIndexPath *) indexPath withResultHandler:(monal_void_block_t) resultHandler
{
    MLMessage* row;
    if((NSUInteger)indexPath.row < self.messageList.count)
        row = [self.messageList objectAtIndex:indexPath.row];
    else
    {
        DDLogError(@"Attempt to access beyond bounds");
        return;
    }

    //prevent duplicated calls from cell animations (don't call resultHandler in this case because the resultHandler would reload the row)
    if([self.previewedIds containsObject:row.messageDBId])
    {
        DDLogDebug(@"Not loading preview for already pending row: %@ in %@", row.messageDBId, self.previewedIds);
        return;
    }
    [self.previewedIds addObject:row.messageDBId];

    row.previewText = @"";
    row.previewImage = [NSURL URLWithString:@""];
    if(row.url)
    {
        DDLogVerbose(@"Fetching HTTP HEAD for %@...", row.url);
        NSMutableURLRequest* headRequest = [[NSMutableURLRequest alloc] initWithURL:row.url];
        headRequest.HTTPMethod = @"HEAD";
        headRequest.cachePolicy = NSURLRequestReturnCacheDataElseLoad;
        NSURLSession* session = [NSURLSession sharedSession];
        [[session dataTaskWithRequest:headRequest completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
            if(error != nil)
            {
                DDLogWarn(@"Loding preview HEAD for %@ failed: %@", row.url, error);
                resultHandler();
                return;
            }
            
            NSDictionary* headers = ((NSHTTPURLResponse*)response).allHeaderFields;
            NSString* mimeType = [[headers objectForKey:@"Content-Type"] lowercaseString];
            NSNumber* contentLength = [headers objectForKey:@"Content-Length"] ? [NSNumber numberWithInt:([[headers objectForKey:@"Content-Length"] intValue])] : @(-1);
            
            if(mimeType.length==0)
            {
                DDLogWarn(@"Loding preview HEAD for %@ failed: mimeType unkown", row.url);
                resultHandler();
                return;
            }
            //preview images, too
            if([mimeType hasPrefix:@"image/"])
            {
                DDLogVerbose(@"Now loading image preview data for: %@", row.url);
                row.previewText = [row.url lastPathComponent];
                row.previewImage = row.url;
                resultHandler();
                return;
            }
            if(![mimeType hasPrefix:@"text/"])
            {
                DDLogWarn(@"Loding HEAD preview for %@ failed: mimeType not supported: %@", row.url, mimeType);
                resultHandler();
                return;
            }
            //limit to 512KB of html
            if(contentLength.intValue > 524288)
            {
                DDLogWarn(@"Now loading preview HTML for %@ with byte range 0-512k...", row.url);
                [self downloadPreviewWithRow:indexPath usingByterange:YES andResultHandler:resultHandler];
                return;
            }
            
            DDLogVerbose(@"Now loading preview for: %@", row.url);
            [self downloadPreviewWithRow:indexPath usingByterange:NO andResultHandler:resultHandler];
        }] resume];
    }
    else if(resultHandler)
    {
        DDLogWarn(@"Not loading HEAD preview for '%@': no url given!", row.url);
        resultHandler();
    }
}

-(void) downloadPreviewWithRow:(NSIndexPath*) indexPath usingByterange:(BOOL) useByterange andResultHandler:(monal_void_block_t) resultHandler
{
    MLMessage* row;
    if((NSUInteger)indexPath.row < self.messageList.count)
        row = [self.messageList objectAtIndex:indexPath.row];
    else
    {
        DDLogError(@"Attempt to access beyond bounds");
        return;
    }

    /**
     <meta property="og:title" content="Nintendo recommits to “keep the business going” for 3DS">
     <meta property="og:image" content="https://cdn.arstechnica.net/wp-content/uploads/2016/09/3DS_SuperMarioMakerforNintendo3DS_char_01-760x380.jpg">
     facebookexternalhit/1.1
     */
    DDLogVerbose(@"Fetching HTTP GET for %@...", row.url);
    NSMutableURLRequest* request = [[NSMutableURLRequest alloc] initWithURL:row.url];
    [request setValue:@"facebookexternalhit/1.1" forHTTPHeaderField:@"User-Agent"]; //required on some sites for og tags e.g. youtube
    if(useByterange)
        [request setValue:@"bytes=0-524288" forHTTPHeaderField:@"Range"];
    request.timeoutInterval = 10;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
        if(error != nil)
            DDLogVerbose(@"preview fetching error: %@", error);
        else
        {
            NSString* body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSURL* baseURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@%@", row.url.scheme, row.url.host, row.url.path]];
            MLOgHtmlParser* ogParser = [[MLOgHtmlParser alloc] initWithHtml:body andBaseUrl:baseURL];
            NSString* text = nil;
            NSURL* image = nil;
            if(ogParser != nil)
            {
                text = [ogParser getOgTitle];
                image = [ogParser getOgImage];
            }
            else
                DDLogError(@"Could not create OG parser!");
            if((text != nil && text.length > 0) || (image != nil && image.absoluteString.length > 0))
            {
                DDLogVerbose(@"Preview of %@: title=%@, image=%@", row.url, text, image);
                row.previewText = text;
                row.previewImage = image;
            }
            else
            {
                DDLogWarn(@"Preview of %@ is empty!", row.url);
                row.previewText = @"";
                row.previewImage = [NSURL URLWithString:@""];
            }
        }
        [self.previewedIds removeObject:row.messageDBId];
        resultHandler();
    }] resume];
}

#pragma mark - Keyboard

- (void)keyboardWillDisappear:(NSNotification*) aNotification
{
    [self setChatInputHeightConstraints:YES];
}

- (void)keyboardDidShow:(NSNotification*)aNotification
{
      //TODO grab animation info
    NSDictionary* info = [aNotification userInfo];
    CGSize kbSize = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    if(kbSize.height > 100) { //my inputbar +any other
        self.hardwareKeyboardPresent = NO;
    }
    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0, 0.0, kbSize.height - 10, 0.0);
    self.messageTable.contentInset = contentInsets;
    self.messageTable.scrollIndicatorInsets = contentInsets;

    // Only scroll to bottom of the message table if a chat is opened
    // don't scroll down on other events like closing a image preview
    if(self.viewDidAppear == NO)
        [self scrollToBottom];
}

- (void)keyboardDidHide:(NSNotification*)aNotification
{
    [self saveMessageDraft];
    [self sendChatState:NO];

    UIEdgeInsets contentInsets = UIEdgeInsetsZero;
    self.messageTable.contentInset = contentInsets;
    self.messageTable.scrollIndicatorInsets = contentInsets;
}

- (void)keyboardWillShow:(NSNotification*)aNotification
{
    [self setChatInputHeightConstraints:NO];
    //TODO grab animation info
//    UIEdgeInsets contentInsets = UIEdgeInsetsZero;
//    self.messageTable.contentInset = contentInsets;
//    self.messageTable.scrollIndicatorInsets = contentInsets;
}

-(void) tempfreezeAutoloading
{
    // Allow  autoloading of more messages after a few seconds
    self.viewIsScrolling = YES;
    createTimer(1.5, (^{
        self.viewIsScrolling = NO;
    }));
}

-(void) stopEditing
{
    if(self.editingCallback)
        self.editingCallback(nil);      //dismiss swipe action
}

-(void) showUploadHUD
{
    if(!self.uploadHUD)
    {
        self.uploadHUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        self.uploadHUD.removeFromSuperViewOnHide = YES;
        self.uploadHUD.label.text = NSLocalizedString(@"Uploading", @"");
        self.uploadHUD.detailsLabel.text = NSLocalizedString(@"Uploading file to server", @"");
    }
    else
        self.uploadHUD.hidden = NO;
}

-(void) hideUploadHUD
{
    self.uploadHUD.hidden = YES;
}

-(void) showPotentialError:(NSError*) error
{
    if(error)
    {
        DDLogError(@"Could not send attachment: %@", error);
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Could not upload file", @"") message:[NSString stringWithFormat:@"%@", error.localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

#pragma mark - MLFileTransferTextCell delegate
-(void) showData:(NSString *)fileUrlStr withMimeType:(NSString *)mimeType andFileName:(NSString * _Nonnull)fileName andFileEncodeName:(NSString * _Nonnull)encodeName
{
    MLFileTransferFileViewController *fileViewController = [MLFileTransferFileViewController new];
    fileViewController.fileUrlStr = fileUrlStr;
    fileViewController.mimeType = mimeType;
    fileViewController.fileName = fileName;
    fileViewController.fileEncodeName = encodeName;
    [self presentViewController:fileViewController animated:NO completion:nil];
//    [self.navigationController pushViewController:fileViewController animated:NO];
}

#pragma mark - MLAudioRecoderManager delegate
-(void) notifyStart
{
    dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat infoHeight = self.inputContainerView.frame.size.height;
        CGFloat infoWidth = self.inputContainerView.frame.size.width;

        UIColor* labelBackgroundColor = self.inputContainerView.backgroundColor;
        self.audioRecoderInfoView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, infoWidth - 50, infoHeight)];
        self.audioRecoderInfoView.backgroundColor = labelBackgroundColor;
        UILabel *audioTimeInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 0, infoWidth - 50, infoHeight)];
        [audioTimeInfoLabel setText:NSLocalizedString(@"Recording audio", @"")];
        [self.audioRecoderInfoView addSubview:audioTimeInfoLabel];
        [self.inputContainerView addSubview:self.audioRecoderInfoView];
        
        [self.audioButton setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
        [self.audioButton setTitleColor:[UIColor redColor] forState:UIControlStateHighlighted];
        [self.audioButton setTitleColor:[UIColor redColor] forState:UIControlStateSelected];
    });
}

-(void) notifyStop:(NSURL* _Nullable) fileURL
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_isRecording = NO;
        [self.audioRecoderInfoView removeFromSuperview];
        [self.audioButton setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
        [self.audioButton setTitleColor:[UIColor blueColor] forState:UIControlStateHighlighted];
        [self.audioButton setTitleColor:[UIColor blueColor] forState:UIControlStateSelected];

        if(fileURL != nil)
            [self showUploadHUD];
    });
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        NSFileCoordinator* coordinator = [NSFileCoordinator new];

        [coordinator coordinateReadingItemAtURL:fileURL options:NSFileCoordinatorReadingForUploading error:nil byAccessor:^(NSURL * _Nonnull newURL) {
            [MLFiletransfer uploadFile:newURL onAccount:self.xmppAccount withEncryption:self.contact.isEncrypted andCompletion:^(NSString* url, NSString* mimeType, NSNumber* size, NSError* error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showPotentialError:error];
                    if(!error)
                    {
                        NSString* newMessageID = [[NSUUID UUID] UUIDString];
                        MLMessage* msg = [self addMessageto:self.contact.contactJid withMessage:url andId:newMessageID messageType:kMessageTypeFiletransfer mimeType:mimeType size:size];
                        [[MLXMPPManager sharedInstance] sendMessage:url toContact:self.contact isEncrypted:self.contact.isEncrypted isUpload:YES messageId:newMessageID withCompletionHandler:^(BOOL success, NSString *messageId) {
                            DDLogInfo(@"File upload sent to contact...");
                            [MLFiletransfer hardlinkFileForMessage:msg];        //hardlink cache file if possible
                            [self hideUploadHUD];
                        }];
                    }
                    DDLogVerbose(@"upload done");
                });
            }];
        }];
    });
}

-(void) updateCurrentTime:(NSTimeInterval) audioDuration
{
    int durationMinutes = (int)audioDuration/60;
    int durationSeconds = (int)audioDuration - durationMinutes*60;

    for (UIView* subview in self.audioRecoderInfoView.subviews) {
        if([subview isKindOfClass:[UILabel class]]){
            UILabel *infoLabel = (UILabel*)subview;
            [infoLabel setText:[NSString stringWithFormat:NSLocalizedString(@"%02d:%02d (long press to abort)", @""), durationMinutes, durationSeconds]];
            [infoLabel setTextColor:[UIColor blackColor]];
        }
    }
}

-(void) notifyResult:(BOOL)isSuccess error:(NSString*) errorMsg
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_isRecording = NO;
        NSString* alertTitle = @"";
        if(isSuccess) {
            alertTitle = NSLocalizedString(@"Recode Success", @"");
        } else {
            alertTitle = [NSString stringWithFormat:@"%@%@", NSLocalizedString(@"Recode Fail:", @""), errorMsg];
        }

        UIAlertController* audioRecoderAlert = [UIAlertController alertControllerWithTitle:alertTitle
                                                                            message:@"" preferredStyle:UIAlertControllerStyleAlert];

        [self presentViewController:audioRecoderAlert animated:YES completion:^{
            dispatch_queue_t queue = dispatch_get_main_queue();
            dispatch_after(2.0, queue, ^{
                [audioRecoderAlert dismissViewControllerAnimated:YES completion:nil];
            });
        }];
    });
}

# pragma mark - Upload Queue (Backend)

-(void) handleMediaUploadCompletion:(NSString*) url withMime:(NSString*) mimeType withSize:(NSNumber*) size withError:(NSError*) error
{
    monal_void_block_t handleNextUpload = ^{
        if(self.uploadQueue.count > 0)
        {
            [self.uploadMenuView performBatchUpdates:^{
                [self deleteQueueItemAtIndex:0];
            } completion:^(BOOL finished){
                [self emptyUploadQueue];
            }];
        }
        else
        {
            [self hideUploadQueue];
            [self hideUploadHUD];
        }
    };
    DDLogVerbose(@"Now in upload completion");
    [self showPotentialError:error];
    if(!error)
    {
        NSString* newMessageID = [[NSUUID UUID] UUIDString];
        MLMessage* msg = [self addMessageto:self.contact.contactJid withMessage:url andId:newMessageID messageType:kMessageTypeFiletransfer mimeType:mimeType size:size];
        [[MLXMPPManager sharedInstance] sendMessage:url toContact:self.contact isEncrypted:self.contact.isEncrypted isUpload:YES messageId:newMessageID withCompletionHandler:^(BOOL success, NSString *messageId) {
            DDLogInfo(@"File upload sent to contact...");
            [MLFiletransfer hardlinkFileForMessage:msg];        //hardlink cache file if possible
            handleNextUpload();
        }];
        DDLogInfo(@"upload done");
    }
    else
        handleNextUpload();
}

-(void) emptyUploadQueue
{
    if(self.uploadQueue.count == 0)
    {
        [self hideUploadQueue];
        [self hideUploadHUD];
        return;
    }
    MLAssert(self.uploadQueue.count >= 1, @"upload queue contains less than 1 element");
    [self showUploadHUD];

    NSDictionary* payload = self.uploadQueue.firstObject;
    MLAssert([payload[@"type"] isEqualToString:@"image"] || [payload[@"type"] isEqualToString:@"file"] || [payload[@"type"] isEqualToString:@"contact"] || [payload[@"type"] isEqualToString:@"audiovisual"], @"Payload type must be of type image, file contact or audiovisual!", payload);
    
    DDLogVerbose(@"start dispatch");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        $call(payload[@"data"], $ID(account, self.xmppAccount), $BOOL(encrypted, self.contact.isEncrypted), $ID(completion, (^(NSString* url, NSString* mimeType, NSNumber* size, NSError* error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if(error != nil)
                    [self handleMediaUploadCompletion:nil withMime:nil withSize:nil withError:error];
                else
                    [self handleMediaUploadCompletion:url withMime:mimeType withSize:size withError:error];
            });
        })));
    });
}

# pragma mark - Upload Queue (UI)
-(void) showUploadQueue
{
    self.uploadMenuConstraint.constant = 180;
    self.uploadMenuView.hidden = NO;
}

-(void) hideUploadQueue
{
    [self setSendButtonIconWithTextLength:[self.chatInput.text length]];
    self.uploadMenuConstraint.constant = 1; // Can't set this to 0, because this will disable the view. If this were to happen, we would not use an accurate queue count if a user empties the queue and fills it afterwards. This is a hack to prevent this behaviour
    self.uploadMenuView.hidden = YES;
}

-(void) deleteQueueItemAtIndex:(NSUInteger) index
{
    if(self.uploadQueue.count == 1) // Delete last object in queue
    {
        [self.uploadMenuView deleteItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:index + 1 inSection:0]]]; // Delete '+' icon if queue is empty
    }
    [self.uploadQueue removeObjectAtIndex:index];
    [self.uploadMenuView deleteItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:index inSection:0]]];
}

-(void) addToUIQueue:(NSArray<NSDictionary*>*) newItems
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if(self.uploadQueue.count == 0 && newItems.count > 0) // Queue was previously empty but will be filled now
        {
            // Force reload of view because this fails after the queue was emptied once otherwise.
            // The '+' cell may also not be in the collection view yet when this function is called.
            [CATransaction begin];
            [UIView setAnimationsEnabled:NO];
            [self showUploadQueue];
            [self.uploadMenuView performBatchUpdates:^{
                [self.uploadQueue addObjectsFromArray:newItems];
                NSMutableArray<NSIndexPath*>* newInd = [[NSMutableArray<NSIndexPath*> alloc] initWithCapacity:newItems.count + 1];
                for(NSUInteger i = 0; i <= newItems.count; i++)
                {
                    newInd[i] = [NSIndexPath indexPathForItem:i inSection:0];
                }
                DDLogVerbose(@"Inserting items at index paths: %@", newInd);
                [self.uploadMenuView insertItemsAtIndexPaths:newInd];
            } completion:^(BOOL finished) {
                [CATransaction commit];
                [UIView setAnimationsEnabled:YES];
                [self setSendButtonIconWithTextLength:[self.chatInput.text length]];
            }];
        }
        else
        {
            [self.uploadMenuView performBatchUpdates:^{
                // Add all new elements
                NSUInteger start = self.uploadQueue.count;
                [self.uploadMenuView reloadItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:start inSection:0]]];
                [self.uploadQueue addObjectsFromArray:newItems];
                NSUInteger newElementsInSet = self.uploadQueue.count - start;
                NSMutableArray<NSIndexPath*>* newInd = [[NSMutableArray<NSIndexPath*> alloc] initWithCapacity:newElementsInSet];
                for(NSUInteger i = 0; i < newElementsInSet; i++)
                {
                    newInd[i] = [NSIndexPath indexPathForItem:start + i + 1 inSection:0];
                }
                DDLogVerbose(@"Inserting items at index paths: %@", newInd);
                [self.uploadMenuView insertItemsAtIndexPaths:newInd];
            } completion:^(BOOL finished) {
                [self.uploadMenuView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:self.uploadQueue.count inSection:0] atScrollPosition:UICollectionViewScrollPositionRight animated:YES];
                [self setSendButtonIconWithTextLength:[self.chatInput.text length]];
            }];
        }
    });
}

-(nonnull __kindof UICollectionViewCell*) collectionView:(nonnull UICollectionView*) collectionView cellForItemAtIndexPath:(nonnull NSIndexPath*) indexPath
{
    // the '+' tile
    if((NSUInteger)indexPath.item == self.uploadQueue.count)
        return [self.uploadMenuView dequeueReusableCellWithReuseIdentifier:@"addToUploadQueueCell" forIndexPath:indexPath];
    else
    {
        MLAssert(self.uploadQueue.count >= (NSUInteger)indexPath.item, @"index path is greater than count in upload queue");
        NSDictionary* uploadItem = self.uploadQueue[indexPath.item];
        // https://developer.apple.com/documentation/uikit/uicollectionview/1618063-dequeuereusablecellwithreuseiden?language=objc?
        MLUploadQueueCell* cell = (MLUploadQueueCell*) [self.uploadMenuView dequeueReusableCellWithReuseIdentifier:@"UploadQueueCell" forIndexPath:indexPath];
        [cell initCellWithPreviewImage:uploadItem[@"preview"] filename:uploadItem[@"filename"] index:indexPath.item];
        [cell setUploadQueueDelegate:self];
        return cell;
    }
}

-(NSInteger) numberOfSectionsInCollectionView:(UICollectionView*) collectionView
{
    return 1;
}

-(NSInteger)collectionView:(nonnull UICollectionView*) collectionView numberOfItemsInSection:(NSInteger) section
{
    MLAssert(section == 0, @"section is only allowed to be zero");
    return self.uploadQueue.count == 0 ? 0 : self.uploadQueue.count + 1;
}

-(void) notifyUploadQueueRemoval:(NSUInteger) index
{
    MLAssert(index < self.uploadQueue.count, @"index is only allowed to be smaller than uploadQueue.count");
    [self.uploadMenuView performBatchUpdates:^{
        [self deleteQueueItemAtIndex:index];
    } completion:^(BOOL finished) {
        // Fix all indices accordingly
        for(NSUInteger i = 0; i < self.uploadQueue.count; i++)
        {
            MLUploadQueueCell* tmp = (MLUploadQueueCell*)[self.uploadMenuView cellForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection: 0]];
            tmp.index = i;
        }

        // Don't show uploadMenuView if queue is empty again
        if(self.uploadQueue.count == 0)
        {
            [self hideUploadQueue];
        }
    }];
}

-(IBAction) addImageToUploadQueue
{
    [self presentViewController:[self generatePHPickerViewController] animated:YES completion:nil];
}

-(void) dropInteraction:(UIDropInteraction*) interaction performDrop:(id<UIDropSession>) session
{
    for(UIDragItem* item in session.items)
    {
        NSItemProvider* provider = item.itemProvider;
        MLAssert(provider != nil, @"provider must not be nil");
        MLAssert([provider hasItemConformingToTypeIdentifier:UTTypeItem.identifier], @"provider must supply item conforming to kUTTypeItem");
        [HelperTools handleUploadItemProvider:provider withCompletionHandler:^(NSMutableDictionary* _Nullable payload) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if(payload == nil || payload[@"error"] != nil)
                {
                    DDLogError(@"Could not save payload for sending: %@", payload[@"error"]);
                    NSString* message = NSLocalizedString(@"Monal was not able to send your attachment!", @"");
                    if(payload[@"error"] != nil)
                        message = [NSString stringWithFormat:NSLocalizedString(@"Monal was not able to send your attachment: %@", @""), [payload[@"error"] localizedDescription]];
                    UIAlertController* unknownItemWarning = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Could not send", @"")
                                                                                message:message preferredStyle:UIAlertControllerStyleAlert];
                    [unknownItemWarning addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Abort", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                        [unknownItemWarning dismissViewControllerAnimated:YES completion:nil];
                        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
                    }]];
                    [self presentViewController:unknownItemWarning animated:YES completion:nil];
                }
                else
                    [self addToUIQueue:@[payload]];
            });
        }];
    }
}

-(UIDropProposal*) dropInteraction:(UIDropInteraction*) interaction sessionDidUpdate:(id<UIDropSession>) session
{
    return [[UIDropProposal alloc] initWithDropOperation:UIDropOperationCopy];
}

@end
