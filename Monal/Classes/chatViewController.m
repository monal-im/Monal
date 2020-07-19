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

#import "MLConstants.h"
#import "MonalAppDelegate.h"
#import "MBProgressHUD.h"


#import "IDMPhotoBrowser.h"
#import "ContactDetails.h"
#import "MLXMPPActivityItem.h"
#import "MLImageManager.h"
#import "DataLayer.h"
#import "AESGcm.h"
#import "HelperTools.h"

@import QuartzCore;
@import MobileCoreServices;

@interface chatViewController()<IDMPhotoBrowserDelegate>
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
@property (nonatomic, strong) UIDocumentPickerViewController *imagePicker;

@property (nonatomic, assign) BOOL encryptChat;
@property (nonatomic, assign) BOOL sendLocation; // used for first request

@property (nonatomic, strong) NSDate* lastMamDate;
@property (nonatomic, assign) BOOL hardwareKeyboardPresent;
@property (nonatomic, strong) xmpp* xmppAccount;

@property (nonatomic, strong) NSLayoutConstraint* chatInputConstraintHWKeyboard;
@property (nonatomic, strong) NSLayoutConstraint* chatInputConstraintSWKeyboard;

@end

@class HelperTools;

@implementation chatViewController

-(void) setup
{
    self.hidesBottomBarWhenPushed=YES;
    
    [[DataLayer sharedInstance] detailsForAccount:self.contact.accountId withCompletion:^(NSArray *result) {
        NSArray* accountVals = result;
        if([accountVals count] > 0)
        {
            self.jid = [NSString stringWithFormat:@"%@@%@",[[accountVals objectAtIndex:0] objectForKey:@"username"], [[accountVals objectAtIndex:0] objectForKey:@"domain"]];
        }
    }];
}

-(void) setupWithContact:(MLContact* ) contact
{
    self.contact = contact;
    [self setup];
}

#pragma mark -  view lifecycle

-(void) viewDidLoad
{
    [super viewDidLoad];
    [self setupDateObjects];
    containerView = self.view;
    self.messageTable.scrollsToTop = YES;
    self.chatInput.scrollsToTop = NO;
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    [nc addObserver:self selector:@selector(handleSendFailedMessage:) name:kMonalSendFailedMessageNotice object:nil];
    [nc addObserver:self selector:@selector(handleSentMessage:) name:kMonalSentMessageNotice object:nil];
    [nc addObserver:self selector:@selector(handleMessageError:) name:kMonalMessageErrorNotice object:nil];
    
    
    [nc addObserver:self selector:@selector(dismissKeyboard:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(handleForeGround) name:UIApplicationWillEnterForegroundNotification object:nil];
    
    [nc addObserver:self selector:@selector(keyboardDidShow:) name:UIKeyboardDidShowNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardDidHide:) name:UIKeyboardDidHideNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardWillDisappear:) name:UIKeyboardWillHideNotification object:nil];
    
    [nc addObserver:self selector:@selector(refreshMessage:) name:kMonalMessageReceivedNotice object:nil];
    [nc addObserver:self selector:@selector(presentMucInvite:) name:kMonalReceivedMucInviteNotice object:nil];
    
    [nc addObserver:self selector:@selector(updateUIElementsOnAccountChange:) name:kMonalAccountStatusChanged object:nil];
    [nc addObserver:self selector:@selector(updateNavBarLastInteractionLabel:) name:kMonalLastInteractionUpdatedNotice object:nil];
    
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
    
    //UTI @"public.data" for everything
    NSString *images = (NSString *)kUTTypeImage;
    self.imagePicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[images] inMode:UIDocumentPickerModeImport];
    self.imagePicker.allowsMultipleSelection=NO;
    self.imagePicker.delegate=self;
#endif

    // Set max height of the chatInput (The chat should be still readable while the HW-Keyboard is active
    self.chatInputConstraintHWKeyboard = [NSLayoutConstraint constraintWithItem:self.chatInput attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationLessThanOrEqual toItem:nil attribute:NSLayoutAttributeHeight multiplier:1 constant:self.view.frame.size.height * 0.6];
    self.chatInputConstraintSWKeyboard = [NSLayoutConstraint constraintWithItem:self.chatInput attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationLessThanOrEqual toItem:nil attribute:NSLayoutAttributeHeight multiplier:1 constant:self.view.frame.size.height * 0.4];
    [self.inputContainerView addConstraint:self.chatInputConstraintHWKeyboard];
    [self.inputContainerView addConstraint:self.chatInputConstraintSWKeyboard];
    
    [self setChatInputHeightConstraints:YES];
    
#if !TARGET_OS_MACCATALYST
    if (@available(iOS 13.0, *)) {
        
    } else {
        [self.sendButton setImage:[UIImage imageNamed:@"648-paper-airplane"] forState:UIControlStateNormal];
        [self.plusButton setImage:[UIImage imageNamed:@"907-plus-rounded-square"] forState:UIControlStateNormal];
    }
#endif
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

/**
 gets recent messages  to fill an empty chat
 */
-(void) synchChat {
    dispatch_async(dispatch_get_main_queue(), ^{
        if(self.xmppAccount.connectionProperties.supportsMam2 & !self.contact.isGroup) {
            if(self.messageList.count==0) {
                [self.xmppAccount setMAMQueryMostRecentForJid:self.contact.contactJid ];
            }
        }
    });
}

-(void) displayEncryptionStateInUI
{
    if(self.encryptChat) {
        [self.navBarEncryptToggleButton setImage:[UIImage imageNamed:@"744-locked-received"]];
    } else {
        [self.navBarEncryptToggleButton setImage:[UIImage imageNamed:@"745-unlocked"]];
    }
}

// TODO use notification
-(void) updateUIElementsOnAccountChange:(xmppState) accountState isHibernated:(BOOL) isHibernated
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
    
    if(isHibernated == YES)
        jidLabelText = [NSString stringWithFormat:@"%@ [%@]", contactDisplayName, @"Hibernated"];
    else
        jidLabelText = [NSString stringWithFormat:@"%@", contactDisplayName];

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
        NSNumber* accountHibernate = [userInfo objectForKey:kAccountHibernate];
        
        // Only parse account changes for our current opened account
        if(![accountNo isEqualToString:self.xmppAccount.accountNo])
            return;
        
        if(accountNo && accountState && accountHibernate)
            [self updateUIElementsOnAccountChange:(xmppState)[accountState intValue] isHibernated:[accountHibernate boolValue]];
    }
    else
    {
        xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId];
        [self updateUIElementsOnAccountChange:kStateLoggedIn isHibernated:[xmppAccount isHibernated]];
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
    NSDate* lastInteractionDate = [NSNull null];
    NSString* jid = self.contact.contactJid;
    NSString* accountNo = self.contact.accountId;
    // use supplied data from notification...
    if(notification)
    {
        NSDictionary* data = notification.userInfo;
        if(![jid isEqualToString:data[@"jid"]] || ![accountNo isEqualToString:data[@"accountNo"]])
            return;     // ignore other accounts or contacts
        if(data[@"isTyping"]==@YES)
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
        if(lastInteractionDate && lastInteractionDate!=[NSNull null])
            _cancelLastInteractionTimer = [HelperTools startTimer:60 withHandler:updateTime];
    };
    updateTime();
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    // Hide normal navigation bar
    //[[self navigationController] setNavigationBarHidden:YES animated:NO];
    
    [MLNotificationManager sharedInstance].currentAccountNo=self.contact.accountId;
    [MLNotificationManager sharedInstance].currentContact=self.contact;
    
    if(self.day) {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        self.inputContainerView.hidden = YES;
    }
    else {
        self.inputContainerView.hidden = NO;
    }
    
    if(self.contact.contactJid && self.contact.accountId) {
        self.encryptChat = [[DataLayer sharedInstance] shouldEncryptForJid:self.contact.contactJid andAccountNo:self.contact.accountId];
    }
    [self handleForeGround];
    [self updateUIElementsOnAccountChange:nil];
    [self updateNavBarLastInteractionLabel:nil];
    [self displayEncryptionStateInUI];
    
    [self updateBackground];
    
    self.placeHolderText.text=[NSString stringWithFormat:NSLocalizedString(@"Message from %@",@ ""), self.jid];
    // Load message draft from db
    [[DataLayer sharedInstance] loadMessageDraft:self.contact.contactJid forAccount:self.contact.accountId
        withCompletion:^(NSString* messageDraft) {
            if([messageDraft length] > 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.chatInput.text = messageDraft;
                    self.placeHolderText.hidden = YES;
                });
            }
    }];
    self.hardwareKeyboardPresent = YES; //default to YES and when keybaord will appears is called, this may be set to NO
    
    // Set correct chatInput height constraints
    [self setChatInputHeightConstraints:self.hardwareKeyboardPresent];
    [self scrollToBottom];
}


-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if(!self.contact.contactJid || !self.contact.accountId) return;
    self.xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId];
    [self synchChat];
#ifndef DISABLE_OMEMO
    if(![self.contact.subscription isEqualToString:kSubBoth] && !self.contact.isGroup) {
        [self.xmppAccount queryOMEMODevicesFrom:self.contact.contactJid];
        
    }
    
    NSArray* devices = [self.xmppAccount.monalSignalStore knownDevicesForAddressName:self.contact.contactJid];
    if(devices.count == 0) {
        if(self.encryptChat) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Encryption Not Supported" message:@"This contact does not appear to have any devices that support encryption." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Disable Encryption" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                // Disable encryption
                self.encryptChat = NO;
                [self updateUIElementsOnAccountChange:nil];
                [[DataLayer sharedInstance] disableEncryptForJid:self.contact.contactJid andAccountNo:self.contact.accountId];
                [alert dismissViewControllerAnimated:YES completion:nil];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Ignore" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                [alert dismissViewControllerAnimated:YES completion:nil];
            }]];

            [self presentViewController:alert animated:YES completion:nil];
        }
    }
#endif
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refreshCounter];
    });
    
}

-(void) viewWillDisappear:(BOOL)animated
{
    // Save message draft
    [self saveMessageDraft:^(BOOL success) {
        if(success) {
            // Update status message for contact to show current draft
            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:self userInfo:@{@"contact":self.contact}];
        }
    }];
    [super viewWillDisappear:animated];
    [MLNotificationManager sharedInstance].currentAccountNo=nil;
    [MLNotificationManager sharedInstance].currentContact=nil;
    
    [self sendChatState:NO];
    [self stopLastInteractionTimer];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if(self.messageTable.contentSize.height > self.messageTable.bounds.size.height)
        [self.messageTable setContentOffset:CGPointMake(0, self.messageTable.contentSize.height - self.messageTable.bounds.size.height) animated:NO];
}

-(void) saveMessageDraft:(void (^)(BOOL))completion
{
    // Save message draft
    [[DataLayer sharedInstance] saveMessageDraft:self.contact.contactJid forAccount:self.contact.accountId withComment:self.chatInput.text withCompletion:completion];
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopLastInteractionTimer];
}

-(void) updateBackground {
    BOOL backgrounds = [[NSUserDefaults standardUserDefaults] boolForKey:@"ChatBackgrounds"];
    
    if(backgrounds){
        self.backgroundImage.hidden=NO;
        NSString *imageName= [[NSUserDefaults standardUserDefaults] objectForKey:@"BackgroundImage"];
        if(imageName)
        {
            if([imageName isEqualToString:@"CUSTOM"])
            {
                self.backgroundImage.image=[[MLImageManager sharedInstance] getBackground];
            } else  {
                self.backgroundImage.image=[UIImage imageNamed:imageName];
            }
        }
        self.transparentLayer.hidden=NO;
    }else  {
        self.backgroundImage.hidden=YES;
        self.transparentLayer.hidden=YES;
    }
}


#pragma mark rotation


-(void) viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [self.chatInput resignFirstResponder];
}


#pragma mark gestures

-(IBAction)dismissKeyboard:(id)sender
{
    [self saveMessageDraft:nil];
    [self.chatInput resignFirstResponder];
}

#pragma mark message signals

-(void) refreshCounter
{
    if(self.navigationController.topViewController==self)
    {
        if([MLNotificationManager sharedInstance].currentContact!=self.contact) {
            return;
        }
        
        if(!_day) {
            [[DataLayer sharedInstance] markAsReadBuddy:self.contact.contactJid forAccount:self.contact.accountId];
            
            MonalAppDelegate* appDelegate= (MonalAppDelegate*) [UIApplication sharedApplication].delegate;
            [appDelegate updateUnread];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:self userInfo:@{@"contact":self.contact}];
        }
    }
}

-(void) refreshData
{
    if(!self.contact.contactJid) return;
    NSMutableArray *newList;
    if(!_day) {
      [[DataLayer sharedInstance] messagesForContact:self.contact.contactJid forAccount: self.contact.accountId withCompletion:^(NSMutableArray *newList) {
            [[DataLayer sharedInstance] countUserUnreadMessages:self.contact.contactJid forAccount: self.contact.accountId withCompletion:^(NSNumber *unread) {
                      if([unread integerValue]==0) self->_firstmsg=YES;
                      
                  }];
           
          if(!self.jid) return;
          MLMessage *unreadStatus = [[MLMessage alloc] init];
          unreadStatus.messageType=kMessageTypeStatus;
          unreadStatus.messageText=NSLocalizedString(@"Unread Messages Below",@ "");
          unreadStatus.actualFrom=self.jid;
          
          NSInteger unreadPos = newList.count-1;
          while(unreadPos>=0)
          {
              MLMessage *row = [newList objectAtIndex:unreadPos];
              if(!row.unread)
              {
                  unreadPos++; //move back down one
                  break;
              }
              unreadPos--; //move up the list
          }
          
          if(unreadPos<=newList.count-1 && unreadPos>0) {
              [newList insertObject:unreadStatus atIndex:unreadPos];
          }
          
          if(newList.count!=self.messageList.count)
          {
              self.messageList = newList;
          }
          
          
        }];
      
    }
    else
    {
        newList =[[[DataLayer sharedInstance] messageHistoryDate:self.contact.contactJid forAccount: self.contact.accountId forDate:_day] mutableCopy];
        
    }
    
}




#pragma mark - textview
-(void) sendMessage:(NSString *) messageText
{
    [self sendMessage:messageText andMessageID:nil];
}

-(void) sendWithShareSheet {
    // MLXMPPActivityItem *item = [[MLXMPPActivityItem alloc] initWithPlaceholderItem:@""];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0]; // Get documents directory
    NSString *path =[documentsDirectory stringByAppendingPathComponent:@"message.xmpp"];
    
    NSURL *url = [NSURL fileURLWithPath:path];
    NSArray *items =@[url];
    //    NSArray *exclude =  @[UIActivityTypePostToTwitter, UIActivityTypePostToFacebook,
    //                          UIActivityTypePostToWeibo,
    //                          UIActivityTypeMessage, UIActivityTypeMail,
    //                          UIActivityTypePrint, UIActivityTypeCopyToPasteboard,
    //                          UIActivityTypeAssignToContact, UIActivityTypeSaveToCameraRoll,
    //                          UIActivityTypeAddToReadingList, UIActivityTypePostToFlickr,
    //                          UIActivityTypePostToVimeo, UIActivityTypePostToTencentWeibo];
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    // share.excludedActivityTypes = exclude;
    [self presentViewController:share animated:YES completion:nil];
}

-(void) sendMessage:(NSString *) messageText andMessageID:(NSString *)messageID
{
    DDLogVerbose(@"Sending message");
    NSString *newMessageID =messageID?messageID:[[NSUUID UUID] UUIDString];
    //dont readd it, use the exisitng
    
    [[DataLayer sharedInstance] detailsForAccount:self.contact.accountId withCompletion:^(NSArray *result) {
        NSArray *accounts = result;
        if(accounts.count==0) {
            DDLogError(@"Account should be >0");
            return;
        }
        NSDictionary* settings=[accounts objectAtIndex:0];
        
        if(!messageID)
        {
            NSString *contactNameCopy =self.contact.contactJid; //prevent retail cycle
            NSString *accountNoCopy = self.contact.accountId;
            BOOL isMucCopy = self.contact.isGroup;
            BOOL encryptChatCopy = self.encryptChat;
            MLContact *contactCopy = self.contact;
            
            
            [self addMessageto:self.contact.contactJid withMessage:messageText andId:newMessageID withCompletion:^(BOOL success) {
                [[MLXMPPManager sharedInstance] sendMessage:messageText toContact:contactNameCopy fromAccount:accountNoCopy isEncrypted:encryptChatCopy isMUC:isMucCopy isUpload:NO messageId:newMessageID
                                    withCompletionHandler:nil];
                [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:nil userInfo:@{@"contact":contactCopy}];
            }];
        }
        else
        {
            [[MLXMPPManager sharedInstance]
                sendMessage:messageText
                toContact:self.contact.contactJid
                fromAccount:self.contact.accountId
                isEncrypted:self.encryptChat
                isMUC:self.contact.isGroup
                isUpload:NO messageId:newMessageID
                withCompletionHandler:nil
            ];
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kMLMessageSentToContact object:self userInfo:@{@"contact":self.contact}];
    }];
}

-(void) sendChatState:(BOOL) isTyping
{
    [[DataLayer sharedInstance] detailsForAccount:self.contact.accountId withCompletion:^(NSArray *result) {
        if(result.count==0)
        {
            DDLogError(@"Account should be >0");
            return;
        }
    }];
    
    if(!self.sendButton.enabled)
    {
        DDLogWarn(@"Account disabled, ignoring chatstate update");
        return;
    }
    
    if(isTyping)
    {
        if(!_isTyping)      //started typing? --> send composing chatstate (e.g. typing)
        {
            DDLogVerbose(@"Sending chatstate isTyping=%@", isTyping ? @"YES" : @"NO");
            [[MLXMPPManager sharedInstance] sendChatState:isTyping fromAccount:self.contact.accountId toJid:self.contact.contactJid];
        }
        
        //cancel old timer if existing
        if(_cancelTypingNotification)
            _cancelTypingNotification();
        
        //start new timer
        _cancelTypingNotification = [HelperTools startTimer:5.0 withHandler:^{
            //no typing interaction in 5 seconds? --> send out active chatstate (e.g. typing ended)
            if(_isTyping)
            {
                _isTyping = NO;
                DDLogVerbose(@"Sending chatstate isTyping=NO");
                [[MLXMPPManager sharedInstance] sendChatState:NO fromAccount:self.contact.accountId toJid:self.contact.contactJid];
            }
        }];
        
        //set internal state
        _isTyping = YES;
    }
    else
    {
        if(_isTyping)      //stopped typing? --> send active chatstate (e.g. typing ended)
        {
            DDLogVerbose(@"Sending chatstate isTyping=%@", isTyping ? @"YES" : @"NO");
            [[MLXMPPManager sharedInstance] sendChatState:isTyping fromAccount:self.contact.accountId toJid:self.contact.contactJid];
        }
        
        //cancel old timer if existing
        if(_cancelTypingNotification)
            _cancelTypingNotification();
        
        //set internal state
        _isTyping = NO;
    }
}

-(void)resignTextView
{
    // Trim leading spaces
    NSString* cleanString = [self.chatInput.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // Only send msg that have at least one character
    if(cleanString.length > 0)
    {
        // Reset chatInput -> remove draft from db so that macOS will show the new send message
        [self.chatInput setText:@""];
        [self saveMessageDraft:nil];
        // Send trimmed message
        [self sendMessage:cleanString];
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
    [self.chatInput resignFirstResponder];

    [self presentViewController:self.imagePicker animated:YES completion:nil];

    return;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] init];
    [coordinator coordinateReadingItemAtURL:urls.firstObject options:NSFileCoordinatorReadingForUploading error:nil byAccessor:^(NSURL * _Nonnull newURL) {
        NSData *data =[NSData dataWithContentsOfURL:newURL];
        [self uploadData:data];
    }];
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
    [self sendMessage:[NSString stringWithFormat:@"geo:%f,%f", gpsLoc.coordinate.latitude, gpsLoc.coordinate.longitude]];
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
        self.gpsHUD.label.text =@"GPS";
        self.gpsHUD.detailsLabel.text =@"Waiting for GPS signal";
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
            UIAlertController *gpsWarning = [UIAlertController alertControllerWithTitle:@"No GPS location received"
                                                                                message:@"Monal did not received a gps location. Please try again later." preferredStyle:UIAlertControllerStyleAlert];
            [gpsWarning addAction:[UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                [gpsWarning dismissViewControllerAnimated:YES completion:nil];
            }]];
            [self presentViewController:gpsWarning animated:YES completion:nil];
        }
    });
}

#pragma mark - attachment picker

-(IBAction)attach:(id)sender
{
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

#if TARGET_OS_MACCATALYST
        [self attachfile:sender];
#else
        UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
        imagePicker.delegate =self;

        UIAlertAction* cameraAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Camera",@ "") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            imagePicker.sourceType = UIImagePickerControllerSourceTypeCamera;
            [self presentViewController:imagePicker animated:YES completion:nil];
        }];

        UIAlertAction* photosAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Photos",@ "") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                if(granted)
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self presentViewController:imagePicker animated:YES completion:nil];
                    });
                }
            }];
        }];

        // Set image
        if (@available(iOS 13.0, *)) {
            [cameraAction setValue:[[UIImage systemImageNamed:@"camera"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
            [photosAction setValue:[[UIImage systemImageNamed:@"photo"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        } else {
            [cameraAction setValue:[[UIImage imageNamed:@"714-camera"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        }
        [actionControll addAction:cameraAction];
        [actionControll addAction:photosAction];
#endif
    }
    UIAlertAction* gpsAlert = [UIAlertAction actionWithTitle:NSLocalizedString(@"Send Location",@ "") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        // GPS
        CLAuthorizationStatus gpsStatus = [CLLocationManager authorizationStatus];
        if(gpsStatus == kCLAuthorizationStatusAuthorizedAlways || gpsStatus == kCLAuthorizationStatusAuthorizedWhenInUse) {
            [self displayGPSHUD];
            [self makeLocationManager];
            [self.locationManager startUpdatingLocation];
        } else if(gpsStatus == kCLAuthorizationStatusNotDetermined) {
            [self makeLocationManager];
            self.sendLocation=YES;
            [self.locationManager requestWhenInUseAuthorization];
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
    [actionControll addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",@ "") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        [actionControll dismissViewControllerAnimated:YES completion:nil];
    }]];

    actionControll.popoverPresentationController.sourceView=sender;
    [self presentViewController:actionControll animated:YES completion:nil];
}

-(void) uploadData:(NSData *) data
{
    if(!self.uploadHUD) {
        self.uploadHUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        self.uploadHUD.removeFromSuperViewOnHide=YES;
        self.uploadHUD.label.text =NSLocalizedString(@"Uploading",@ "");
        self.uploadHUD.detailsLabel.text =NSLocalizedString(@"Uploading file to server",@ "");
        
    }
    NSData *decryptedData= data;
    NSData *dataToPass= data;
    MLEncryptedPayload *encrypted;
    
    int keySize=32;
    if(self.encryptChat) {
        encrypted = [AESGcm encrypt:decryptedData keySize:keySize];
        if(encrypted) {
            NSMutableData *mutableBody = [encrypted.body mutableCopy];
            [mutableBody appendData:encrypted.authTag];
            dataToPass = [mutableBody copy];
        } else  {
            DDLogError(@"Could not encrypt attachment");
        }
    }
    
    [[MLXMPPManager sharedInstance]  httpUploadJpegData:dataToPass toContact:self.contact.contactJid onAccount:self.contact.accountId withCompletionHandler:^(NSString *url, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.uploadHUD.hidden=YES;
            
            if(url) {
                NSString *newMessageID =[[NSUUID UUID] UUIDString];
                
                NSString *contactJidCopy =self.contact.contactJid; //prevent retail cycle
                NSString *accountNoCopy = self.contact.accountId;
                BOOL isMucCopy = self.contact.isGroup;
                BOOL encryptChatCopy = self.encryptChat;
                
                NSString *urlToPass=url;
                
                if(encrypted) {
                    NSURLComponents *urlComponents = [NSURLComponents componentsWithURL:[NSURL URLWithString:urlToPass] resolvingAgainstBaseURL:NO];
                    if(urlComponents) {
                        urlComponents.scheme = @"aesgcm";
                        urlComponents.fragment = [NSString stringWithFormat:@"%@%@",
                                                  [HelperTools hexadecimalString:encrypted.iv],
                                                  [HelperTools hexadecimalString:[encrypted.key subdataWithRange:NSMakeRange(0, keySize)]]];
                        urlToPass=urlComponents.string;
                    } else  {
                        DDLogError(@"Could not parse URL for conversion to aesgcm:");
                    }
                }
                
                [[MLImageManager sharedInstance] saveImageData:decryptedData forLink:urlToPass];
                
                [self addMessageto:self.contact.contactJid withMessage:urlToPass andId:newMessageID withCompletion:^(BOOL success) {
                    [[MLXMPPManager sharedInstance] sendMessage:urlToPass toContact:contactJidCopy fromAccount:accountNoCopy isEncrypted:encryptChatCopy isMUC:isMucCopy isUpload:YES messageId:newMessageID
                                          withCompletionHandler:nil];
                    
                }];
                
            }
            else  {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"There was an error uploading the file to the server",@ "") message:[NSString stringWithFormat:@"%@", error.localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close",@ "") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    [alert dismissViewControllerAnimated:YES completion:nil];
                }]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
        
    }];
    
    
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,
                                                                                               id> *)info
{
    [self dismissViewControllerAnimated:YES completion:nil];
    
    NSString *mediaType = info[UIImagePickerControllerMediaType];
    if([mediaType isEqualToString:(NSString *)kUTTypeImage]) {
        UIImage *selectedImage= info[UIImagePickerControllerEditedImage];
        if(!selectedImage) selectedImage= info[UIImagePickerControllerOriginalImage];
        NSData *jpgData=  UIImageJPEGRepresentation(selectedImage, 0.5f);
        if(jpgData)
        {
            [self uploadData:jpgData];
        }
        
    }
    
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - handling notfications

-(void) reloadTable
{
    if(self.messageTable.hasUncommittedUpdates) return;
    
    [self.messageTable reloadData];
}

//always messages going out
-(void) addMessageto:(NSString*)to withMessage:(NSString*) message andId:(NSString *) messageId withCompletion:(void (^)(BOOL success))completion
{
    if(!self.jid || !message)  {
        DDLogError(@" not ready to send messages");
        return;
    }

    [[DataLayer sharedInstance] addMessageHistoryFrom:self.jid to:to forAccount:self.contact.accountId withMessage:message actuallyFrom:self.jid withId:messageId encrypted:self.encryptChat withCompletion:^(BOOL result, NSString *messageType) {
        DDLogVerbose(@"added message");
        
        if(result) {
            dispatch_async(dispatch_get_main_queue(),
                           ^{
                MLMessage* messageObj = [[MLMessage alloc] init];
                messageObj.actualFrom=self.jid;
                messageObj.from=self.jid;
                messageObj.timestamp=[NSDate date];
                messageObj.hasBeenSent=YES;
                messageObj.messageId=messageId;
                messageObj.encrypted=self.encryptChat;
                messageObj.messageType=messageType;
                messageObj.messageText=message;

                [self.messageTable performBatchUpdates:^{
                    if(!self.messageList) self.messageList = [[NSMutableArray alloc] init];
                    [self.messageList addObject:messageObj];
                    NSInteger bottom = [self.messageList count]-1;
                    if(bottom>=0) {
                        NSIndexPath *path1 = [NSIndexPath indexPathForRow:bottom  inSection:0];
                        [self->_messageTable insertRowsAtIndexPaths:@[path1]
                                                   withRowAnimation:UITableViewRowAnimationFade];
                        
                    }
                } completion:^(BOOL finished) {
                    if(completion) completion(result);

                    [self scrollToBottom];
                }];
            });
        }
        else {
            DDLogVerbose(@"failed to add message");
        }
    }];
    
    // make sure its in active
    if(_firstmsg==YES)
    {
        [[DataLayer sharedInstance] addActiveBuddies:to forAccount:self.contact.accountId withCompletion:nil];
        _firstmsg=NO;
    }
}

-(void) presentMucInvite:(NSNotification *)notification
{
    xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId];
    NSDictionary *userDic = notification.userInfo;
    NSString *from = [userDic objectForKey:NSLocalizedString(@"from",@"")];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString* messageString = [NSString  stringWithFormat:NSLocalizedString(@"You have been invited to a conversation %@?",@""), from ];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Group Chat Invite",@"") message:messageString preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Join",@"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [xmppAccount joinRoom:from withNick:xmppAccount.connectionProperties.identity.user andPassword:nil];
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close",@"") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}


-(void) handleNewMessage:(NSNotification *)notification
{
    DDLogVerbose(@"chat view got new message notice %@", notification.userInfo);
    
    MLMessage *message = [notification.userInfo objectForKey:@"message"];
    if(!message) {
        DDLogError(@"Notification without message");
    }
    
    if([message.accountId isEqualToString:self.contact.accountId]
       && ([message.from isEqualToString:self.contact.contactJid]
           || [message.to isEqualToString:self.contact.contactJid] ))
    {
        if([self.contact.subscription isEqualToString:kSubBoth]) {
            //getting encrypted chat turns it on. not the other way around
            //            if(message.encrypted && !self.encryptChat) {
            //                NSArray *devices= [self.xmppAccount.monalSignalStore knownDevicesForAddressName:self.contact.contactJid];
            //                if(devices.count>0) {
            //                    dispatch_async(dispatch_get_main_queue(), ^{
            //                        [[DataLayer sharedInstance] encryptForJid:self.contact.contactJid andAccountNo:self.contact.accountId];
            //                        self.encryptChat=YES;
            //                    });
            //                }
            //            }
        }
        
        [[DataLayer sharedInstance] messageTypeForMessage: message.messageText withKeepThread:YES andCompletion:^(NSString *messageType) {
            
            dispatch_async(dispatch_get_main_queue(),
                           ^{
                NSString *finalMessageType=messageType;
                if([message.messageType isEqualToString:kMessageTypeStatus])
                {
                    finalMessageType =kMessageTypeStatus;
                }
                message.messageType=finalMessageType;
                
                if(!self.messageList) self.messageList=[[NSMutableArray alloc] init];
                [self.messageList addObject:message]; //TODO maybe we wantt to insert base on delay timestamp..
                
                [self->_messageTable beginUpdates];
                NSIndexPath *path1;
                NSInteger bottom =  self.messageList.count-1;
                if(bottom >= 0) {
                    
                    path1 = [NSIndexPath indexPathForRow:bottom  inSection:0];
                    [self->_messageTable insertRowsAtIndexPaths:@[path1]
                                               withRowAnimation:UITableViewRowAnimationBottom];
                }
                [self->_messageTable endUpdates];
                
                [self scrollToBottom];
                
                [self refreshCounter];
            });
        }];
    }
}

-(void) setMessageId:(NSString *) messageId delivered:(BOOL) delivered
{
    dispatch_async(dispatch_get_main_queue(),
                   ^{
        if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground) return;
        
        int row=0;
        NSIndexPath *indexPath;
        for(MLMessage *message in self.messageList)
        {
            if([message.messageId isEqualToString:messageId]) {
                message.hasBeenSent=delivered;
                indexPath =[NSIndexPath indexPathForRow:row inSection:0];
                break;
            }
            row++;
        }
        if(indexPath) {
            [self->_messageTable beginUpdates];
            [self->_messageTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            [self->_messageTable endUpdates];
        }
    });
}

-(void) setMessageId:(NSString *) messageId received:(BOOL) received
{
    dispatch_async(dispatch_get_main_queue(),
                   ^{
        if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground) return;
        
        int row=0;
        NSIndexPath *indexPath;
        for(MLMessage *message in self.messageList)
        {
            if([message.messageId isEqualToString:messageId]) {
                message.hasBeenReceived=received;
                indexPath =[NSIndexPath indexPathForRow:row inSection:0];
                break;
            }
            row++;
        }
        
        if(indexPath) {
            [self->_messageTable beginUpdates];
            [self->_messageTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            [self->_messageTable endUpdates];
        }
    });
}


-(void) handleSendFailedMessage:(NSNotification *)notification
{
    NSDictionary *dic =notification.userInfo;
    [self setMessageId:[dic objectForKey:kMessageId]  delivered:NO];
}

-(void) handleSentMessage:(NSNotification *)notification
{
    NSDictionary *dic =notification.userInfo;
    [self setMessageId:[dic objectForKey:kMessageId]  delivered:YES];
}


-(void) handleMessageError:(NSNotification *)notification
{
    NSDictionary *dic =notification.userInfo;
   
    NSString *messageId= [dic objectForKey:kMessageId];
    dispatch_async(dispatch_get_main_queue(),
                   ^{
        if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground) return;
        
        int row=0;
        NSIndexPath *indexPath;
        for(MLMessage *message in self.messageList)
        {
            if([message.messageId isEqualToString:messageId] && !message.hasBeenReceived) {
                message.errorType=[dic objectForKey:@"errorType"];
                message.errorReason=[dic objectForKey:@"errorReason"];
                message.hasBeenSent = NO;
                indexPath =[NSIndexPath indexPathForRow:row inSection:0];
                break;
            }
            row++;
        }
        if(indexPath) {
            [self->_messageTable beginUpdates];
            [self->_messageTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            [self->_messageTable endUpdates];
        }
    });
}

-(void) refreshMessage:(NSNotification *)notification
{
    NSDictionary *dic =notification.userInfo;
    [self setMessageId:[dic  objectForKey:kMessageId]  received:YES];
}


-(void) scrollToBottom
{
    if(self.messageList.count==0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger bottom = [self.messageTable numberOfRowsInSection:0];
        if(bottom>0)
        {
            NSIndexPath *path1 = [NSIndexPath indexPathForRow:bottom-1  inSection:0];
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
    self.thisday =[self.gregorian components:NSCalendarUnitDay fromDate:now].day;
    self.thismonth =[self.gregorian components:NSCalendarUnitMonth fromDate:now].month;
    self.thisyear =[self.gregorian components:NSCalendarUnitYear fromDate:now].year;
}


-(NSString*) formattedDateWithSource:(NSDate *) sourceDate  andPriorDate:(NSDate *) priorDate
{
    NSString* dateString;
    if(sourceDate!=nil)
    {
        
        NSInteger msgday =[self.gregorian components:NSCalendarUnitDay fromDate:sourceDate].day;
        NSInteger msgmonth=[self.gregorian components:NSCalendarUnitMonth fromDate:sourceDate].month;
        NSInteger msgyear =[self.gregorian components:NSCalendarUnitYear fromDate:sourceDate].year;
        
        NSInteger priorDay=0;
        NSInteger priorMonth=0;
        NSInteger priorYear=0;
        
        if(priorDate) {
            priorDay =[self.gregorian components:NSCalendarUnitDay fromDate:priorDate].day;
            priorMonth=[self.gregorian components:NSCalendarUnitMonth fromDate:priorDate].month;
            priorYear =[self.gregorian components:NSCalendarUnitYear fromDate:priorDate].year;
        }
        
        if (priorDate && ((priorDay!=msgday) || (priorMonth!=msgmonth) || (priorYear!=msgyear))  )
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
    if(sourceDate!=nil)
    {
        [self.destinationDateFormat setDateStyle:NSDateFormatterNoStyle];
        [self.destinationDateFormat setTimeStyle:NSDateFormatterShortStyle];
        
        dateString = [self.destinationDateFormat stringFromDate:sourceDate];
    }
    
    return dateString;
}



-(void) retry:(id) sender
{
    NSInteger historyId = ((UIButton*) sender).tag;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Retry sending message?",@ "") message:NSLocalizedString(@"This message failed to send.",@ "") preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Retry",@ "") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSArray *messageArray =[[DataLayer sharedInstance] messageForHistoryID:historyId];
        if([messageArray count]>0) {
            NSDictionary *dic= [messageArray objectAtIndex:0];
            [self sendMessage:[dic objectForKey:@"message"] andMessageID:[dic objectForKey:@"messageid"]];
            [self setMessageId:[dic objectForKey:@"messageid"] delivered:YES]; // for the UI, db will be set in the notification
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",@ "") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    alert.popoverPresentationController.sourceView=sender;
    
    [self presentViewController:alert animated:YES completion:nil];
    
}

#pragma mark - tableview datasource

-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger toReturn=0;
    
    switch (section) {
        case 0:
        {
            toReturn=[self.messageList count];
            break;
        }
        default:
            break;
    }
    
    return toReturn;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    MLBaseCell* cell;
    
    MLMessage* row;
    if(indexPath.row<self.messageList.count) {
        row= [self.messageList objectAtIndex:indexPath.row];
    } else  {
        DDLogError(@"Attempt to access beyond bounds");
    }
    
    NSString* from = row.from;
    
    //cut text after 2048 chars to make the message cell work properly (too big texts don't render the text in the cell at all)
    NSString* messageText = row.messageText;
    if([messageText length] > 2048)
        messageText = [NSString stringWithFormat:@"%@\n[...]", [messageText substringToIndex:2048]];
    
    if([row.messageType isEqualToString:kMessageTypeStatus])
    {
        cell=[tableView dequeueReusableCellWithIdentifier:@"StatusCell"];
        cell.messageBody.text = messageText;
        cell.link=nil;
        return cell;
    }
    
    if(self.contact.isGroup)
    {
        if([from isEqualToString:self.contact.contactJid])
        {
            if([row.messageType isEqualToString:kMessageTypeUrl])
            {
                cell=[tableView dequeueReusableCellWithIdentifier:@"linkInCell"];
            } else  {
                cell=[tableView dequeueReusableCellWithIdentifier:@"textInCell"];
            }
        }
        else
        {
            if([row.messageType isEqualToString:kMessageTypeUrl])
            {
                cell=[tableView dequeueReusableCellWithIdentifier:@"linkOutCell"];
            } else  {
                cell=[tableView dequeueReusableCellWithIdentifier:@"textOutCell"];
            }
            
        }
    } else  {
        if([from isEqualToString:self.contact.contactJid])
        {
            if([row.messageType isEqualToString:kMessageTypeUrl])
            {
                cell=[tableView dequeueReusableCellWithIdentifier:@"linkInCell"];
            }  else  {
                cell=[tableView dequeueReusableCellWithIdentifier:@"textInCell"];
            }
        }
        else
        {
            if([row.messageType isEqualToString:kMessageTypeUrl])
            {
                cell=[tableView dequeueReusableCellWithIdentifier:@"linkOutCell"];
            } else  {
                cell=[tableView dequeueReusableCellWithIdentifier:@"textOutCell"];
            }
        }
        
    }
    
    if([row.messageType isEqualToString:kMessageTypeImage])
    {
        MLChatImageCell* imageCell;
        if([from isEqualToString:self.contact.contactJid])
        {
            imageCell= (MLChatImageCell *) [tableView dequeueReusableCellWithIdentifier:@"imageInCell"];
            imageCell.outBound=NO;
        }
        else  {
            imageCell= (MLChatImageCell *) [tableView dequeueReusableCellWithIdentifier:@"imageOutCell"];
            imageCell.outBound=YES;
        }
        
        
        if(![imageCell.link isEqualToString:messageText]){
            imageCell.link = messageText;
            imageCell.thumbnailImage.image=nil;
            imageCell.loading=NO;
            [imageCell loadImageWithCompletion:^{}];
        }
        cell=imageCell;
        
    }
    else if ([row.messageType isEqualToString:kMessageTypeUrl]) {
        MLLinkCell *toreturn;
        if([from isEqualToString:self.contact.contactJid]) {
            toreturn=(MLLinkCell *)[tableView dequeueReusableCellWithIdentifier:@"linkInCell"];
        }
        else  {
            toreturn=(MLLinkCell *)[tableView dequeueReusableCellWithIdentifier:@"linkOutCell"];
        }
        
        NSString * cleanLink=[messageText  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSArray *parts = [cleanLink componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        cell.link = parts[0];
        
        toreturn.messageBody.text =cell.link;
        toreturn.link=cell.link;
        
        if(row.previewText || row.previewImage)
        {
            toreturn.imageUrl = row.previewImage;
            toreturn.messageTitle.text = row.previewText;
            [toreturn loadImageWithCompletion:^{
                
            }];
        }  else {
            [toreturn loadPreviewWithCompletion:^{
                if(toreturn.messageTitle.text.length==0) toreturn.messageTitle.text=@" "; // prevent repeated calls
                [[DataLayer sharedInstance] setMessageId:row.messageId previewText:toreturn.messageTitle.text  andPreviewImage:toreturn.imageUrl.absoluteString];
            }];
        }
        cell=toreturn;
    } else if ([row.messageType isEqualToString:kMessageTypeGeo]) {
        // Parse latitude and longitude
        NSString* geoPattern = @"^geo:(-?(?:90|[1-8][0-9]|[0-9])(?:\\.[0-9]{1,32})?),(-?(?:180|1[0-7][0-9]|[0-9]{1,2})(?:\\.[0-9]{1,32})?)$";
        NSError *error = NULL;
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
            if([[NSUserDefaults standardUserDefaults] boolForKey: @"ShowGeoLocation"]) {
                MLChatMapsCell* mapsCell;
                if([from isEqualToString:self.contact.contactJid]) {
                    mapsCell = (MLChatMapsCell *) [tableView dequeueReusableCellWithIdentifier:@"mapsInCell"];
                    mapsCell.outBound = NO;
                } else  {
                    mapsCell = (MLChatMapsCell *) [tableView dequeueReusableCellWithIdentifier:@"mapsOutCell"];
                }

                // Set lat / long used for map view and pin
                mapsCell.latitude = [latitude doubleValue];
                mapsCell.longitude = [longitude doubleValue];

                [mapsCell loadCoordinatesWithCompletion:^{}];
                cell = mapsCell;
            } else {
                NSMutableAttributedString* geoString = [[NSMutableAttributedString alloc] initWithString:messageText];
                [geoString addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:[geoMatch rangeAtIndex:0]];

                cell.messageBody.attributedText = geoString;
                NSInteger zoomLayer = 15;
                cell.link = [NSString stringWithFormat:@"https://www.openstreetmap.org/?mlat=%@&mlon=%@&zoom=%ldd", latitude, longitude, zoomLayer];
            }
        } else {
            cell.messageBody.text = messageText;
            cell.link = nil;
        }
    } else {
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
                NSDictionary *underlineAttribute = @{NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)};
                NSAttributedString* underlined = [[NSAttributedString alloc] initWithString:cell.link attributes:underlineAttribute];
                NSMutableAttributedString* stitchedString  = [[NSMutableAttributedString alloc] init];
                [stitchedString appendAttributedString:
                 [[NSAttributedString alloc] initWithString:[messageText substringToIndex:pos.location] attributes:nil]];
                [stitchedString appendAttributedString:underlined];
                if(pos2.location!=NSNotFound)
                {
                    NSString* remainder = [messageText substringFromIndex:pos.location+[underlined length]];
                    [stitchedString appendAttributedString:[[NSAttributedString alloc] initWithString:remainder attributes:nil]];
                }
                cell.messageBody.attributedText=stitchedString;
            }
        }
        else // Default case
        {
            cell.messageBody.text = messageText;
            cell.link = nil;
        }
    }
    
    if(self.contact.isGroup)
    {
        cell.name.hidden=NO;
        cell.name.text=row.actualFrom;
    } else  {
        cell.name.text=@"";
        cell.name.hidden=YES;
    }
    
    if(!row.hasBeenSent){
        cell.deliveryFailed=YES;
    } else {
        cell.deliveryFailed=NO;
    }
    
    MLMessage *nextRow =nil;
    if(indexPath.row+1<self.messageList.count)
    {
        nextRow = [self.messageList objectAtIndex:indexPath.row+1];
    }
    
    MLMessage *priorRow =nil;
    if(indexPath.row>0)
    {
        priorRow = [self.messageList objectAtIndex:indexPath.row-1];
    }
    
    if(row.hasBeenReceived==YES) {
        cell.messageStatus.text=kDelivered;
        if(indexPath.row==self.messageList.count-1 ||
           ![nextRow.actualFrom isEqualToString:self.jid]) {
            cell.messageStatus.hidden=NO;
        } else  {
            cell.messageStatus.hidden=YES;
        }
    }
    else  {
        cell.messageStatus.hidden=YES;
    }
    
    cell.messageHistoryId=row.messageDBId;
    BOOL newSender=NO;
    if(indexPath.row>0)
    {
        NSString *priorSender =priorRow.from;
        if(![priorSender isEqualToString:row.from])
        {
            newSender=YES;
        }
    }
    
    cell.date.text= [self formattedTimeStampWithSource:row.delayTimeStamp?row.delayTimeStamp:row.timestamp];
    cell.selectionStyle=UITableViewCellSelectionStyleNone;
    
    cell.dividerDate.text = [self formattedDateWithSource:row.delayTimeStamp?row.delayTimeStamp:row.timestamp andPriorDate:priorRow.timestamp];
    
    if(row.encrypted)
    {
        cell.lockImage.hidden=NO;
    } else  {
        cell.lockImage.hidden=YES;
    }
    
    if([row.from isEqualToString:_jid])
    {
        cell.outBound=YES;
    }
    else  {
        cell.outBound=NO;
    }
    
    cell.parent=self;
    
    if(!row.hasBeenReceived) {
        if(row.errorType.length>0) {
            cell.messageStatus.text =[NSString stringWithFormat:@"Error:%@ - %@", row.errorType, row.errorReason];
            cell.messageStatus.hidden=NO;
        }
    }
    
    [cell updateCellWithNewSender:newSender];
    
    return cell;
}

#pragma mark - tableview delegate
-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self.chatInput resignFirstResponder];
    MLBaseCell* cell = [tableView cellForRowAtIndexPath:indexPath];
    if(cell.link)
    {
        if([cell respondsToSelector:@selector(openlink:)]) {
            [(MLChatCell *)cell openlink:self];
        } else  {
            self.photos =[[NSMutableArray alloc] init];
            MLChatImageCell *imageCell = (MLChatImageCell *) cell;
            IDMPhoto* photo=[IDMPhoto photoWithImage:imageCell.thumbnailImage.image];
            // photo.caption=[row objectForKey:@"caption"];
            [self.photos addObject:photo];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if(self.photos.count>0) {
                IDMPhotoBrowser *browser = [[IDMPhotoBrowser alloc] initWithPhotos:self.photos];
                browser.delegate=self;
               
                UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Close",@"") style:UIBarButtonItemStyleDone target:self action:@selector(closePhotos)];
                browser.navigationItem.rightBarButtonItem=close;
                
                //                browser.displayActionButton = YES; // Show action button to allow sharing, copying, etc (defaults to YES)
                //                browser.displayNavArrows = NO; // Whether to display left and right nav arrows on toolbar (defaults to NO)
                //                browser.displaySelectionButtons = NO; // Whether selection buttons are shown on each image (defaults to NO)
                //                browser.zoomPhotosToFill = YES; // Images that almost fill the screen will be initially zoomed to fill (defaults to YES)
                //                browser.alwaysShowControls = NO; // Allows to control whether the bars and controls are always visible or whether they fade away to show the photo full (defaults to NO)
                //                browser.enableGrid = YES; // Whether to allow the viewing of all the photo thumbnails on a grid (defaults to YES)
                //                browser.startOnGrid = NO; // Whether to start on the grid of thumbnails instead of the first photo (defaults to NO)
                //
                UINavigationController *nav =[[UINavigationController alloc] initWithRootViewController:browser];
                
                
                [self presentViewController:nav animated:YES completion:nil];
            }
        });
        
    }
}

-(void) closePhotos {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark tableview datasource

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES; // for now
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}


- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        MLMessage* message= [self.messageList objectAtIndex:indexPath.row];
        
        DDLogVerbose(@"%@", message);
        
        if(message.messageId)
        {
            [[DataLayer sharedInstance] deleteMessageHistory:message.messageDBId];
        }
        else
        {
            return;
        }
        [self.messageList removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationRight];
        
        
    }
}

- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender
{
    return YES;
}

//dummy function needed to remove warnign
-(void) openlink: (id) sender {
    
}

- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender
{
    
}


-(BOOL) canBecomeFirstResponder
{
    return YES;
}

-(UIView *) inputAccessoryView
{
    return self.inputContainerView;
}


# pragma mark - Textview delegate functions

- (void)textViewDidBeginEditing:(UITextView *)textView
{
    [self scrollToBottom];
}


- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    BOOL shouldinsert=YES;
    
    [self sendChatState:YES];
    
    if(self.hardwareKeyboardPresent &&  [text isEqualToString:@"\n"])
    {
        [self resignTextView];
        shouldinsert = NO;
    }
    
    return shouldinsert;
}

- (void)textViewDidChange:(UITextView *)textView
{
    if(textView.text.length>0)
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
    [self saveMessageDraft:nil];

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

@end
