//
//  chat.m
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "chatViewController.h"
#import "MLChatCell.h"
#import "MLLinkCell.h"
#import "MLChatImageCell.h"
#import "MLChatMapsCell.h"
#import "MLReloadCell.h"

#import "MLConstants.h"
#import "MonalAppDelegate.h"
#import "MBProgressHUD.h"
#import "xmpp.h"
#import "MLOMEMO.h"

#import "IDMPhotoBrowser.h"
#import "ContactDetails.h"
#import "MLXMPPActivityItem.h"
#import "MLImageManager.h"
#import "DataLayer.h"
#import "AESGcm.h"
#import "HelperTools.h"
#import "MLChatViewHelper.h"
#import "MLChatInputContainer.h"
#import "MLXEPSlashMeHandler.h"
#import "MLSearchViewController.h"
#import "MLFiletransfer.h"
#import "EmojiUtilities.h"

@import QuartzCore;
@import MobileCoreServices;
@import AVFoundation;

@interface chatViewController()<IDMPhotoBrowserDelegate, ChatInputActionDelegage, UISearchControllerDelegate>
{
    BOOL _isTyping;
    monal_void_block_t _cancelTypingNotification;
    monal_void_block_t _cancelLastInteractionTimer;
}

@property (nonatomic, strong)  NSDateFormatter* destinationDateFormat;
@property (nonatomic, strong)  NSCalendar *gregorian;
@property (nonatomic, assign)  NSInteger thisyear;
@property (nonatomic, assign)  NSInteger thismonth;
@property (nonatomic, assign)  NSInteger thisday;
@property (nonatomic, strong)  MBProgressHUD *uploadHUD;
@property (nonatomic, strong)  MBProgressHUD *gpsHUD;

@property (nonatomic, strong) NSMutableArray* messageList;
@property (nonatomic, strong) NSMutableArray* photos;
@property (nonatomic, strong) UIDocumentPickerViewController *filePicker;

@property (nonatomic, assign) BOOL encryptChat;
@property (nonatomic, assign) BOOL sendLocation; // used for first request

@property (nonatomic, strong) NSDate* lastMamDate;
@property (nonatomic, assign) BOOL hardwareKeyboardPresent;
@property (nonatomic, strong) xmpp* xmppAccount;

// Privacy settings that should not be loaded for each action
@property (nonatomic, assign) BOOL showGeoLocationsInline;
@property (nonatomic, assign) BOOL sendLastChatState;

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

@property (nonatomic, strong) void (^editingCallback)(NSString* newBody);

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

-(void) setup
{
    self.hidesBottomBarWhenPushed = YES;
    
    NSDictionary* accountDict = [[DataLayer sharedInstance] detailsForAccount:self.contact.accountId];
    if(accountDict)
        self.jid = [NSString stringWithFormat:@"%@@%@",[accountDict objectForKey:@"username"], [accountDict objectForKey:@"domain"]];

    // init privacy Settings
    self.showGeoLocationsInline = [[HelperTools defaultsDB] boolForKey: @"ShowGeoLocation"];
    self.sendLastChatState = [[HelperTools defaultsDB] boolForKey: @"SendLastChatState"];
}

-(void) setupWithContact:(MLContact*) contact
{
    self.contact = contact;
    [self setup];
}

#pragma mark -  view lifecycle

-(void) viewDidLoad
{
    [super viewDidLoad];
    
    [self initNavigationBarItems];
    
    [self setupDateObjects];
    containerView = self.view;
    self.messageTable.scrollsToTop = YES;
    self.chatInput.scrollsToTop = NO;
    self.editingCallback = nil;
    
    self.splitViewController.preferredDisplayMode=UISplitViewControllerDisplayModeAllVisible;
    
    _isTyping = NO;
    self.hidesBottomBarWhenPushed=YES;
    
    self.chatInput.layer.borderColor=[UIColor lightGrayColor].CGColor;
    self.chatInput.layer.cornerRadius=3.0f;
    self.chatInput.layer.borderWidth=0.5f;
    self.chatInput.textContainerInset=UIEdgeInsetsMake(5, 0, 5, 0);
    
    self.messageTable.rowHeight = UITableViewAutomaticDimension;
    self.messageTable.estimatedRowHeight = UITableViewAutomaticDimension;
    
#if TARGET_OS_MACCATALYST
    //does not become first responder like in iOS
    [self.view addSubview:self.inputContainerView];

    [self.inputContainerView.leadingAnchor constraintEqualToAnchor:self.inputContainerView.superview.leadingAnchor].active=YES;
    [self.inputContainerView.bottomAnchor constraintEqualToAnchor:self.inputContainerView.superview.bottomAnchor].active=YES;
    [self.inputContainerView.trailingAnchor constraintEqualToAnchor:self.inputContainerView.superview.trailingAnchor].active=YES;
    self.tableviewBottom.constant += 20;
#endif

    self.filePicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[mimeType_images, mimeType_gifFiles, mimeType_txtFiles, mimeType_videoFiles, mimeType_pdfFiles, mimeType_xmlFiles, mimeType_sourceCodeFiles,
                        mimeType_audioFiles, mimeType_mp4Files, mimeType_movFiles, mimeType_zipFiles, mimeType_gzipFiles,
                        mimeType_tarFiles, mimeType_rtfFiles, mimeType_xlsFiles, mimeType_pptFiles, mimeType_docFiles,
                        mimeType_keyNoteFiles, mimeType_presentationFiles, mimeType_rmFiles, mimeType_mp3Files, mimeType_aviFiles, mimeType_mp4aFiles, mimeType_wavFiles] inMode:UIDocumentPickerModeImport];
    self.filePicker.allowsMultipleSelection = NO;
    self.filePicker.delegate = self;

    // Set max height of the chatInput (The chat should be still readable while the HW-Keyboard is active
    self.chatInputConstraintHWKeyboard = [NSLayoutConstraint constraintWithItem:self.chatInput attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationLessThanOrEqual toItem:nil attribute:NSLayoutAttributeHeight multiplier:1 constant:self.view.frame.size.height * 0.6];
    self.chatInputConstraintSWKeyboard = [NSLayoutConstraint constraintWithItem:self.chatInput attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationLessThanOrEqual toItem:nil attribute:NSLayoutAttributeHeight multiplier:1 constant:self.view.frame.size.height * 0.4];
    [self.inputContainerView addConstraint:self.chatInputConstraintHWKeyboard];
    [self.inputContainerView addConstraint:self.chatInputConstraintSWKeyboard];
    
    [self setChatInputHeightConstraints:YES];
    
    if (@available(iOS 13.0, *)) {
        [self.sendButton setImage:[UIImage systemImageNamed:@"paperplane.fill"] forState:UIControlStateNormal];
        [self.plusButton setImage:[UIImage systemImageNamed:@"paperclip"] forState:UIControlStateNormal];
    } else {
        [self.sendButton setImage:[UIImage imageNamed:@"648-paper-airplane"] forState:UIControlStateNormal];
        [self.plusButton setImage:[UIImage imageNamed:@"907-plus-rounded-square"] forState:UIControlStateNormal];
    }

    // setup refreshControl for infinite scrolling
    UIRefreshControl* refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(loadOldMsgHistory:) forControlEvents:UIControlEventValueChanged];
    refreshControl.attributedTitle = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Loading more Messages from Server", @"")];
    [self.messageTable setRefreshControl:refreshControl];
    self.moreMessagesAvailable = YES;
    //Init search button item.
    [self initSearchButtonItem];
}

-(void) initNavigationBarItems
{
    UIView *cusView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 120, self.navigationController.navigationBar.frame.size.height)];
    //cusView.backgroundColor = [UIColor redColor];

    self.navBarIcon = [[UIImageView alloc] initWithFrame:CGRectMake(0, 7, 30, 30)];
    self.navBarContactJid = [[UILabel alloc] initWithFrame:CGRectMake(38, 7, 200, 18)];
    self.navBarLastInteraction = [[UILabel alloc] initWithFrame:CGRectMake(38, 26, 200, 12)];

    [self.navBarContactJid setFont:[UIFont systemFontOfSize:15.0]];
    [self.navBarLastInteraction setFont:[UIFont systemFontOfSize:10.0]];

    [cusView addSubview:self.navBarIcon];
    [cusView addSubview:self.navBarContactJid];
    [cusView addSubview:self.navBarLastInteraction];
    UITapGestureRecognizer *customViewTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(commandIPressed:)];
    [cusView addGestureRecognizer:customViewTapRecognizer];
    self.navigationItem.leftBarButtonItems = @[[[UIBarButtonItem alloc] initWithCustomView:cusView]];
    self.navigationItem.leftItemsSupplementBackButton = YES;
}

-(void) initLastMsgButton
{
    unichar arrowSymbol = 0x2193;
    
    self.lastMsgButton = [[UIButton alloc] init];
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

-(void) lastMsgButtonPositionConfigWithSize:(CGSize)size
{
    float buttonXPos = self.inputContainerView.frame.origin.x + self.inputContainerView.frame.size.width - lastMsgButtonSize - 5;
    float buttonYPos = self.inputContainerView.frame.origin.y - lastMsgButtonSize - 5;
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
    self.searchResultMessageList = [[NSMutableArray alloc] init];
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
            UIColor *originColor = [selectedCell.backgroundColor copy];
            selectedCell.backgroundColor = [UIColor lightGrayColor];
                        
            [UIView animateWithDuration:0.2 delay:0.2 options:UIViewAnimationOptionCurveLinear animations:^{
                selectedCell.backgroundColor = originColor;
            } completion:nil];
        });
    }
}

-(void)doReloadHistoryForSearch
{
    [self loadOldMsgHistory];
}

- (void)doReloadActionForAllTableView
{
    [self.messageTable reloadData];
}

- (void)doGetMsgData
{
    for (int idx = 0; idx<self.messageList.count; idx++)
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
    if(messageDBId)
    {
        [self.searchController setMessageIndexPath:[NSNumber numberWithInteger:pathIdx] withDBId:messageDBId];
    }
}

-(BOOL) isContainKeyword:(NSNumber *) messageDBId
{
    if ([self.searchController getMessageIndexPathForDBId:messageDBId])
    {
        return YES;
    }
    
    return NO;
}

-(void) resetHistoryAttributeForCell:(MLBaseCell*) cell
{
    if (!cell.messageBody.text) return;
    
    NSMutableAttributedString *defaultAttrString = [[NSMutableAttributedString alloc] initWithString:cell.messageBody.text];
    NSInteger textLength = (cell.messageBody.text == nil) ? 0: cell.messageBody.text.length;
    NSRange defaultTextRange = NSMakeRange(0, textLength);
    [defaultAttrString addAttribute:NSBackgroundColorAttributeName value:[UIColor clearColor] range:defaultTextRange];
    cell.messageBody.attributedText = defaultAttrString;
    cell.textLabel.backgroundColor = [UIColor clearColor];
}


-(void) setChatInputHeightConstraints:(BOOL) hwKeyboardPresent
{
    if((!self.chatInputConstraintHWKeyboard) || (!self.chatInputConstraintSWKeyboard)) {
        return;
    }
    // activate / disable constraints depending on keyboard type
    self.chatInputConstraintHWKeyboard.active = hwKeyboardPresent;
    self.chatInputConstraintSWKeyboard.active = !hwKeyboardPresent;
    
    [self.inputContainerView layoutIfNeeded];
}

-(void) handleForeGround {
    [self refreshData];
    [self reloadTable];
}

-(IBAction) toggleEncryption:(id)sender
{
#ifndef DISABLE_OMEMO
    NSArray* devices = [self.xmppAccount.omemo knownDevicesForAddressName:self.contact.contactJid];
    [MLChatViewHelper<chatViewController*> toggleEncryption:&(self->_encryptChat) forAccount:self.xmppAccount.accountNo forContactJid:self.contact.contactJid withKnownDevices:devices withSelf:self afterToggle:^() {
        [self displayEncryptionStateInUI];
    }];
#endif
}

-(void) displayEncryptionStateInUI
{
    if(self.encryptChat) {
        [self.navBarEncryptToggleButton setImage:[UIImage imageNamed:@"744-locked-received"]];
    } else {
        [self.navBarEncryptToggleButton setImage:[UIImage imageNamed:@"745-unlocked"]];
    }
}

-(void) refreshContact:(NSNotification*) notification
{
    MLContact* contact = [notification.userInfo objectForKey:@"contact"];
    if(self.contact && [self.contact.contactJid isEqualToString:contact.contactJid] && [self.contact.accountId isEqual:contact.accountId])
        [self updateUIElements];
}

-(void) updateUIElements
{
    if(!self.contact.accountId) return;

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

    if(self.contact.isGroup) {
        NSArray* members = [[DataLayer sharedInstance] resourcesForContact:self.contact.contactJid];
        jidLabelText = [NSString stringWithFormat:@"%@ (%ld)", contactDisplayName, members.count];
    }
    // change text values
    dispatch_async(dispatch_get_main_queue(), ^{
        self.navBarContactJid.text = jidLabelText;
        [[MLImageManager sharedInstance] getIconForContact:self.contact.contactJid andAccount:self.contact.accountId withCompletion:^(UIImage *image) {
                   self.navBarIcon.image=image;
          }];
        self.sendButton.enabled = sendButtonEnabled;
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
        if(![accountNo isEqualToString:self.xmppAccount.accountNo])
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
    if(_cancelLastInteractionTimer)
        _cancelLastInteractionTimer();
    _cancelLastInteractionTimer = nil;
}

-(void) updateNavBarLastInteractionLabel:(NSNotification*) notification
{
    NSDate* lastInteractionDate = nil;
    NSString* jid = self.contact.contactJid;
    NSString* accountNo = self.contact.accountId;
    // use supplied data from notification...
    if(notification)
    {
        NSDictionary* data = notification.userInfo;
        if(![jid isEqualToString:data[@"jid"]] || ![accountNo isEqualToString:data[@"accountNo"]])
            return;     // ignore other accounts or contacts
        if([data[@"isTyping"] boolValue] == YES)
        {
            [self stopLastInteractionTimer];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.navBarLastInteraction.text = NSLocalizedString(@"Typing...", @"");
            });
            return;
        }
        lastInteractionDate = data[@"lastInteraction"];     // this is nil for a "not typing" (aka typing ended) notification --> "online"
    }
    // ...or load the latest interaction timestamp from db
    else
        lastInteractionDate = [[DataLayer sharedInstance] lastInteractionOfJid:jid forAccountNo:accountNo];
    
    // make timestamp human readable (lastInteractionDate will be captured by this block and automatically used by our timer)
    monal_void_block_t __block updateTime = ^{
        DDLogVerbose(@"LastInteraction updateTime() called");
        NSString* lastInteractionString = [HelperTools formatLastInteraction:lastInteractionDate];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.navBarLastInteraction.text = lastInteractionString;
        });
        
        [self stopLastInteractionTimer];
        // this timer will be called only if needed
        if(lastInteractionDate && lastInteractionDate.timeIntervalSince1970 > 0)
            _cancelLastInteractionTimer = createTimer(60, updateTime);
    };
    updateTime();
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    //throw on empty contacts
    NSAssert(self.contact.contactJid, @"can not open chat for empty contact jid");
    NSAssert(self.contact.accountId, @"can not open chat for empty account id");
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
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
    [nc addObserver:self selector:@selector(presentMucInvite:) name:kMonalReceivedMucInviteNotice object:nil];
    
    [nc addObserver:self selector:@selector(refreshContact:) name:kMonalContactRefresh object:nil];
    [nc addObserver:self selector:@selector(updateUIElementsOnAccountChange:) name:kMonalAccountStatusChanged object:nil];
    [nc addObserver:self selector:@selector(updateNavBarLastInteractionLabel:) name:kMonalLastInteractionUpdatedNotice object:nil];
    
    [nc addObserver:self selector:@selector(updateBackground) name:kMonalBackgroundChanged object:nil];
    
    self.viewDidAppear = NO;
    self.viewIsScrolling = YES;
    //stop editing (if there is some)
    [self stopEditing];
    self.xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId];
    if(!self.xmppAccount) DDLogDebug(@"Disabled account detected");
    self.encryptChat = [[DataLayer sharedInstance] shouldEncryptForJid:self.contact.contactJid andAccountNo:self.contact.accountId];
    
    [MLNotificationManager sharedInstance].currentAccountNo = self.contact.accountId;
    [MLNotificationManager sharedInstance].currentContact = self.contact;
    
    if(self.day)
    {
        DDLogInfo(@"Showing special day history view");
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        self.inputContainerView.hidden = YES;
        [self refreshData];
        [self updateUIElements];
        [self updateNavBarLastInteractionLabel:nil];
        return;
    }
    else
        self.inputContainerView.hidden = NO;
    
    [self handleForeGround];
    [self updateUIElements];
    [self updateNavBarLastInteractionLabel:nil];
    [self displayEncryptionStateInUI];
    
    [self updateBackground];
    
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
    
    // Set correct chatInput height constraints
    [self setChatInputHeightConstraints:self.hardwareKeyboardPresent];
    [self scrollToBottom];

    [self tempfreezeAutoloading];
}


-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
#ifndef DISABLE_OMEMO
    if(self.xmppAccount) {
        BOOL omemoDeviceForContactFound = [self.xmppAccount.omemo knownDevicesForAddressNameExist:self.contact.contactJid];
        if(!omemoDeviceForContactFound) {
            if(self.encryptChat && [[DataLayer sharedInstance] isAccountEnabled:self.xmppAccount.accountNo]) {
                UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Encryption Not Supported", @"") message:NSLocalizedString(@"This contact does not appear to have any devices that support encryption.", @"") preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Disable Encryption", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    // Disable encryption
                    self.encryptChat = NO;
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
    
    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self];

    // Save message draft
    BOOL success = [self saveMessageDraft];
    if(success) {
        // Update status message for contact to show current draft
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:self.xmppAccount userInfo:@{@"contact": self.contact}];
    }
    [super viewWillDisappear:animated];
    [MLNotificationManager sharedInstance].currentAccountNo = nil;
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
    [self stopLastInteractionTimer];
}

-(void) updateBackground {
    BOOL backgrounds = [[HelperTools defaultsDB] boolForKey:@"ChatBackgrounds"];
    
    if(backgrounds){
        self.backgroundImage.hidden = NO;
        NSString* imageName = [[HelperTools defaultsDB] objectForKey:@"BackgroundImage"];
        if(imageName)
        {
            if([imageName isEqualToString:@"CUSTOM"])
            {
                self.backgroundImage.image = [[MLImageManager sharedInstance] getBackground];
            } else  {
                self.backgroundImage.image = [UIImage imageNamed:imageName];
            }
        }
        self.transparentLayer.hidden = NO;
    } else {
        self.backgroundImage.hidden = YES;
        self.transparentLayer.hidden = YES;
    }
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
    if(self.navigationController.topViewController==self)
    {
        if([MLNotificationManager sharedInstance].currentContact!=self.contact)
            return;
        
        if(!_day && ![HelperTools isInBackground])
        {
            //get list of unread messages
            NSArray* unread = [[DataLayer sharedInstance] markMessagesAsReadForBuddy:self.contact.contactJid andAccount:self.contact.accountId tillStanzaId:nil wasOutgoing:NO];
            
            //send displayed marker for last unread message (XEP-0333)
            MLMessage* lastUnreadMessage = [unread lastObject];
            if(lastUnreadMessage)
            {
                DDLogDebug(@"Marking as displayed: %@", lastUnreadMessage.messageId);
                [[[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId] sendDisplayMarkerForId:lastUnreadMessage.messageId to:lastUnreadMessage.from];
            }
            
            //update app badge
            MonalAppDelegate* appDelegate = (MonalAppDelegate*) [UIApplication sharedApplication].delegate;
            [appDelegate updateUnread];
            
            //refresh contact in active contacts view
            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:self.xmppAccount userInfo:@{@"contact": self.contact}];
        }
        else
            DDLogDebug(@"Not marking messages as read because we are still in background: %@", [HelperTools isInBackground] ? @"YES" : @"NO");
    }
}

-(void) refreshData
{
    if(!self.contact.contactJid) return;
    if(!_day) {
        NSMutableArray* messages = [[DataLayer sharedInstance] messagesForContact:self.contact.contactJid forAccount: self.contact.accountId];
        NSNumber* unreadMsgCnt = [[DataLayer sharedInstance] countUserUnreadMessages:self.contact.contactJid forAccount: self.contact.accountId];
        if([unreadMsgCnt integerValue] == 0) self->_firstmsg=YES;

        if(!self.jid) return;
        MLMessage* unreadStatus = [[MLMessage alloc] init];
        unreadStatus.messageType = kMessageTypeStatus;
        unreadStatus.messageText = NSLocalizedString(@"Unread Messages Below", @"");
        unreadStatus.actualFrom = self.jid;

        NSInteger unreadPos = messages.count - 1;
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

        if(unreadPos <= messages.count - 1 && unreadPos > 0) {
            [messages insertObject:unreadStatus atIndex:unreadPos];
        }

        self.messageList = messages;
		[self doSetNotLoadingHistory];
        [self refreshCounter];
    }
    else  { // load log for this day
        self.messageList = [[[DataLayer sharedInstance] messageHistoryDateForContact:self.contact.contactJid forAccount:self.contact.accountId forDate:self.day] mutableCopy];
    }
}

#pragma mark - textview
-(void) sendMessage:(NSString*) messageText withType:(NSString*) messageType
{
    [self sendMessage:messageText andMessageID:nil withType:messageType];
}

-(void) sendMessage:(nonnull NSString*) messageText andMessageID:(NSString*) messageID withType:(NSString*) messageType
{
    DDLogVerbose(@"Sending message");
    NSString* newMessageID = messageID ? messageID:[[NSUUID UUID] UUIDString];
    //dont readd it, use the exisitng
    NSDictionary* accountDict = [[DataLayer sharedInstance] detailsForAccount:self.contact.accountId];
    if(!accountDict)
    {
        DDLogError(@"Account not found!");
        return;
    }

    if(!messageID && !messageType) {
        DDLogError(@"message id and type both cant be empty");
        return;
    }
    
    if(!messageID)
    {
        [self addMessageto:self.contact.contactJid withMessage:messageText andId:newMessageID messageType:messageType mimeType:nil size:nil];
        [[MLXMPPManager sharedInstance] sendMessage:messageText toContact:self.contact.contactJid fromAccount:self.contact.accountId isEncrypted:self.encryptChat isMUC:self.contact.isGroup isUpload:NO messageId:newMessageID
                            withCompletionHandler:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:self.xmppAccount userInfo:@{@"contact": self.contact}];
    }
    else
    {
        [[MLXMPPManager sharedInstance]
                      sendMessage:messageText
                        toContact:self.contact.contactJid
                      fromAccount:self.contact.accountId
                      isEncrypted:self.encryptChat
                            isMUC:self.contact.isGroup
                         isUpload:NO
                        messageId:newMessageID
            withCompletionHandler:nil
        ];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:kMLMessageSentToContact object:self userInfo:@{@"contact":self.contact}];
}

-(void) sendChatState:(BOOL) isTyping
{
    if(!self.sendButton.enabled)
    {
        DDLogWarn(@"Account disabled, ignoring chatstate update");
        return;
    }
    
    // Do not send when the user disabled the feature
    if(!self.sendLastChatState)
        return;

    if(isTyping != _isTyping)       //changed state? --> send typing notification
    {
        DDLogVerbose(@"Sending chatstate isTyping=%@", isTyping ? @"YES" : @"NO");
        [[MLXMPPManager sharedInstance] sendChatState:isTyping fromAccount:self.contact.accountId toJid:self.contact.contactJid];
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
            if(_isTyping)
            {
                _isTyping = NO;
                DDLogVerbose(@"Sending chatstate isTyping=NO");
                [[MLXMPPManager sharedInstance] sendChatState:NO fromAccount:self.contact.accountId toJid:self.contact.contactJid];
            }
        }));
}

-(void)resignTextView
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
}

-(IBAction)sendMessageText:(id)sender
{
    [self resignTextView];
}

-(void) prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    [self sendChatState:NO];

    if([segue.identifier isEqualToString:@"showDetails"])
    {
        UINavigationController *nav = segue.destinationViewController;
        ContactDetails* details = (ContactDetails *)nav.topViewController;
        details.contact = self.contact;
        details.completion = ^{
            [self viewWillAppear:YES];
        };
    }
}


#pragma mark - doc picker
-(IBAction)attachfile:(id)sender
{
    [self stopEditing];
    [self.chatInput resignFirstResponder];
    
    [self presentViewController:self.filePicker animated:YES completion:nil];
    
    return;
}

- (void) documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    if(urls.count == 0)
        return;
    
    [self showUploadHUD];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block int filesToUpload = (int)urls.count;
        NSFileCoordinator* coordinator = [[NSFileCoordinator alloc] init];
        for(NSURL* url in urls)
        {
            [coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingForUploading error:nil byAccessor:^(NSURL * _Nonnull newURL) {
                [MLFiletransfer uploadFile:newURL onAccount:self.xmppAccount withEncryption:self.encryptChat andCompletion:^(NSString* url, NSString* mimeType, NSNumber* size, NSError* error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self showPotentialError:error];
                        if(!error)
                        {
                            filesToUpload--;
                            if(filesToUpload == 0)
                                [self hideUploadHUD];
                            
                            NSString* newMessageID = [[NSUUID UUID] UUIDString];
                            [self addMessageto:self.contact.contactJid withMessage:url andId:newMessageID messageType:kMessageTypeFiletransfer mimeType:mimeType size:size];
                            [[MLXMPPManager sharedInstance] sendMessage:url toContact:self.contact.contactJid fromAccount:self.contact.accountId isEncrypted:self.encryptChat isMUC:self.contact.isGroup isUpload:YES messageId:newMessageID withCompletionHandler:nil];
                        }
                        DDLogVerbose(@"upload done");
                    });
                }];
            }];
        }
    });
}

#pragma mark  - location delegate
- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    CLAuthorizationStatus gpsStatus = [CLLocationManager authorizationStatus];
    if(gpsStatus == kCLAuthorizationStatusAuthorizedAlways || gpsStatus == kCLAuthorizationStatusAuthorizedWhenInUse) {
        if(self.sendLocation) {
            self.sendLocation=NO;
            [self.locationManager requestLocation];
        }
    }
}

-(void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
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
    self.gpsHUD.hidden=YES;
    // Send location
    [self sendMessage:[NSString stringWithFormat:@"geo:%f,%f", gpsLoc.coordinate.latitude, gpsLoc.coordinate.longitude] withType:kMessageTypeGeo];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    DDLogError(@"Error while fetching location %@", error);
}

-(void) makeLocationManager {
    if(self.locationManager == nil) {
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        self.locationManager.delegate = self;
    }
}

-(void) displayGPSHUD {
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
            UIAlertController *gpsWarning = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"No GPS location received", @"")
                                                                                message:NSLocalizedString(@"Monal did not received a gps location. Please try again later.", @"") preferredStyle:UIAlertControllerStyleAlert];
            [gpsWarning addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                [gpsWarning dismissViewControllerAnimated:YES completion:nil];
            }]];
            [self presentViewController:gpsWarning animated:YES completion:nil];
        }
    });
}

#pragma mark - attachment picker

-(IBAction)attach:(id)sender
{
    [self stopEditing];
    [self.chatInput resignFirstResponder];
    xmpp* account=[[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId];

    UIAlertController *actionControll = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Select Action",@ "")
                                                                            message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    // Check for http upload support
    if(!account.connectionProperties.supportsHTTPUpload )
    {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error",@ "")
                                                                       message:NSLocalizedString(@"This server does not appear to support HTTP file uploads (XEP-0363). Please ask the administrator to enable it.",@ "") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close",@ "") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        
        return;
    } else {

        UIImagePickerController* mediaPicker = [[UIImagePickerController alloc] init];
        mediaPicker.delegate = self;
#if TARGET_OS_MACCATALYST
       
        UIAlertAction* photosAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Images", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self attachfile:sender];
        }];
        
        [photosAction setValue:[[UIImage systemImageNamed:@"photo"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
#else


        UIAlertAction* cameraAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Camera", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            mediaPicker.sourceType = UIImagePickerControllerSourceTypeCamera;

            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                if(granted)
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self presentViewController:mediaPicker animated:YES completion:nil];
                    });
                }
            }];
        }];

        UIAlertAction* photosAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Photos", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            mediaPicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
            mediaPicker.allowsEditing = NO;
            [self presentViewController:mediaPicker animated:YES completion:nil];
       
        }];
        
        UIAlertAction* fileAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"File", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self presentViewController:self.filePicker animated:YES completion:nil];
        }];
        
        // Set image
        if (@available(iOS 13.0, *)) {
            [cameraAction setValue:[[UIImage systemImageNamed:@"camera"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
            [photosAction setValue:[[UIImage systemImageNamed:@"photo"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        } else {
            [cameraAction setValue:[[UIImage imageNamed:@"714-camera"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        }
        [fileAction setValue:[[UIImage imageNamed:@"file-attatchment"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        [actionControll addAction:cameraAction];
        [actionControll addAction:photosAction];
        [actionControll addAction:fileAction];
#endif
        
        [actionControll addAction:photosAction];
    }
    
    UIAlertAction* gpsAlert = [UIAlertAction actionWithTitle:NSLocalizedString(@"Send Location",@ "") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        // GPS
        CLAuthorizationStatus gpsStatus = [CLLocationManager authorizationStatus];
        if(gpsStatus == kCLAuthorizationStatusAuthorizedAlways || gpsStatus == kCLAuthorizationStatusAuthorizedWhenInUse) {
            [self displayGPSHUD];
            [self makeLocationManager];
            [self.locationManager startUpdatingLocation];
        } else if(gpsStatus == kCLAuthorizationStatusNotDetermined) {
#if TARGET_OS_MACCATALYST
            UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Location Access Needed", @"") message:NSLocalizedString(@"Monal  uses your location when you send a location message in a conversation.", @"") preferredStyle:UIAlertControllerStyleAlert];
            
            [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @ "") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                [alert dismissViewControllerAnimated:YES completion:nil];
            }]];
            
            UIAlertAction* allow = [UIAlertAction actionWithTitle:NSLocalizedString(@"Allow", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [self makeLocationManager];
                self.sendLocation=YES;
                [self.locationManager requestWhenInUseAuthorization];
            }];
            [alert addAction:allow];
            
            [self presentViewController:alert animated:YES completion:nil];

#else
            [self makeLocationManager];
            self.sendLocation=YES;
            [self.locationManager requestWhenInUseAuthorization];
#endif

        } else {
            UIAlertController *permissionAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Location Access Needed",@ "")
                                                                                     message:NSLocalizedString(@"Monal does not have access to your location. Please update the location access in your device's Privacy Settings.",@ "") preferredStyle:UIAlertControllerStyleAlert];
            [self presentViewController:permissionAlert animated:YES completion:nil];
            [permissionAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",@ "") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                [permissionAlert dismissViewControllerAnimated:YES completion:nil];
            }]];
        }
    }];

    // Set image
    if (@available(iOS 13.0, *)) {
        [gpsAlert setValue:[[UIImage systemImageNamed:@"location"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    }
    [actionControll addAction:gpsAlert];
    [actionControll addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        [actionControll dismissViewControllerAnimated:YES completion:nil];
    }]];

    actionControll.popoverPresentationController.sourceView=sender;
    [self presentViewController:actionControll animated:YES completion:nil];
}

-(void) imagePickerController:(UIImagePickerController*) picker didFinishPickingMediaWithInfo:(NSDictionary<NSString*, id>*) info
{
    [self dismissViewControllerAnimated:YES completion:nil];

    UIImage* selectedImage = info[UIImagePickerControllerEditedImage];
    if(!selectedImage)
        selectedImage = info[UIImagePickerControllerOriginalImage];

    [self showUploadHUD];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [MLFiletransfer uploadUIImage:selectedImage onAccount:self.xmppAccount withEncryption:self.encryptChat andCompletion:^(NSString* url, NSString* mimeType, NSNumber* size, NSError* error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showPotentialError:error];
                if(!error)
                    [self hideUploadHUD];
                
                NSString* newMessageID = [[NSUUID UUID] UUIDString];
                [self addMessageto:self.contact.contactJid withMessage:url andId:newMessageID messageType:kMessageTypeFiletransfer mimeType:mimeType size:size];
                [[MLXMPPManager sharedInstance] sendMessage:url toContact:self.contact.contactJid fromAccount:self.contact.accountId isEncrypted:self.encryptChat isMUC:self.contact.isGroup isUpload:YES messageId:newMessageID withCompletionHandler:nil];
                DDLogVerbose(@"upload done");
            });
        }];
    });
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
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
-(NSNumber*) addMessageto:(NSString *)to withMessage:(nonnull NSString *) message andId:(nonnull NSString *) messageId messageType:(nonnull NSString *) messageType mimeType:(NSString *) mimeType size:(NSNumber *) size
{
    if(!self.jid || !message)
    {
        DDLogError(@"not ready to send messages");
        return nil;
    }
    
    NSNumber* messageDBId = [[DataLayer sharedInstance] addMessageHistoryFrom:self.jid to:to forAccount:self.contact.accountId withMessage:message actuallyFrom:self.jid withId:messageId encrypted:self.encryptChat messageType:messageType mimeType:mimeType size:size];
    if(messageDBId)
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
                    self.messageList = [[NSMutableArray alloc] init];
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
    }
    else
        DDLogError(@"failed to add message to history db");
    return messageDBId;
}

-(void) presentMucInvite:(NSNotification *)notification
{
    xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId];
    NSDictionary* userDic = notification.userInfo;
    NSString* from = [userDic objectForKey:@"from"];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString* messageString = [NSString  stringWithFormat:NSLocalizedString(@"You have been invited to a conversation %@?", @""), from ];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Group Chat Invite", @"") message:messageString preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Join", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [xmppAccount joinRoom:from withNick:xmppAccount.connectionProperties.identity.user andPassword:nil];
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

-(void) handleNewMessage:(NSNotification *)notification
{
    DDLogVerbose(@"chat view got new message notice %@", notification.userInfo);
    
    MLMessage* message = [notification.userInfo objectForKey:@"message"];
    if(!message)
        DDLogError(@"Notification without message");
    
    if([message.accountId isEqualToString:self.contact.accountId]
       && ([message.from isEqualToString:self.contact.contactJid]
           || [message.to isEqualToString:self.contact.contactJid] ))
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            if(!self.messageList)
                self.messageList = [[NSMutableArray alloc] init];
            
            //update already existent message
            for(size_t msgIdx = [self.messageList count]; msgIdx > 0; msgIdx--)
            {
                // find msg that should be updated
                MLMessage* msgInList = [self.messageList objectAtIndex:(msgIdx - 1)];
                if([msgInList.messageDBId intValue] == [message.messageDBId intValue])
                {
                    //update message in our list
                    [msgInList updateWithMessage:message];
                    
                    // Update table entry
                    NSIndexPath* indexPath = [NSIndexPath indexPathForRow:(msgIdx - 1) inSection:messagesSection];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self->_messageTable beginUpdates];
                        [self->_messageTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                        [self->_messageTable endUpdates];
                    });
                    return;
                }
            }
            
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
    
    NSIndexPath* indexPath;
    for(size_t msgIdx = [self.messageList count]; msgIdx > 0; msgIdx--)
    {
        // find msg that should be deleted
        MLMessage* msgInList = [self.messageList objectAtIndex:(msgIdx - 1)];
        if([msgInList.messageDBId intValue] == [msg.messageDBId intValue])
        {
            // Remove table entry
            indexPath = [NSIndexPath indexPathForRow:(msgIdx - 1) inSection:messagesSection];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_messageTable beginUpdates];
                [self.messageList removeObjectAtIndex:indexPath.row];
                [self->_messageTable deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationRight];
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
                }
            }
            
            indexPath = [NSIndexPath indexPathForRow:(msgIdx - 1) inSection:messagesSection];

            // Update table entry
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
            
            //TODO JIM: do something on update (maybe this is not needed because handling will be done in filetransferChatCell)
            
            // Update table entry
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
                [self.messageTable scrollToRowAtIndexPath:path1 atScrollPosition:UITableViewScrollPositionBottom animated:NO];
            }
        }
    });
}

#pragma mark - date time

-(void) setupDateObjects
{
    self.destinationDateFormat = [[NSDateFormatter alloc] init];
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
            [self loadOldMsgHistory];
            // Allow loading of more messages after a few seconds
            monal_void_block_t __block allowAutoLoading = ^{
                self.viewIsScrolling = NO;
            };
            createTimer(10, allowAutoLoading);
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
    if(indexPath.row < self.messageList.count) {
        row = [self.messageList objectAtIndex:indexPath.row];
    } else {
        DDLogError(@"Attempt to access beyond bounds");
    }

    //cut text after kMonalChatMaxAllowedTextLen chars to make the message cell work properly (too big texts don't render the text in the cell at all)
    NSString* messageText = row.messageText;
    if([messageText length] > kMonalChatMaxAllowedTextLen)
        messageText = [NSString stringWithFormat:@"%@\n[...]", [messageText substringToIndex:kMonalChatMaxAllowedTextLen]];
    BOOL inDirection = [row.from isEqualToString:self.contact.contactJid];

    if([row.messageType isEqualToString:kMessageTypeStatus])
    {
        cell = [tableView dequeueReusableCellWithIdentifier:@"StatusCell"];
        cell.messageBody.text = messageText;
        cell.link = nil;
        cell.parent = self;
        return cell;
    }
    else if([row.messageType isEqualToString:kMessageTypeFiletransfer])
    {
        DDLogVerbose(@"got filetransfer chat cell: %@ (%@)", row.filetransferMimeType, row.filetransferSize);
        NSDictionary* info = [MLFiletransfer getFileInfoForMessage:row];
        
        if (![[HelperTools defaultsDB] boolForKey:@"AutodownloadFiletransfers"])
        {
            //TODO JIM: here we need the download and check-file buttons
            
            if(info && ![info[@"needsDownloading"] boolValue])
            {
                cell = [self fileTransferCellCheckerWithInfo:info direction:inDirection tableView:tableView andMsg:row];
            }
            else if (info && [info[@"needsDownloading"] boolValue])
            {
                if (info[@"mimeType"] != nil)
                {
                    //TODO JIM: explanation: this was already checked (mime ype and size are known) but not yet downloaded --> download it
                    //TODO JIM: explanation: this should not be automatically but only triggered by a button press
                    //TODO JIM: explanation: I'm doing this automatically here because we still lack those buttons
                    //TODO JIM: explanation: this only handles images, because we don't want to autodownload everything
                    MLFileTransferDataCell* fileTransferCell = (MLFileTransferDataCell *) [self messageTableCellWithIdentifier:@"fileTransferCheckingData" andInbound:inDirection fromTable:tableView];
                    
                    NSString *fileType = info[@"mimeType"];
                    
                    if([fileType hasPrefix:@"image/"])
                    {
                        fileTransferCell.transferStatus = transferImageTypeNeedDowndload;
                    }
                    else if([fileType hasPrefix:@"video/"])
                    {
                        fileTransferCell.transferStatus = transferVideoTypeNeedDowndload;
                    }
                    else if([fileType hasPrefix:@"audio/"])
                    {
                        fileTransferCell.transferStatus = transferAudioTypeNeedDowndload;
                    }
                    else
                    {
                        fileTransferCell.transferStatus = transferFileTypeNeedDowndload;
                    }
                    
                    NSString *hintStr = [NSString stringWithFormat:@"%@ %@ (%@).", NSLocalizedString(@"Download", @""), info[@"filename"], fileType];
                    NSString *fileSizeStr = info[@"size"];
                    long long fileSizeLongLongValue = fileSizeStr.longLongValue;
                    NSString *readableFileSize = [NSByteCountFormatter stringFromByteCount:fileSizeLongLongValue
                                                                                countStyle:NSByteCountFormatterCountStyleFile];
                    
                    [fileTransferCell.loadingView setHidden:YES];
                    [fileTransferCell.downloadImageView setHidden:NO];
                    [fileTransferCell.sizeLabel setText:readableFileSize];
                    [fileTransferCell.fileTransferHint setText:hintStr];
                    fileTransferCell.messageDBId = row.messageDBId;
                    cell = fileTransferCell;
                }
                else
                {
                    //TODO JIM: explanation: this was not yet checked, do an http head request to get mime type and size
                    //TODO JIM: explanation: this should not be automatically but only triggered by a button press
                    //TODO JIM: explanation: I'm doing this automatically here because we still lack those buttons
                    MLFileTransferDataCell* fileTransferCell = (MLFileTransferDataCell *) [self messageTableCellWithIdentifier:@"fileTransferCheckingData" andInbound:inDirection fromTable:tableView];
                    NSString *hintStr = [NSString stringWithFormat:@"%@%@", NSLocalizedString(@"Check type and size on ", @""), info[@"filename"]];
                    [fileTransferCell.fileTransferHint setText:hintStr];
                    fileTransferCell.transferStatus = transferCheck;
                    [fileTransferCell.sizeLabel setText:@""];
                    fileTransferCell.messageDBId = row.messageDBId;
                    cell = fileTransferCell;
                }
            }
            //            else
            //            {
            //
            //                NSString *mimeType = info[@"mimeType"];
            //
            //                NSLog(@"#[Jim] mimeType:%@", mimeType);
            //
            //TODO JIM: add handling for some other mime types and default handling for general files (e.g. "open this file" button) here
            //TODO JIM: for now we just show the link as normal chat cell
            //            }
        }
        else
        {
            //this is just a dummy to display something usable (the filetransfer url as link cell)
            
            // Use default text cell
            cell = (MLChatCell*)[self messageTableCellWithIdentifier:@"progress" andInbound:inDirection fromTable: tableView];
            cell.link = row.messageText;
            
            if(info && ![info[@"needsDownloading"] boolValue])
            {
                cell = [self fileTransferCellCheckerWithInfo:info direction:inDirection tableView:tableView andMsg:row];
            }
        }
    }
    else if([row.messageType isEqualToString:kMessageTypeUrl] && [[HelperTools defaultsDB] boolForKey:@"ShowURLPreview"])
    {
        MLLinkCell* toreturn = (MLLinkCell *)[self messageTableCellWithIdentifier:@"link" andInbound:inDirection fromTable: tableView];
        
        NSString* cleanLink = [messageText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSArray* parts = [cleanLink componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        toreturn.link = parts[0];
        toreturn.messageBody.text = toreturn.link;
        
        if(row.previewText || row.previewImage)
        {
            toreturn.imageUrl = row.previewImage;
            toreturn.messageTitle.text = row.previewText;
            [toreturn loadImageWithCompletion:^{}];
        }
        else
        {
            [toreturn loadPreviewWithCompletion:^{
                // prevent repeated calls
                if(toreturn.messageTitle.text.length == 0)
                    toreturn.messageTitle.text = @" ";
                [[DataLayer sharedInstance] setMessageId:row.messageId previewText:toreturn.messageTitle.text andPreviewImage:toreturn.imageUrl.absoluteString];
            }];
        }
        cell = toreturn;
    } else if ([row.messageType isEqualToString:kMessageTypeGeo]) {
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
            if(self.showGeoLocationsInline) {
                MLChatMapsCell* mapsCell = (MLChatMapsCell *)[self messageTableCellWithIdentifier:@"maps" andInbound:inDirection fromTable: tableView];

                // Set lat / long used for map view and pin
                mapsCell.latitude = [latitude doubleValue];
                mapsCell.longitude = [longitude doubleValue];

                [mapsCell loadCoordinatesWithCompletion:^{}];
                cell = mapsCell;
            } else {
                // Default to text cell
                cell = [self messageTableCellWithIdentifier:@"text" andInbound:inDirection fromTable: tableView];
                NSMutableAttributedString* geoString = [[NSMutableAttributedString alloc] initWithString:messageText];
                [geoString addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:[geoMatch rangeAtIndex:0]];

                cell.messageBody.attributedText = geoString;
                NSInteger zoomLayer = 15;
                cell.link = [NSString stringWithFormat:@"https://www.openstreetmap.org/?mlat=%@&mlon=%@&zoom=%ldd", latitude, longitude, zoomLayer];
            }
        } else {
            DDLogWarn(@"msgs of type kMessageTypeGeo should contain a geo location");
        }
    } else {
        // Use default text cell
        cell = (MLChatCell*)[self messageTableCellWithIdentifier:@"text" andInbound:inDirection fromTable: tableView];
        
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
            if(messageText.length ==2  && [EmojiUtilities containsEmoji:messageText]){
                UIFont* originalFont = [UIFont systemFontOfSize:cell.messageBody.font.pointSize*3];
                [cell.messageBody setFont:originalFont];
                
                [cell.messageBody setText:messageText];
                cell.bubbleImage.hidden=YES;
            }
            else
            // Reset attributes
            //XEP-0245: The slash me Command
            if([messageText hasPrefix:@"/me "])
            {
                NSString* displayName;
                if([row.from isEqualToString:self.jid])
                    displayName = [MLContact ownDisplayNameForAccountNo:self.contact.accountId andOwnJid:self.jid];
                else
                    displayName = [self.contact contactDisplayName];
                UIFont* italicFont = [UIFont italicSystemFontOfSize:cell.messageBody.font.pointSize];
                
                NSMutableAttributedString* attributedMsgString = [[MLXEPSlashMeHandler sharedInstance] attributedStringSlashMeWithAccountId:self.contact.accountId
                                                                                                                                displayName:displayName
                                                                                                                                 actualFrom:row.actualFrom
                                                                                                                                    message:messageText
                                                                                                                                    isGroup:self.contact.isGroup
                                                                                                                                   withFont:italicFont];
                
                [cell.messageBody setAttributedText:attributedMsgString];
            } else {                
                // Reset attributes
                UIFont* originalFont = [UIFont systemFontOfSize:cell.messageBody.font.pointSize];
                [cell.messageBody setFont:originalFont];
                
                [cell.messageBody setText:messageText];
            }
            cell.link = nil;
        }
    }
    
    if(cell == nil)
    {
        //this is just a dummy to display something usable (the filetransfer url as link cell)
        MLLinkCell* toreturn = (MLLinkCell *)[self messageTableCellWithIdentifier:@"link" andInbound:inDirection fromTable: tableView];;
        toreturn.link = row.messageText;
        toreturn.messageBody.text = toreturn.link;
        
        if(row.previewText || row.previewImage)
        {
            toreturn.imageUrl = row.previewImage;
            toreturn.messageTitle.text = row.previewText;
            [toreturn loadImageWithCompletion:^{}];
        }
        else
        {
            [toreturn loadPreviewWithCompletion:^{
                // prevent repeated calls
                if(toreturn.messageTitle.text.length == 0)
                    toreturn.messageTitle.text = @" ";
                [[DataLayer sharedInstance] setMessageId:row.messageId previewText:toreturn.messageTitle.text andPreviewImage:toreturn.imageUrl.absoluteString];
            }];
        }
        cell = toreturn;
    }
    // Only display names for groups
    cell.name.text = self.contact.isGroup ? row.actualFrom : @"";
    cell.name.hidden = !self.contact.isGroup;

    MLMessage* priorRow = nil;
    if(indexPath.row > 0)
    {
        priorRow = [self.messageList objectAtIndex:indexPath.row-1];
    }
    
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
        NSString* priorSender = priorRow.from;
        if(![priorSender isEqualToString:row.from])
            newSender = YES;
    }
    cell.date.text = [self formattedTimeStampWithSource:row.delayTimeStamp ? row.delayTimeStamp : row.timestamp];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    cell.dividerDate.text = [self formattedDateWithSource:row.delayTimeStamp?row.delayTimeStamp:row.timestamp andPriorDate:priorRow.timestamp];
    
    // Do not hide the lockImage if the message was encrypted
    cell.lockImage.hidden = !row.encrypted;
    // Set correct layout in/Outbound
    cell.outBound = !inDirection;
    // Hide messageStatus on inbound messages
    cell.messageStatus.hidden = inDirection;
    
    cell.parent = self;
    
    if(cell.outBound && ([row.errorType length] > 0 || [row.errorReason length] > 0) && !row.hasBeenReceived && row.hasBeenSent)
    {
        cell.messageStatus.text = NSLocalizedString(@"Error", @"");
        cell.deliveryFailed = YES;
    }
    
    [cell updateCellWithNewSender:newSender];
        
    if(!cell.link) [self resetHistoryAttributeForCell:cell];
    if(self.searchController.isActive && row.messageDBId)
    {
        if([self.searchController isDBIdExistent:row.messageDBId])
        {
            NSMutableAttributedString *attributedMsgString = [self.searchController doSearchKeyword:self.searchController.searchBar.text
                                                                                             onText:messageText
                                                                                         andInbound:inDirection];
            [cell.messageBody setAttributedText:attributedMsgString];
        }
    }
    
    return cell;
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
                [(MLChatCell *)cell openlink:self];
            } else  {
                self.photos = [[NSMutableArray alloc] init];
                MLChatImageCell* imageCell = (MLChatImageCell *) cell;
                IDMPhoto* photo = [IDMPhoto photoWithImage:imageCell.thumbnailImage.image];
                // photo.caption=[row objectForKey:@"caption"];
                [self.photos addObject:photo];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if(self.photos.count > 0) {
                    IDMPhotoBrowser* browser = [[IDMPhotoBrowser alloc] initWithPhotos:self.photos];
                    browser.delegate=self;

                    UIBarButtonItem* close = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Close", @"") style:UIBarButtonItemStyleDone target:self action:@selector(closePhotos)];
                    browser.navigationItem.rightBarButtonItem = close;

                    //                browser.displayActionButton = YES; // Show action button to allow sharing, copying, etc (defaults to YES)
                    //                browser.displayNavArrows = NO; // Whether to display left and right nav arrows on toolbar (defaults to NO)
                    //                browser.displaySelectionButtons = NO; // Whether selection buttons are shown on each image (defaults to NO)
                    //                browser.zoomPhotosToFill = YES; // Images that almost fill the screen will be initially zoomed to fill (defaults to YES)
                    //                browser.alwaysShowControls = NO; // Allows to control whether the bars and controls are always visible or whether they fade away to show the photo full (defaults to NO)
                    //                browser.enableGrid = YES; // Whether to allow the viewing of all the photo thumbnails on a grid (defaults to YES)
                    //                browser.startOnGrid = NO; // Whether to start on the grid of thumbnails instead of the first photo (defaults to NO)
                    //
                    UINavigationController* nav = [[UINavigationController alloc] initWithRootViewController:browser];

                    [self presentViewController:nav animated:YES completion:nil];
                }
            });
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
    if(indexPath.row < self.messageList.count)
        message = [self.messageList objectAtIndex:indexPath.row];
    else
    {
        DDLogError(@"Attempt to access beyond bounds");
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    }
    if(!message.messageDBId)
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    
    //configure swipe actions
    
    UIContextualAction* LMCEditAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"" handler:^(UIContextualAction* action, UIView* sourceView, void (^completionHandler)(BOOL actionPerformed)) {
        [self.chatInput setText:message.messageText];       //we want to begin editing using the old message
        weakify(self);
        self.editingCallback = ^(NSString* newBody) {
            strongify(self);
            self.editingCallback = nil;
            if(newBody != nil)
            {
                message.messageText = newBody;
                
                [self.xmppAccount sendLMCForId:message.messageId withNewBody:newBody to:message.to];
                [[DataLayer sharedInstance] updateMessageHistory:message.messageDBId withText:newBody];
                
                [self->_messageTable beginUpdates];
                [self->_messageTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                [self->_messageTable endUpdates];
                
                //update active chats if necessary
                [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:self.xmppAccount userInfo:@{@"contact": self.contact}];
                return completionHandler(YES);
            }
            else
                [self.chatInput setText:@""];
            return completionHandler(NO);
        };
    }];
    LMCEditAction.backgroundColor = UIColor.systemYellowColor;
    if(@available(iOS 13.0, *))
    {
        LMCEditAction.image = [[[UIImage systemImageNamed:@"pencil.circle.fill"] imageWithHorizontallyFlippedOrientation] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAutomatic];
    }
    
    UIContextualAction* LMCDeleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"" handler:^(UIContextualAction* action, UIView* sourceView, void (^completionHandler)(BOOL actionPerformed)) {
        [self.xmppAccount sendLMCForId:message.messageId withNewBody:kMessageDeletedBody to:message.to];
        [[DataLayer sharedInstance] deleteMessageHistory:message.messageDBId];
        
        [self->_messageTable beginUpdates];
        [self.messageList removeObjectAtIndex:indexPath.row];
        [self->_messageTable deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationRight];
        [self->_messageTable endUpdates];
        
        //update active chats if necessary
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:self.xmppAccount userInfo:@{@"contact": self.contact}];
        
        return completionHandler(YES);
    }];
    LMCDeleteAction.backgroundColor = UIColor.systemRedColor;
    if(@available(iOS 13.0, *))
    {
        LMCDeleteAction.image = [[[UIImage systemImageNamed:@"trash.circle.fill"] imageWithHorizontallyFlippedOrientation] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAutomatic];
    }
    
    UIContextualAction* localDeleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"" handler:^(UIContextualAction* action, UIView* sourceView, void (^completionHandler)(BOOL actionPerformed)) {
        [[DataLayer sharedInstance] deleteMessageHistory:message.messageDBId];
        
        [self->_messageTable beginUpdates];
        [self.messageList removeObjectAtIndex:indexPath.row];
        [self->_messageTable deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationRight];
        [self->_messageTable endUpdates];
        
        //update active chats if necessary
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:self.xmppAccount userInfo:@{@"contact": self.contact}];
        
        return completionHandler(YES);
    }];
    localDeleteAction.backgroundColor = UIColor.systemRedColor;
    if(@available(iOS 13.0, *))
    {
        localDeleteAction.image = [[[UIImage systemImageNamed:@"trash.circle.fill"] imageWithHorizontallyFlippedOrientation] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAutomatic];
    }
    
    UIContextualAction* copyAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"" handler:^(UIContextualAction* action, UIView* sourceView, void (^completionHandler)(BOOL actionPerformed)) {
        UIPasteboard* pasteboard = [UIPasteboard generalPasteboard];
        MLBaseCell* selectedCell = [self.messageTable cellForRowAtIndexPath:indexPath];
        if([selectedCell isKindOfClass:[MLChatImageCell class]])
            pasteboard.image = ((MLChatImageCell*)selectedCell).thumbnailImage.image;
        else if([selectedCell isKindOfClass:[MLLinkCell class]])
            pasteboard.URL = [NSURL URLWithString:((MLLinkCell*)selectedCell).link];
        else
            pasteboard.string = message.messageText;
        return completionHandler(YES);
    }];
    copyAction.backgroundColor = UIColor.systemGreenColor;
    if(@available(iOS 13.0, *))
    {
        copyAction.image = [[[UIImage systemImageNamed:@"doc.on.doc.fill"] imageWithHorizontallyFlippedOrientation] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAutomatic];
    }
    
    //only allow editing for the 2 newest outgoing message that were sent in the last 2 minutes
    if([[DataLayer sharedInstance] checkLMCEligible:message.messageDBId from:self.xmppAccount.connectionProperties.identity.jid])
        return [UISwipeActionsConfiguration configurationWithActions:@[
            LMCEditAction,
            LMCDeleteAction,
            copyAction,
        ]];
    else
        return [UISwipeActionsConfiguration configurationWithActions:@[
            localDeleteAction,
            copyAction,
        ]];
}

-(MLBaseCell*) fileTransferCellCheckerWithInfo:(NSDictionary*)info direction:(BOOL)inDirection tableView:(UITableView*)tableView andMsg:(MLMessage*)row{
    MLBaseCell *cell = nil;
    //TODO JIM: explanation: this was already downloaded and it is an image --> show this image inline
    if ([info[@"mimeType"] hasPrefix:@"image/"])
    {
        MLChatImageCell* imageCell = (MLChatImageCell *) [self messageTableCellWithIdentifier:@"image" andInbound:inDirection fromTable:tableView];
        
        if(imageCell.msg != row)
        {
            imageCell.msg = row;
            imageCell.thumbnailImage.image = nil;
            imageCell.loading = NO;
            [imageCell loadImage];
        }
        cell = imageCell;
    }
    else if ([info[@"mimeType"] hasPrefix:@"video/"])
    {                
        MLFileTransferVideoCell* videoCell = (MLFileTransferVideoCell *) [self messageTableCellWithIdentifier:@"fileTransferVideo" andInbound:inDirection fromTable:tableView];
        NSString *videoStr = info[@"cacheFile"];
        NSString *videoFileName = info[@"filename"];
        [videoCell avplayerConfigWithUrlStr:videoStr fileName:videoFileName andVC:self];
                
        cell = videoCell;
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
    if(self.contact.isGroup)
        return;
    
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
    if(self.contact.isGroup)
        return;

    // Load older messages from db
    NSMutableArray* oldMessages = nil;
    if(self.messageList.count > 0) {
        oldMessages = [[DataLayer sharedInstance] messagesForContact:self.contact.contactJid forAccount: self.contact.accountId beforeMsgHistoryID:((MLMessage*)[self.messageList objectAtIndex:0]).messageDBId];
    }

    if(!self.isLoadingMam && [oldMessages count] < kMonalChatFetchedMsgCnt)
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
        
        //now load more (older) messages from mam if not
        DDLogVerbose(@"Loading more messages from mam before stanzaId %@", oldestStanzaId);
        weakify(self);
        [self.xmppAccount setMAMQueryMostRecentForJid:self.contact.contactJid before:oldestStanzaId withCompletion:^(NSArray* _Nullable messages) {
            strongify(self);
            if(!messages)
            {
                DDLogError(@"Got backscrolling mam error");
                self.moreMessagesAvailable = NO;
                //TODO: error happened --> display this to user?
            }
            else
            {
                if([messages count] == 0) {
                    self.moreMessagesAvailable = NO;
                }
                DDLogVerbose(@"Got backscrolling mam response: %lu", (unsigned long)[messages count]);
                [self insertOldMessages:messages];      //this array is already in reverse order
            }
            //allow next mam fetch
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isLoadingMam = NO;
                if(sender)
                    [(UIRefreshControl *)sender endRefreshing];
            });
        }];
    }
    else if(!self.isLoadingMam && [oldMessages count] >= kMonalChatFetchedMsgCnt)
    {
        if(sender)
            [(UIRefreshControl *)sender endRefreshing];
    }
    
    if(oldMessages && [oldMessages count] > 0) {
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
            self.messageList = [[NSMutableArray alloc] init];
        
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
    return @[
            // shift + enter
            [UIKeyCommand keyCommandWithInput:@"\r" modifierFlags:UIKeyModifierShift action:@selector(shiftEnterKeyPressed:)],
            // enter
            [UIKeyCommand keyCommandWithInput:@"\r" modifierFlags:0 action:@selector(enterKeyPressed:)],
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
}

#pragma mark - photo browser delegate

- (NSUInteger)numberOfPhotosInPhotoBrowser:(IDMPhotoBrowser *)photoBrowser {
    return self.photos.count;
}

- (id <IDMPhoto>)photoBrowser:(IDMPhotoBrowser *)photoBrowser photoAtIndex:(NSUInteger)index {
    if (index < self.photos.count) {
        return [self.photos objectAtIndex:index];
    }
    return nil;
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
    MLFileTransferFileViewController *fileViewController = [[MLFileTransferFileViewController alloc] init];
    fileViewController.fileUrlStr = fileUrlStr;
    fileViewController.mimeType = mimeType;
    fileViewController.fileName = fileName;
    fileViewController.fileEncodeName = encodeName;
    [self presentViewController:fileViewController animated:NO completion:nil];
//    [self.navigationController pushViewController:fileViewController animated:NO];
}
@end
