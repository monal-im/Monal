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

#import "MLConstants.h"
#import "MonalAppDelegate.h"
#import "MBProgressHUD.h"
#import "UIActionSheet+Blocks.h"
#import <DropBoxSDK/DropBoxSDK.h>

#import "IDMPhotoBrowser.h"
#import "ContactDetails.h"
#import "MLXMPPActivityItem.h"

@import QuartzCore;
@import MobileCoreServices;

static const int ddLogLevel = LOG_LEVEL_ERROR;

@interface chatViewController()<DBRestClientDelegate, IDMPhotoBrowserDelegate>

@property (nonatomic, strong)  NSDateFormatter* destinationDateFormat;
@property (nonatomic, strong)  NSDateFormatter* sourceDateFormat;
@property (nonatomic, strong)  NSCalendar *gregorian;
@property (nonatomic, assign)  NSInteger thisyear;
@property (nonatomic, assign)  NSInteger thismonth;
@property (nonatomic, assign)  NSInteger thisday;
@property (nonatomic, strong)  MBProgressHUD *uploadHUD;

@property (nonatomic, strong) NSMutableArray* messageList;
@property (nonatomic, strong) NSMutableArray* photos;

@property (nonatomic, strong) DBRestClient *restClient;
@property (nonatomic, assign) BOOL encryptChat;

@property (nonatomic, strong) NSDate* lastMamDate;
@property (nonatomic, assign) BOOL hardwareKeyboardPresent;

/**
 if set to yes will prevent scrolling and resizing. useful for resigning first responder just to set auto correct
 */
@property (nonatomic, assign) BOOL blockAnimations;

@end

@implementation chatViewController

-(void) setup
{
    _contactName=[_contact objectForKey:@"buddy_name"];
    if(!_contactName)
    {
        _contactName=[_contact objectForKey:@"message_from"];
    }
    _contactFullName=[[DataLayer sharedInstance] nickName:_contactName forAccount:[NSString stringWithFormat:@"%@",[_contact objectForKey:@"account_id"]]];
   
    if (!_contactFullName) {
    _contactFullName=[[DataLayer sharedInstance] fullName:_contactName forAccount:[NSString stringWithFormat:@"%@",[_contact objectForKey:@"account_id"]]];
    }
    if (!_contactFullName) _contactFullName=_contactName;
    
    self.accountNo=[NSString stringWithFormat:@"%ld",[[_contact objectForKey:@"account_id"] integerValue]];
    self.hidesBottomBarWhenPushed=YES;
    
    NSArray* accountVals =[[DataLayer sharedInstance] accountVals:self.accountNo];
    if([accountVals count]>0)
    {
        self.jid=[NSString stringWithFormat:@"%@@%@",[[accountVals objectAtIndex:0] objectForKey:@"username"], [[accountVals objectAtIndex:0] objectForKey:@"domain"]];
    }
    

}

-(void) setupWithContact:(NSDictionary*) contact
{
    _contact=contact;
    [self setup];
    
}

#pragma mark -  view lifecycle

-(void) viewDidLoad
{
    [super viewDidLoad];
    [self setupDateObjects];
    containerView= self.view;
    self.messageTable.scrollsToTop=YES;
    self.chatInput.scrollsToTop=NO;
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    [nc addObserver:self selector:@selector(handleSendFailedMessage:) name:kMonalSendFailedMessageNotice object:nil];
    [nc addObserver:self selector:@selector(handleSentMessage:) name:kMonalSentMessageNotice object:nil];
  
    
    
    [nc addObserver:self selector:@selector(dismissKeyboard:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(handleForeGround) name:UIApplicationWillEnterForegroundNotification object:nil];
    [nc addObserver:self selector:@selector(handleBackground) name:UIApplicationWillResignActiveNotification object:nil];
    
	[nc addObserver:self selector:@selector(keyboardWillShow:) name: UIKeyboardWillShowNotification object:nil];
	[nc addObserver:self selector:@selector(keyboardWillHide:) name: UIKeyboardWillHideNotification object:nil];
	[nc addObserver:self selector:@selector(keyboardDidShow:) name: UIKeyboardDidShowNotification object:nil];
  
    [nc addObserver:self selector:@selector(refreshMessage:) name:kMonalMessageReceivedNotice object:nil];
    [nc addObserver:self selector:@selector(presentMucInvite:) name:kMonalReceivedMucInviteNotice object:nil];

    [nc addObserver:self selector:@selector(refreshButton:) name:kMonalAccountStatusChanged object:nil];
    [nc addObserver:self selector:@selector(fetchMoreMessages) name:kMLMAMMore object:nil];
    
    
    self.hidesBottomBarWhenPushed=YES;
    
    self.chatInput.layer.borderColor=[UIColor lightGrayColor].CGColor;
    self.chatInput.layer.cornerRadius=3.0f;
    self.chatInput.layer.borderWidth=0.5f;
    self.chatInput.textContainerInset=UIEdgeInsetsMake(5, 0, 5, 0);
        
//    self.inputContainerView.layer.borderColor=[UIColor lightGrayColor].CGColor;
//    self.inputContainerView.layer.borderWidth=0.5f;
    
    if ([DBSession sharedSession].isLinked) {
        self.restClient = [[DBRestClient alloc] initWithSession:[DBSession sharedSession]];
        self.restClient.delegate = self;
    }
    
    self.messageTable.rowHeight = UITableViewAutomaticDimension;
    self.messageTable.estimatedRowHeight=UITableViewAutomaticDimension;
   
}

-(void) handleForeGround {
    [self refreshData];
    [self reloadTable];
}


-(void) handleBackground {
    [self refreshCounter];
}

-(void) synchChat {
    dispatch_async(dispatch_get_main_queue(), ^{
        
        xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountNo];
        if(xmppAccount.supportsMam2 & !self->_isMUC) {
            
            //synch point
            // if synch point < login time
            NSDate *synch = [[DataLayer sharedInstance] synchPointForContact:self.contactName andAccount:self.accountNo];
            NSDate * connectedTime = [[MLXMPPManager sharedInstance] connectedTimeFor:self.accountNo];
            
            if([synch timeIntervalSinceReferenceDate]<[connectedTime timeIntervalSinceReferenceDate])
            {
                if(self.messageList.count==0) {
                    [xmppAccount setMAMQueryMostRecentForJid:self.contactName];
                } else  {
                    [xmppAccount setMAMQueryFromStart:synch toDate:nil andJid:self.contactName];
                }
                [[DataLayer sharedInstance] setSynchPoint:[NSDate date] ForContact:self.contactName andAccount:self.accountNo];
            }
        }

    });
}

-(void) fetchMoreMessages
{
  [self synchChat];
}

-(void) refreshButton:(NSNotification *) notificaiton
{
    if(!self.accountNo) return; 
    xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountNo];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *title = [[DataLayer sharedInstance] fullName:self.contactName forAccount:self.accountNo];
        if(title.length==0) title=self.contactName;
        
        if(xmppAccount.accountState<kStateLoggedIn)
        {
         //   self.sendButton.enabled=NO;
            if(!title) title=@"";
            if(self.contactName.length>0){
                self.navigationItem.title=[NSString stringWithFormat:@"%@ [%@]", title, @"Logged Out"];
            }
        }
        else  {
           // self.sendButton.enabled=YES;
            self.navigationItem.title=title;
            
        }
        
        if(self.encryptChat){
            self.navigationItem.title = [NSString stringWithFormat:@"%@ 🔒", self.navigationItem.title];
        }
    });
}


-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [MLNotificationManager sharedInstance].currentAccountNo=self.accountNo;
    [MLNotificationManager sharedInstance].currentContact=self.contactName;
    
    if(self.day) {
        NSString *title = [[DataLayer sharedInstance] fullName:self.contactName forAccount:self.accountNo];
        if(title.length==0) title=self.contactName;
        self.navigationItem.title=  [NSString stringWithFormat:@"%@(%@)", self.navigationItem.title, _day];
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        self.inputContainerView.hidden=YES;
    }
    else {
        self.inputContainerView.hidden=NO;
    }
    
    if(self.contactName && self.accountNo) {
        self.encryptChat =[[DataLayer sharedInstance] shouldEncryptForJid:self.contactName andAccountNo:self.accountNo];
    }
    [self handleForeGround];
    [self refreshButton:nil];

    [self updateBackground];
  

}


-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if(!self.contactName || !self.accountNo) return; 
    
    [self refreshCounter];
    [self synchChat];
#ifndef DISABLE_OMEMO
    xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountNo];
    [xmppAccount queryOMEMODevicesFrom:self.contactName];
#endif
  //  [self scrollToBottom];
    
}

-(void) viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [MLNotificationManager sharedInstance].currentAccountNo=nil;
    [MLNotificationManager sharedInstance].currentContact=nil;
    
    [self refreshCounter];

}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if(self.messageTable.contentSize.height>self.messageTable.bounds.size.height)
        [self.messageTable setContentOffset:CGPointMake(0, self.messageTable.contentSize.height- self.messageTable.bounds.size.height) animated:NO];
    
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
     [self.chatInput resignFirstResponder];
}

#pragma mark message signals

-(void) refreshCounter
{
    if(!_day) {
        [[DataLayer sharedInstance] markAsReadBuddy:self.contactName forAccount:self.accountNo];
        
        MonalAppDelegate* appDelegate= (MonalAppDelegate*) [UIApplication sharedApplication].delegate;
        [appDelegate updateUnread];
    }
    
}

-(void) refreshData
{
    if(!_contactName) return;
    NSMutableArray *newList;
    if(!_day) {
        newList =[[DataLayer sharedInstance] messageHistory:_contactName forAccount: _accountNo];
        [[DataLayer sharedInstance] countUserUnreadMessages:_contactName forAccount: _accountNo withCompletion:^(NSNumber *unread) {
            if([unread integerValue]==0) _firstmsg=YES;
            
        }];
        _isMUC=[[DataLayer sharedInstance] isBuddyMuc:_contactName forAccount: _accountNo];
        
    }
    else
    {
        newList =[[[DataLayer sharedInstance] messageHistoryDate:_contactName forAccount: _accountNo forDate:_day] mutableCopy];
        
    }

    if(!self.jid) return;
    NSDictionary* unreadStatus = @{@"af": self.jid,
                              @"message": @"Unread Messages Below" ,
                              kMessageType:kMessageTypeStatus
                              };
    int unreadPos = newList.count-1;
    while(unreadPos>=0)
    {
        NSDictionary *row = [newList objectAtIndex:unreadPos];
        if([[row objectForKey:@"unread"] boolValue]==NO)
        {
            unreadPos++; 
            break;
        }
        unreadPos--;
    }
    
    if(unreadPos<newList.count-1){
        [newList insertObject:unreadStatus atIndex:unreadPos];
    }
    
    if(newList.count!=self.messageList.count)
    {
        self.messageList = newList;
    }
}




#pragma mark textview
-(void) sendMessage:(NSString *) messageText
{
    [self sendMessage:messageText andMessageID:nil];
}

-(void) sendWithShareSheet {
    MLXMPPActivityItem *item = [MLXMPPActivityItem alloc]; 
    NSArray *items =@[item];
    NSArray *exclude =  @[UIActivityTypePostToTwitter, UIActivityTypePostToFacebook,
                          UIActivityTypePostToWeibo,
                          UIActivityTypeMessage, UIActivityTypeMail,
                          UIActivityTypePrint, UIActivityTypeCopyToPasteboard,
                          UIActivityTypeAssignToContact, UIActivityTypeSaveToCameraRoll,
                          UIActivityTypeAddToReadingList, UIActivityTypePostToFlickr,
                          UIActivityTypePostToVimeo, UIActivityTypePostToTencentWeibo];
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
   // share.excludedActivityTypes = exclude; 
    [self presentViewController:share animated:YES completion:nil];
}

-(void) sendMessage:(NSString *) messageText andMessageID:(NSString *)messageID
{
    DDLogVerbose(@"Sending message");
    NSString *newMessageID =messageID?messageID:[[NSUUID UUID] UUIDString];
    //dont readd it, use the exisitng
    xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountNo];
    if(xmppAccount.accountState<kStateLoggedIn)
    {
        DDLogInfo(@"Sending Via share sheet");
        [self sendWithShareSheet];
        
    } else  {
    if(!messageID) {
        NSString *contactNameCopy =_contactName; //prevent retail cycle
        NSString *accountNoCopy = _accountNo;
        BOOL isMucCopy = _isMUC;
        BOOL encryptChatCopy = self.encryptChat;
        
    
        [self addMessageto:_contactName withMessage:messageText andId:newMessageID withCompletion:^(BOOL success) {
            [[MLXMPPManager sharedInstance] sendMessage:messageText toContact:contactNameCopy fromAccount:accountNoCopy isEncrypted:encryptChatCopy isMUC:isMucCopy isUpload:NO messageId:newMessageID
                                  withCompletionHandler:nil];
        }];
    }
    else  {
        [[MLXMPPManager sharedInstance] sendMessage:messageText toContact:_contactName fromAccount:_accountNo isEncrypted:self.encryptChat isMUC:_isMUC isUpload:NO messageId:newMessageID
                              withCompletionHandler:nil];
    }
    }
}

-(void)resignTextView
{
    NSString *cleanstring = [self.chatInput.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if(cleanstring.length>0)
    {
        self.blockAnimations=YES;
        if(self.chatInput.isFirstResponder) {
            [self.chatInput resignFirstResponder];//apply autocorrect
            [self.chatInput becomeFirstResponder];
        }
        self.blockAnimations=NO;

        [self sendMessage:cleanstring];

        [self.chatInput setText:@""];
        [self scrollToBottom];
    }
}

-(IBAction)sendMessageText:(id)sender
{
    [self resignTextView];
    [self updateInputViewSize];

}

-(void) prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"showDetails"])
    {
        UINavigationController *nav = segue.destinationViewController;
        ContactDetails* details = (ContactDetails *)nav.topViewController;
        details.contact= _contact;
    }
}

#pragma mark - Dropbox upload and delegate

- (void) uploadImageToDropBox:(NSData *) imageData {

    NSString *fileName = [NSString stringWithFormat:@"%@.jpg",[NSUUID UUID].UUIDString];
    NSString *tempDir = NSTemporaryDirectory();
    NSString *imagePath = [tempDir stringByAppendingPathComponent:fileName];
    [imageData writeToFile:imagePath atomically:YES];
    
    [self.restClient uploadFile:fileName toPath:@"/" withParentRev:nil fromPath:imagePath];
}

- (void)restClient:(DBRestClient *)client uploadedFile:(NSString *)destPath
              from:(NSString *)srcPath metadata:(DBMetadata *)metadata {
    DDLogVerbose(@"File uploaded successfully to dropbox path: %@", metadata.path);
    [self.restClient loadSharableLinkForFile:metadata.path];
}

- (void)restClient:(DBRestClient *)client uploadFileFailedWithError:(NSError *)error {
    DDLogVerbose(@"File upload to dropbox failed with error: %@", error);
}

- (void)restClient:(DBRestClient*)client uploadProgress:(CGFloat)progress
           forFile:(NSString*)destPath from:(NSString*)srcPat
{
    self.uploadHUD.progress=progress;
}

- (void)restClient:(DBRestClient*)restClient loadedSharableLink:(NSString*)link
           forFile:(NSString*)path{
    NSString *newMessageID =[[NSUUID UUID] UUIDString];
 
    [self addMessageto:_contactName withMessage:link andId:newMessageID withCompletion:^(BOOL success) {
        [[MLXMPPManager sharedInstance] sendMessage:link toContact:_contactName fromAccount:_accountNo isEncrypted:self.encryptChat isMUC:_isMUC isUpload:YES messageId:newMessageID
                              withCompletionHandler:nil];
    }];
    
    self.uploadHUD.hidden=YES;
    self.uploadHUD=nil;
}

- (void)restClient:(DBRestClient*)restClient loadSharableLinkFailedWithError:(NSError*)error{
    self.uploadHUD.hidden=YES;
    self.uploadHUD=nil;
    DDLogVerbose(@"Failed to get Dropbox link with error: %@", error);
}

#pragma mark - image picker

-(IBAction)attach:(id)sender
{
    [self.chatInput resignFirstResponder];
    xmpp* account=[[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountNo];
    if(!account.supportsHTTPUpload && !self.restClient)
    {
        
        UIAlertView *addError = [[UIAlertView alloc]
                                 initWithTitle:@"Error"
                                 message:@"This server does not appear to support HTTP file uploads (XEP-0363). Please ask the administrator to enable it. You can also link to DropBox in settings and use that to share files."
                                 delegate:nil cancelButtonTitle:@"Close"
                                 otherButtonTitles: nil] ;
        [addError show];
        
        return;
    }
    
    UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
    imagePicker.delegate =self;
    
    RIButtonItem* cancelButton = [RIButtonItem itemWithLabel:NSLocalizedString(@"Cancel", nil) action:^{
        
    }];
    
    RIButtonItem* cameraButton = [RIButtonItem itemWithLabel:@"Camera" action:^{
        imagePicker.sourceType = UIImagePickerControllerSourceTypeCamera;
        [self presentViewController:imagePicker animated:YES completion:nil];
    }];
    
    RIButtonItem* photosButton = [RIButtonItem itemWithLabel:@"Photos" action:^{
          imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            if(granted)
            {
                [self presentViewController:imagePicker animated:YES completion:nil];
            }
        }];

    }];
    
    UIActionSheet* sheet =[[UIActionSheet alloc] initWithTitle:@"Select Image Source" cancelButtonItem:cancelButton destructiveButtonItem:nil otherButtonItems: cameraButton, photosButton,nil];
    [sheet showFromTabBar:self.tabBarController.tabBar];

}


-(void) uploadData:(NSData *) data
{
    if(!self.uploadHUD) {
        self.uploadHUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        self.uploadHUD.removeFromSuperViewOnHide=YES;
        self.uploadHUD.label.text =@"Uploding";
        self.uploadHUD.detailsLabel.text =@"Upoading file to server";
        
    }
    
    //if you have configured it, defer to dropbox
    if(self.restClient)
    {
        self.uploadHUD.mode=MBProgressHUDModeDeterminate;
        self.uploadHUD.progress=0;
        [self uploadImageToDropBox:data];
    }
    else  {
        [[MLXMPPManager sharedInstance]  httpUploadJpegData:data toContact:self.contactName onAccount:self.accountNo withCompletionHandler:^(NSString *url, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.uploadHUD.hidden=YES;
                
                if(url) {
                    NSString *newMessageID =[[NSUUID UUID] UUIDString];
                   
                    [self addMessageto:_contactName withMessage:url andId:newMessageID withCompletion:^(BOOL success) {
                        [[MLXMPPManager sharedInstance] sendMessage:url toContact:_contactName fromAccount:_accountNo isEncrypted:self.encryptChat isMUC:_isMUC isUpload:YES messageId:newMessageID
                                              withCompletionHandler:nil];
                        
                    }];
                    
                }
                else  {
                    UIAlertView *addError = [[UIAlertView alloc]
                                             initWithTitle:@"There was an error uploading the file to the server"
                                             message:[NSString stringWithFormat:@"%@", error.localizedDescription]
                                             delegate:nil cancelButtonTitle:@"Close"
                                             otherButtonTitles: nil] ;
                    [addError show];
                }
            });
            
        }];
    }

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
    [_messageTable reloadData];
}

//always messages going out
-(void) addMessageto:(NSString*)to withMessage:(NSString*) message andId:(NSString *) messageId withCompletion:(void (^)(BOOL success))completion
{
	if(!self.jid || !message)  {
        DDLogError(@" not ready to send messages");
        return;
    }
    
    [[DataLayer sharedInstance] addMessageHistoryFrom:self.jid to:to forAccount:_accountNo withMessage:message actuallyFrom:self.jid withId:messageId encrypted:self.encryptChat withCompletion:^(BOOL result, NSString *messageType) {
		DDLogVerbose(@"added message");
        
        if(result) {
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           NSString *messagetime = [self currentGMTTime];
                           
                           NSDictionary* userInfo = @{@"af": self.jid,
                                                      @"message": message ,
                                                      @"thetime": messagetime,
                                                      @"delivered":@YES,
                                                      @"messageid": messageId,
                                                      @"encrypted":[NSNumber numberWithBool:self.encryptChat],
                                                      kMessageType:messageType
                                                      };
                           if(!self.messageList) self.messageList =[[NSMutableArray alloc] init];
                           [self.messageList addObject:[userInfo mutableCopy]];
                           
                           NSIndexPath *path1;
                           [self->_messageTable beginUpdates];
                           NSInteger bottom = [self.messageList count]-1;
                           if(bottom>=0) {
                                path1 = [NSIndexPath indexPathForRow:bottom  inSection:0];
                               [self->_messageTable insertRowsAtIndexPaths:@[path1]
                                                    withRowAnimation:UITableViewRowAnimationFade];
                           }
                           [self->_messageTable endUpdates];
                            if(completion) completion(result);
                           
                           [self scrollToBottom];
                           
                           
                       });
            
          
        
    }
	else {
		DDLogVerbose(@"failed to add message");
    }
    }];
	
	// make sure its in active
	if(_firstmsg==YES)
	{
        [[DataLayer sharedInstance] addActiveBuddies:to forAccount:_accountNo withCompletion:nil];
        _firstmsg=NO;
	}

}

-(void) presentMucInvite:(NSNotification *)notification
{
     xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountNo];
    NSDictionary *userDic = notification.userInfo;
    NSString *from = [userDic objectForKey:@"from"];
    dispatch_async(dispatch_get_main_queue(), ^{
          NSString* messageString = [NSString  stringWithFormat:NSLocalizedString(@"You have been invited to a conversation %@?", nil), from ];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Group Chat Invite" message:messageString preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Join" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
              [xmppAccount joinRoom:from withNick:xmppAccount.username andPassword:nil];
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        
    });
}


-(void) handleNewMessage:(NSNotification *)notification
{
    DDLogVerbose(@"chat view got new message notice %@", notification.userInfo);
    
    if([[notification.userInfo objectForKey:@"accountNo"] isEqualToString:_accountNo]
       &&( ( [[notification.userInfo objectForKey:@"from"] isEqualToString:_contactName])
          || ([[notification.userInfo objectForKey:@"to"] isEqualToString:_contactName] ))
       )
    {
        [[DataLayer sharedInstance] messageTypeForMessage: [notification.userInfo objectForKey:@"messageText"] withCompletion:^(NSString *messageType) {
            
            dispatch_async(dispatch_get_main_queue(),
                           ^{
                               NSString *finalMessageType=messageType;
                               NSDictionary* userInfo;
                               if([[notification.userInfo objectForKey:kMessageType] isEqualToString:kMessageTypeStatus])
                               {
                                   finalMessageType =kMessageTypeStatus;
                               }
                           
                               if([[notification.userInfo objectForKey:@"to"] isEqualToString:_contactName])
                               {
                                   NSString *timeString;
                                   if(![notification.userInfo objectForKey:@"delayTimeStamp"]) {
                                       timeString=[self currentGMTTime];
                                   }
                                   else  {
                                       NSObject *obj =[notification.userInfo objectForKey:@"delayTimeStamp"];
                                       if([obj isKindOfClass:[NSDate class]])
                                       {
                                           timeString =[self.sourceDateFormat stringFromDate:(NSDate *)obj];
                                       } else  {
                                           timeString= [notification.userInfo objectForKey:@"delayTimeStamp"];
                                       }
                                   }
                                   
                                   userInfo = @{@"af": [notification.userInfo objectForKey:@"actuallyfrom"],
                                                @"message": [notification.userInfo objectForKey:@"messageText"],
                                                @"messageid": [notification.userInfo objectForKey:@"messageid"],
                                                 @"encrypted": [notification.userInfo objectForKey:@"encrypted"],
                                                @"thetime": timeString,
                                                @"delivered":@YES,
                                                kMessageType:finalMessageType
                                                };
                                   
                               } else  {
                                   userInfo = @{@"af": [notification.userInfo objectForKey:@"actuallyfrom"],
                                                @"message": [notification.userInfo objectForKey:@"messageText"],
                                                @"messageid": [notification.userInfo objectForKey:@"messageid"],
                                                @"encrypted": [notification.userInfo objectForKey:@"encrypted"],
                                                @"thetime": [self currentGMTTime],
                                                kMessageType:finalMessageType
                                                };
                               }
                               
                               
                               if(!self.messageList) self.messageList=[[NSMutableArray alloc] init];
                               [self.messageList addObject:[userInfo mutableCopy]];
                               
                               [_messageTable beginUpdates];
                               NSIndexPath *path1;
                               NSInteger bottom =  self.messageList.count-1;
                               if(bottom>=0) {
                                   
                                   path1 = [NSIndexPath indexPathForRow:bottom  inSection:0];
                                   [_messageTable insertRowsAtIndexPaths:@[path1]
                                                        withRowAnimation:UITableViewRowAnimationBottom];
                                   
                               } 
                               [_messageTable endUpdates];
                               
                               [self scrollToBottom];
                               
                               //mark as read
                               // [[DataLayer sharedInstance] markAsReadBuddy:_contactName forAccount:_accountNo];
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
                       for(NSMutableDictionary *rowDic in self.messageList)
                       {
                           if([[rowDic objectForKey:@"messageid"] isEqualToString:messageId]) {
                               [rowDic setObject:[NSNumber numberWithBool:delivered] forKey:@"delivered"];
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
                       for(NSMutableDictionary *rowDic in self.messageList)
                       {
                           if([[rowDic objectForKey:@"messageid"] isEqualToString:messageId]) {
                               [rowDic setObject:[NSNumber numberWithBool:received] forKey:@"received"];
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


-(void) refreshMessage:(NSNotification *)notification
{
    NSDictionary *dic =notification.userInfo;
    [self setMessageId:[dic objectForKey:kMessageId]  received:YES];
}


-(void) scrollToBottom
{
    if(self.messageList.count==0) return; 
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger bottom = [self.messageTable numberOfRowsInSection:0];
        if(bottom>0)
        {
            NSIndexPath *path1 = [NSIndexPath indexPathForRow:bottom-1  inSection:0];
            if(![self.messageTable.indexPathsForVisibleRows containsObject:path1])
            {
                [self.messageTable scrollToRowAtIndexPath:path1 atScrollPosition:UITableViewScrollPositionBottom animated:NO];
            }
        }
    });
}
#pragma mark date time

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

-(NSString*) currentGMTTime
{
    NSDate* sourceDate =[NSDate date];
    
//    NSTimeZone* sourceTimeZone = [NSTimeZone systemTimeZone];
//    NSTimeZone* destinationTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
//    NSInteger sourceGMTOffset = [sourceTimeZone secondsFromGMTForDate:sourceDate];
//    NSInteger destinationGMTOffset = [destinationTimeZone secondsFromGMTForDate:sourceDate];
//    NSTimeInterval interval = destinationGMTOffset - sourceGMTOffset;
//    NSDate* destinationDate = [[NSDate alloc] initWithTimeInterval:interval sinceDate:sourceDate];
//
    return [self.sourceDateFormat stringFromDate:sourceDate];
}

-(NSString*) formattedDateWithSource:(NSObject *) sourceDateString andPriorDate:(NSObject *) priorDateString
{
    NSString* dateString;
    if(sourceDateString!=nil)
    {
        NSDate* sourceDate;
        if([sourceDateString isKindOfClass:[NSDate class]]){
            sourceDate=(NSDate *)sourceDateString;
        } else  {
            sourceDate= [self.sourceDateFormat dateFromString: (NSString *)sourceDateString];
        }
        
        NSInteger msgday =[self.gregorian components:NSCalendarUnitDay fromDate:sourceDate].day;
        NSInteger msgmonth=[self.gregorian components:NSCalendarUnitMonth fromDate:sourceDate].month;
        NSInteger msgyear =[self.gregorian components:NSCalendarUnitYear fromDate:sourceDate].year;
        
        NSDate* priorDate;
        if([priorDateString isKindOfClass:[NSDate class]]){
            priorDate=(NSDate *)priorDateString;
        } else  {
            priorDate= [self.sourceDateFormat dateFromString: (NSString *)priorDateString];
        }
        
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

-(NSString*) formattedTimeStampWithSource:(NSObject *) sourceDateString
{
    NSString* dateString;
    if(sourceDateString!=nil)
    {
        NSDate* sourceDate;
        if([sourceDateString isKindOfClass:[NSDate class]]){
            sourceDate=(NSDate *)sourceDateString;
        } else  {
            sourceDate= [self.sourceDateFormat dateFromString: (NSString *)sourceDateString];
        }
        
        [self.destinationDateFormat setDateStyle:NSDateFormatterNoStyle];
        [self.destinationDateFormat setTimeStyle:NSDateFormatterShortStyle];
        
        dateString = [self.destinationDateFormat stringFromDate:sourceDate];
    }
    
    return dateString;
}



-(void) retry:(id) sender
{
    NSInteger historyId = ((UIButton*) sender).tag;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Retry sending message?" message:@"This message failed to send." preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Retry" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSArray *messageArray =[[DataLayer sharedInstance] messageForHistoryID:historyId];
        if([messageArray count]>0) {
            NSDictionary *dic= [messageArray objectAtIndex:0];
            [self sendMessage:[dic objectForKey:@"message"] andMessageID:[dic objectForKey:@"messageid"]];
            [self setMessageId:[dic objectForKey:@"messageid"] delivered:YES]; // for the UI, db will be set in the notification
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
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

    NSDictionary* row;
    if(indexPath.row<self.messageList.count) {
    row= [self.messageList objectAtIndex:indexPath.row];
    }
    
    NSString *from =[row objectForKey:@"af"];
    
    //intended to correct for bad data. Can be removed later probably.
    if([from isEqualToString:@"(null)"])
    {
        from=[row objectForKey:@"message_from"];;
    }
      NSString *messageType =[row objectForKey:kMessageType];
    
    if([messageType isEqualToString:kMessageTypeStatus])
    {
        cell=[tableView dequeueReusableCellWithIdentifier:@"StatusCell"];
        cell.messageBody.text =[row objectForKey:@"message"];
        cell.link=nil;
        return cell;
    }
    
    if(_isMUC)
    {
        if([from isEqualToString:_jid])
        {
            if([messageType isEqualToString:kMessageTypeUrl])
            {
                cell=[tableView dequeueReusableCellWithIdentifier:@"linkOutCell"];
            } else  {
                cell=[tableView dequeueReusableCellWithIdentifier:@"textOutCell"];
            }
        }
        else
        {
            if([messageType isEqualToString:kMessageTypeUrl])
            {
                cell=[tableView dequeueReusableCellWithIdentifier:@"linkInCell"];
            } else  {
                cell=[tableView dequeueReusableCellWithIdentifier:@"textInCell"];
            }
        }
    } else  {
        if([from isEqualToString:self.contactName])
        {
            if([messageType isEqualToString:kMessageTypeUrl])
            {
                cell=[tableView dequeueReusableCellWithIdentifier:@"linkInCell"];
            }  else  {
                cell=[tableView dequeueReusableCellWithIdentifier:@"textInCell"];
            }
        }
        else
        {
            if([messageType isEqualToString:kMessageTypeUrl])
            {
                cell=[tableView dequeueReusableCellWithIdentifier:@"linkOutCell"];
            } else  {
                cell=[tableView dequeueReusableCellWithIdentifier:@"textOutCell"];
            }
        }
        
        NSNumber *received = [row objectForKey:@"message"];
        if(received){
           
        }
    }

    NSDictionary *messageRow;
    if(indexPath.row<self.messageList.count) {
        messageRow = [self.messageList objectAtIndex:indexPath.row];
    }
    NSString *messageString =[messageRow objectForKey:@"message"];
   
    if([messageType isEqualToString:kMessageTypeImage])
    {
        MLChatImageCell* imageCell;
        if([from isEqualToString:self.contactName])
        {
            imageCell= (MLChatImageCell *) [tableView dequeueReusableCellWithIdentifier:@"imageInCell"];
            imageCell.outBound=NO;
        }
        else  {
            imageCell= (MLChatImageCell *) [tableView dequeueReusableCellWithIdentifier:@"imageOutCell"];
            imageCell.outBound=YES;
        }
        
        
        if(![imageCell.link isEqualToString:messageString]){
            imageCell.link = messageString;
            imageCell.thumbnailImage.image=nil;
            imageCell.loading=NO;
            [imageCell loadImageWithCompletion:^{}];
        }
        cell=imageCell;
        
    }
    else {
        
      if([messageType isEqualToString:kMessageTypeUrl])
      {
          MLLinkCell *toreturn;
          if([from isEqualToString:self.contactName]) {
              toreturn=(MLLinkCell *)[tableView dequeueReusableCellWithIdentifier:@"linkInCell"];
          }
          else  {
              toreturn=(MLLinkCell *)[tableView dequeueReusableCellWithIdentifier:@"linkOutCell"];
          }
          
         NSString * cleanLink=[[row objectForKey:@"message"]  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
          NSArray *parts = [cleanLink componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
          cell.link = parts[0];
          
          toreturn.messageBody.text =cell.link;
          toreturn.link=cell.link;
          
          if([(NSString *)[row objectForKey:@"previewImage"] length]>0
             || [(NSString *)[row objectForKey:@"previewText"] length]>0)
          {
              toreturn.imageUrl = [row objectForKey:@"previewImage"];
              toreturn.messageTitle.text = [row objectForKey:@"previewText"];
              [toreturn loadImageWithCompletion:^{
                  
              }];
          }  else {
              [toreturn loadPreviewWithCompletion:^{
                  if(toreturn.messageTitle.text.length==0) toreturn.messageTitle.text=@" "; // prevent repeated calls
                  [[DataLayer sharedInstance] setMessageId:[row objectForKey:@"messageid"] previewText:toreturn.messageTitle.text  andPreviewImage:toreturn.imageUrl];
              }];
          }
          cell=toreturn;
          
      } else {
        NSString* lowerCase= [[row objectForKey:@"message"] lowercaseString];
        NSRange pos = [lowerCase rangeOfString:@"https://"];
        if(pos.location==NSNotFound) {
            pos=[lowerCase rangeOfString:@"http://"];
        }
        
        NSRange pos2;
        if(pos.location!=NSNotFound)
        {
            NSString* urlString =[[row objectForKey:@"message"] substringFromIndex:pos.location];
            pos2= [urlString rangeOfString:@" "];
            if(pos2.location==NSNotFound) {
                pos2= [urlString rangeOfString:@">"];
            }
            
            if(pos2.location!=NSNotFound) {
                urlString=[urlString substringToIndex:pos2.location];
            }
            NSArray *parts = [urlString componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            cell.link = parts[0];
            
            if(cell.link) {
                
                NSDictionary *underlineAttribute = @{NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)};
                NSAttributedString* underlined = [[NSAttributedString alloc] initWithString:cell.link attributes:underlineAttribute];
                NSMutableAttributedString* stitchedString  = [[NSMutableAttributedString alloc] init];
                [stitchedString appendAttributedString:
                 [[NSAttributedString alloc] initWithString:[[row objectForKey:@"message"] substringToIndex:pos.location] attributes:nil]];
                [stitchedString appendAttributedString:underlined];
                if(pos2.location!=NSNotFound)
                {
                    NSString* remainder = [[row objectForKey:@"message"] substringFromIndex:pos.location+[underlined length]];
                    [stitchedString appendAttributedString:[[NSAttributedString alloc] initWithString:remainder attributes:nil]];
                }
                cell.messageBody.attributedText=stitchedString;
            }
        }
        else
        {
            cell.messageBody.text =[row objectForKey:@"message"];
            cell.link=nil;
        }
          
      }
        
    }
    
    if(_isMUC)
    {
        cell.name.hidden=NO;
        cell.name.text=from;
    } else  {
        cell.name.text=@"";
        cell.name.hidden=YES;
    }

    if([row objectForKey:@"delivered"]){
        if([[row objectForKey:@"delivered"] boolValue]!=YES)
        {
            cell.deliveryFailed=YES;
        }
    }
    
    NSNumber *received = [row objectForKey:kReceived];
    if(received.boolValue==YES) {
        NSDictionary *prior =nil;
        if(indexPath.row>0)
        {
            prior = [self.messageList objectAtIndex:indexPath.row-1];
        }
        if(indexPath.row==self.messageList.count-1 || ![[prior objectForKey:@"af"] isEqualToString:self.jid]) {
            cell.messageStatus.hidden=NO;
        } else  {
            cell.messageStatus.hidden=YES;
        }
    }
    else  {
        cell.messageStatus.hidden=YES;
    }

    cell.messageHistoryId=[row objectForKey:@"message_history_id"];
    BOOL newSender=NO;
    NSString *priorDate;
    if(indexPath.row>0)
    {
        NSDictionary *priorRow=[self.messageList objectAtIndex:indexPath.row-1];
        priorDate =[priorRow objectForKey:@"thetime"];
        NSString *priorSender =[priorRow objectForKey:@"af"];
        
        //intended to correct for bad data. Can be removed later probably.
        if([priorSender isEqualToString:@"(null)"])
        {
            priorSender=[priorRow objectForKey:@"message_from"];;
        }
        if(![priorSender isEqualToString:from])
        {
            newSender=YES;
        }
    }
    
    cell.date.text= [self formattedTimeStampWithSource:[row objectForKey:@"thetime"]];
    cell.selectionStyle=UITableViewCellSelectionStyleNone;
    
    cell.dividerDate.text = [self formattedDateWithSource:[row objectForKey:@"thetime"] andPriorDate:priorDate];
    
    if([[row objectForKey:@"encrypted"] boolValue])
    {
        cell.lockImage.hidden=NO;
    } else  {
         cell.lockImage.hidden=YES;
    }
    
    if([from isEqualToString:_jid])
    {
        cell.outBound=YES;
    }
    else  {
        cell.outBound=NO;
    }
    
    cell.parent=self; 
    
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
        NSDictionary* message= [self.messageList objectAtIndex:indexPath.row];
        
        DDLogVerbose(@"%@", message);
        
        if([message objectForKey:@"message_history_id"])
        {
            [[DataLayer sharedInstance] deleteMessageHistory:[NSString stringWithFormat:@"%@",[message objectForKey:@"message_history_id"]]];
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


//-(BOOL) canBecomeFirstResponder
//{
//    return YES;
//}
//
//-(UIView *) inputAccessoryView
//{
//    return self.inputContainerView;
//}


# pragma mark - Textview delegate functions

-(void) updateInputViewSize
{
    
    if(self.chatInput.intrinsicContentSize.height>43) {
        self.inputContainerHeight.constant= self.chatInput.intrinsicContentSize.height+16+10;
          self.chatInput.contentInset = UIEdgeInsetsMake(5, 0, 5, 0);
    } else
    {
        self.inputContainerHeight.constant=43.0f;
        self.chatInput.contentInset = UIEdgeInsetsMake(5, 0, 5, 0);
    }
    [self.chatInput setScrollEnabled:NO];
    [self.inputContainerView layoutIfNeeded];
    [self.chatInput setScrollEnabled:YES];
    [self.chatInput scrollRangeToVisible:NSMakeRange(0, 0)];
}

- (void)textViewDidBeginEditing:(UITextView *)textView
{
    [self scrollToBottom];
}


- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    BOOL shouldinsert=YES;
    
    if(self.hardwareKeyboardPresent &&  [text isEqualToString:@"\n"])
    {
        [self resignTextView];
        shouldinsert=NO;
        [self updateInputViewSize];
    }
    
    return shouldinsert; 
}

- (void)textViewDidChange:(UITextView *)textView
{
     [self updateInputViewSize];
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

-(void) keyboardDidHide: (NSNotification *)notif
{
	DDLogVerbose(@"kbd did hide ");
}

-(void) keyboardWillHide:(NSNotification *) notification
{
    if(self.blockAnimations) return;
    
    NSTimeInterval animationDuration =[[[notification userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
	[UIView animateWithDuration:animationDuration
                     animations:^{
                         self.inputContainerBottom.constant=0; 
                         if([self.messageList count]>0)
                         {
                             [self scrollToBottom];
                         }
                         
                     } completion:^(BOOL finished) {
                         
                         
                     }
     ];
    
    _keyboardVisible=NO;
	DDLogVerbose(@"kbd will hide scroll: %f", oldFrame.size.height);
}

-(void) keyboardDidShow:(NSNotification *) notification
{
    if(self.blockAnimations) return;
    CGRect keyboardframe =[[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGSize keyboardSize = keyboardframe.size;
    self.inputContainerBottom.constant= keyboardSize.height-self.tabBarController.tabBar.frame.size.height;
    [self scrollToBottom];
    
}

-(void) keyboardWillShow:(NSNotification *) notification
{
    CGRect keyboardFrame = [[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    keyboardFrame = [self.view convertRect:keyboardFrame fromView:nil]; // convert orientation
    self.hardwareKeyboardPresent = NO;
    if ((keyboardFrame.size.height ) < 100) {
        self.hardwareKeyboardPresent = YES;
    }
   
    if(self.blockAnimations) return;
//    CGRect keyboardframe =[[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
//    CGSize keyboardSize = keyboardframe.size;
//
//    NSTimeInterval animationDuration =[[[notification userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
//    [UIView animateWithDuration:animationDuration
//                     animations:^{
//                         self.inputContainerBottom.constant= keyboardSize.height-self.tabBarController.tabBar.frame.size.height;
//
//                     } completion:^(BOOL finished) {
//
//                         [self scrollToBottom];
//                     }
//     ];
//
}




@end
