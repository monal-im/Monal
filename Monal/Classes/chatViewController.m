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

#import "MLConstants.h"
#import "MonalAppDelegate.h"
#import "MBProgressHUD.h"
#import "UIActionSheet+Blocks.h"
#import <DropBoxSDK/DropBoxSDK.h>

#import "MWPhotoBrowser.h"

@import QuartzCore;
@import MobileCoreServices;

static const int ddLogLevel = LOG_LEVEL_ERROR;

@interface chatViewController()<DBRestClientDelegate, MWPhotoBrowserDelegate>

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
    _contactFullName=[[DataLayer sharedInstance] fullName:[_contact objectForKey:@"buddy_name"] forAccount:[NSString stringWithFormat:@"%@",[_contact objectForKey:@"account_id"]]];
    if (!_contactFullName) _contactFullName=_contactName;
    
    self.accountNo=[NSString stringWithFormat:@"%d",[[_contact objectForKey:@"account_id"] integerValue]];
    self.hidesBottomBarWhenPushed=YES;
    
#warning this should be smarter...
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

-(id) initWithContact:(NSDictionary*) contact  andDay:(NSString* )day;
{
    self = [super init];
    if(self){
        _contact=contact;
        _day=day;
       
        [self setup];
    }
    
    return self;
}


#pragma mark view lifecycle

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
    
    self.hidesBottomBarWhenPushed=YES;
    
    self.chatInput.layer.borderColor=[UIColor lightGrayColor].CGColor;
    self.chatInput.layer.cornerRadius=3.0f;
    self.chatInput.layer.borderWidth=0.5f;
    self.chatInput.textContainerInset=UIEdgeInsetsMake(5, 0, 5, 0);
    
    
    self.inputContainerView.layer.borderColor=[UIColor lightGrayColor].CGColor;
    self.inputContainerView.layer.borderWidth=0.5f;
    
    if ([DBSession sharedSession].isLinked) {
        self.restClient = [[DBRestClient alloc] initWithSession:[DBSession sharedSession]];
        self.restClient.delegate = self;
    }
    
    self.messageTable.rowHeight = UITableViewAutomaticDimension;
    self.messageTable.estimatedRowHeight=75.0f; 
    
}

-(void) handleForeGround {
    [self refreshData];
}


-(void) handleBackground {
    [self refreshCounter];
}



-(void)viewWillAppear:(BOOL)animated
{
    
    [super viewWillAppear:animated];
    
    [MLNotificationManager sharedInstance].currentAccountNo=self.accountNo;
    [MLNotificationManager sharedInstance].currentContact=self.contactName;
    
 
    if(![_contactFullName isEqualToString:@"(null)"] && [[_contactFullName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]>0)
    {
         self.navigationItem.title=_contactFullName;
    }
    else {
         self.navigationItem.title=_contactName;
    }
    
   
    
    if(_day) {
        self.navigationItem.title=  [NSString stringWithFormat:@"%@(%@)", self.navigationItem.title, _day];
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [containerView removeFromSuperview];
       
    }

    [self handleForeGround];
    
    xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountNo];
    if(xmppAccount.supportsMam0) {
        
        if(self.messageList.count==0)
        {
            //fetch default
            NSDate *yesterday =[NSDate dateWithTimeInterval:-86400 sinceDate:[NSDate date]];
            [xmppAccount setMAMQueryFromStart: yesterday toDate:[NSDate date] andJid:self.contactName];
        }
        
    }

    UIEdgeInsets currentInset = self.messageTable.contentInset;
    self.messageTable.contentInset =UIEdgeInsetsMake(self.navigationController.navigationBar.frame.size.height+[UIApplication sharedApplication].statusBarFrame.size.height, currentInset.left, currentInset.bottom, currentInset.right);
    
}

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self scrollToBottom];
    [self refreshCounter];
 
}

-(void) viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [MLNotificationManager sharedInstance].currentAccountNo=nil;
    [MLNotificationManager sharedInstance].currentContact=nil;
    
    [self refreshCounter];

}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
    if(!_day) {
        self.messageList =[[DataLayer sharedInstance] messageHistory:_contactName forAccount: _accountNo];
        [[DataLayer sharedInstance] countUserUnreadMessages:_contactName forAccount: _accountNo withCompletion:^(NSNumber *unread) {
            if([unread integerValue]==0) _firstmsg=YES;
            
        }];
        _isMUC=[[DataLayer sharedInstance] isBuddyMuc:_contactName forAccount: _accountNo];
        
    }
    else
    {
        self.messageList =[[[DataLayer sharedInstance] messageHistoryDate:_contactName forAccount: _accountNo forDate:_day] mutableCopy];
        
    }
    [_messageTable reloadData];
}


#pragma mark textview
-(void) sendMessage:(NSString *) messageText
{
    [self sendMessage:messageText andMessageID:nil];
}

-(void) sendMessage:(NSString *) messageText andMessageID:(NSString *)messageID
{
    DDLogVerbose(@"Sending message");
    NSString *newMessageID =[[NSUUID UUID] UUIDString];
 
    [[MLXMPPManager sharedInstance] sendMessage:messageText toContact:_contactName fromAccount:_accountNo isMUC:_isMUC messageId:newMessageID
                          withCompletionHandler:nil];
    
    //dont readd it, use the exisitng
    if(!messageID) {
        [self addMessageto:_contactName withMessage:messageText andId:newMessageID];
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
    self.chatInput.text= link;
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
        [self presentViewController:imagePicker animated:YES completion:nil];
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
                    self.chatInput.text= url;
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
-(void) addMessageto:(NSString*)to withMessage:(NSString*) message andId:(NSString *) messageId
{
	if(!self.jid || !message)  {
        DDLogError(@" not ready to send messages");
        return;
    }
    
	[[DataLayer sharedInstance] addMessageHistoryFrom:self.jid to:to forAccount:_accountNo withMessage:message actuallyFrom:self.jid withId:messageId withCompletion:^(BOOL result, NSString *messageType) {
		DDLogVerbose(@"added message");
        
        if(result) {
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           NSDictionary* userInfo = @{@"af": self.jid,
                                                      @"message": message ,
                                                      @"thetime": [self currentGMTTime],
                                                      @"delivered":@YES,
                                                             kMessageId: messageId,
                                                      kMessageType:messageType
                                                             };
                           [self.messageList addObject:[userInfo mutableCopy]];
                           
                           NSIndexPath *path1;
                           [_messageTable beginUpdates];
                           NSInteger bottom = [self.messageList count]-1;
                           if(bottom>=0) {
                                path1 = [NSIndexPath indexPathForRow:bottom  inSection:0];
                               [_messageTable insertRowsAtIndexPaths:@[path1]
                                                    withRowAnimation:UITableViewRowAnimationBottom];
                           }
                           [_messageTable endUpdates];
                           
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

-(void) handleNewMessage:(NSNotification *)notification
{
    DDLogVerbose(@"chat view got new message notice %@", notification.userInfo);
    
    if([[notification.userInfo objectForKey:@"accountNo"] isEqualToString:_accountNo]
       &&( ( [[notification.userInfo objectForKey:@"from"] isEqualToString:_contactName]) || ([[notification.userInfo objectForKey:@"to"] isEqualToString:_contactName] ))
       )
    {
        [[DataLayer sharedInstance] messageTypeForMessage: [notification.userInfo objectForKey:@"messageText"] withCompletion:^(NSString *messageType) {
            
            dispatch_async(dispatch_get_main_queue(),
                           ^{
                               NSDictionary* userInfo;
                               if([[notification.userInfo objectForKey:@"to"] isEqualToString:_contactName])
                               {
                                   userInfo = @{@"af": [notification.userInfo objectForKey:@"actuallyfrom"],
                                                @"message": [notification.userInfo objectForKey:@"messageText"],
                                                @"thetime": [self currentGMTTime],   @"delivered":@YES,
                                                kMessageType:messageType
                                                };
                                   
                               } else  {
                                   userInfo = @{@"af": [notification.userInfo objectForKey:@"actuallyfrom"],
                                                @"message": [notification.userInfo objectForKey:@"messageText"],
                                                @"thetime": [self currentGMTTime], kMessageType:messageType
                                                };
                               }
                               
                               
                               [self.messageList addObject:userInfo];
                               
                               [_messageTable beginUpdates];
                               NSIndexPath *path1;
                               NSInteger bottom =  self.messageList.count-1;
                               if(bottom>0) {
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
                       int row=0;
                       [_messageTable beginUpdates];
                       for(NSMutableDictionary *rowDic in self.messageList)
                       {
                           if([[rowDic objectForKey:@"messageid"] isEqualToString:messageId]) {
                               [rowDic setObject:[NSNumber numberWithBool:delivered] forKey:@"delivered"];
                               NSIndexPath *indexPath =[NSIndexPath indexPathForRow:row inSection:0];
                                   [_messageTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                               break;
                           }
                           row++;
                       }
                       [_messageTable endUpdates];
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

#pragma mark MUC display elements

-(void) scrollToBottom
{
    NSInteger bottom = [self.messageTable numberOfRowsInSection:0];
    if(bottom>0)
    {
        NSIndexPath *path1 = [NSIndexPath indexPathForRow:bottom-1  inSection:0];
        if(![self.messageTable.indexPathsForVisibleRows containsObject:path1])
        {
            [self.messageTable scrollToRowAtIndexPath:path1 atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        }
    }
    
}
#pragma mark date time

-(void) setupDateObjects
{
    self.destinationDateFormat = [[NSDateFormatter alloc] init];
    [self.destinationDateFormat setLocale:[NSLocale currentLocale]];
    [self.destinationDateFormat setDoesRelativeDateFormatting:YES];
    
    self.sourceDateFormat = [[NSDateFormatter alloc] init];
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
    
    NSTimeZone* sourceTimeZone = [NSTimeZone systemTimeZone];
    NSTimeZone* destinationTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    NSInteger sourceGMTOffset = [sourceTimeZone secondsFromGMTForDate:sourceDate];
    NSInteger destinationGMTOffset = [destinationTimeZone secondsFromGMTForDate:sourceDate];
    NSTimeInterval interval = destinationGMTOffset - sourceGMTOffset;
    NSDate* destinationDate = [[NSDate alloc] initWithTimeInterval:interval sinceDate:sourceDate];
    
    return [self.sourceDateFormat stringFromDate:destinationDate];
}

-(NSString*) formattedDateWithSource:(NSString*) sourceDateString
{
    NSString* dateString;
    
    if(sourceDateString!=nil)
    {
        
        NSDate* sourceDate=[self.sourceDateFormat dateFromString:sourceDateString];
        
        NSTimeZone* sourceTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
        NSTimeZone* destinationTimeZone = [NSTimeZone systemTimeZone];
        NSInteger sourceGMTOffset = [sourceTimeZone secondsFromGMTForDate:sourceDate];
        NSInteger destinationGMTOffset = [destinationTimeZone secondsFromGMTForDate:sourceDate];
        NSTimeInterval interval = destinationGMTOffset - sourceGMTOffset;
        NSDate* destinationDate = [[NSDate alloc] initWithTimeInterval:interval sinceDate:sourceDate];
        
        NSInteger msgday =[self.gregorian components:NSCalendarUnitDay fromDate:destinationDate].day;
        NSInteger msgmonth=[self.gregorian components:NSCalendarUnitMonth fromDate:destinationDate].month;
        NSInteger msgyear =[self.gregorian components:NSCalendarUnitYear fromDate:destinationDate].year;
        
        if ((self.thisday!=msgday) || (self.thismonth!=msgmonth) || (self.thisyear!=msgyear))
        {
    
            //no more need for seconds
            [self.destinationDateFormat setTimeStyle:NSDateFormatterShortStyle];
            
            // note: if it isnt the same day we want to show the full  day
            [self.destinationDateFormat setDateStyle:NSDateFormatterMediumStyle];
            
            //cache date
           
        }
        else
        {
            //today just show time
            [self.destinationDateFormat setDateStyle:NSDateFormatterNoStyle];
            [self.destinationDateFormat setTimeStyle:NSDateFormatterMediumStyle];
        }
      
        dateString = [ self.destinationDateFormat stringFromDate:destinationDate];
    }
    
    return dateString;
}



-(void) retry:(id) sender
{
    NSInteger historyId = ((UIButton*) sender).tag;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Retry sending message?" message:@"It is possible this message may have failed to send." preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Retry" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSArray *messageArray =[[DataLayer sharedInstance] messageForHistoryID:historyId];
        if([messageArray count]>0) {
            NSDictionary *dic= [messageArray objectAtIndex:0];
            [self sendMessage:[dic objectForKey:@"message"] andMessageID:[dic objectForKey:@"messageid"]];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
    
}

#pragma mark tableview datasource

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

    NSDictionary* row= [self.messageList objectAtIndex:indexPath.row];
    
    if(_isMUC)
    {
        if([[row objectForKey:@"af"] isEqualToString:_jid])
        {
            cell=[tableView dequeueReusableCellWithIdentifier:@"textOutCell"];
        }
        else
        {
            cell=[tableView dequeueReusableCellWithIdentifier:@"textInCell"];
        }
    } else  {
        if([[row objectForKey:@"af"] isEqualToString:self.contactName])
        {
            cell=[tableView dequeueReusableCellWithIdentifier:@"textInCell"];
        }
        else
        {
            cell=[tableView dequeueReusableCellWithIdentifier:@"textOutCell"];
        }
    }

    
    NSDictionary *messageRow = [self.messageList objectAtIndex:indexPath.row];
    
    NSString *messageString =[messageRow objectForKey:@"message"];
    NSString *messageType =[messageRow objectForKey:kMessageType];
    
    if([messageType isEqualToString:kMessageTypeImage])
    {
        MLChatImageCell* imageCell;
      
        if([[row objectForKey:@"af"] isEqualToString:self.contactName])
        {
            imageCell= (MLChatImageCell *) [tableView dequeueReusableCellWithIdentifier:@"imageInCell"];
            imageCell.outBound=NO;
           
        }
        else  {
            imageCell= (MLChatImageCell *) [tableView dequeueReusableCellWithIdentifier:@"imageOutCell"];
            imageCell.outBound=YES;
        }
        
        imageCell.link = messageString;
        [imageCell loadImageWithcompletion:^{
            
            [self.messageTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            
        }];
        cell=imageCell;
        
    } else  {
    
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
            
            
            cell.link=[urlString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
            NSDictionary *underlineAttribute = @{NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)};
            NSAttributedString* underlined = [[NSAttributedString alloc] initWithString:cell.link
                                                                             attributes:underlineAttribute];
            
            
            if ([underlined length]==[[row objectForKey:@"message"] length])
            {
                cell.messageBody.attributedText=underlined;
            }
            else
            {
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
    
    if(_isMUC)
    {
        cell.showName=YES;
        cell.name.text=[row objectForKey:@"af"];
    }

    
    if([[row objectForKey:@"delivered"] boolValue]!=YES)
    {
        cell.deliveryFailed=YES;
    }
    
    cell.messageHistoryId=[row objectForKey:@"message_history_id"];
    cell.date.text= [self formattedDateWithSource:[row objectForKey:@"thetime"]];
    cell.selectionStyle=UITableViewCellSelectionStyleNone;
    
    if([[row objectForKey:@"af"] isEqualToString:_jid])
    {
        cell.outBound=YES;
    }
    
    cell.parent=self; 
    
    [cell updateCell];
    
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
            
            MWPhoto* photo=[MWPhoto photoWithImage:imageCell.thumbnailImage.image];
            // photo.caption=[row objectForKey:@"caption"];
            [self.photos addObject:photo];
            
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                MWPhotoBrowser *browser = [[MWPhotoBrowser alloc] initWithDelegate:self];
                
                browser.displayActionButton = YES; // Show action button to allow sharing, copying, etc (defaults to YES)
                browser.displayNavArrows = NO; // Whether to display left and right nav arrows on toolbar (defaults to NO)
                browser.displaySelectionButtons = NO; // Whether selection buttons are shown on each image (defaults to NO)
                browser.zoomPhotosToFill = YES; // Images that almost fill the screen will be initially zoomed to fill (defaults to YES)
                browser.alwaysShowControls = NO; // Allows to control whether the bars and controls are always visible or whether they fade away to show the photo full (defaults to NO)
                browser.enableGrid = YES; // Whether to allow the viewing of all the photo thumbnails on a grid (defaults to YES)
                browser.startOnGrid = NO; // Whether to start on the grid of thumbnails instead of the first photo (defaults to NO)
              
                UINavigationController *nav =[[UINavigationController alloc] initWithRootViewController:browser];
                
                
                [self presentViewController:nav animated:YES completion:nil];
                
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


# pragma mark Textview delegate functions

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
    
    if([text isEqualToString:@"\n"])
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
- (NSUInteger)numberOfPhotosInPhotoBrowser:(MWPhotoBrowser *)photoBrowser {
    return self.photos.count;
}

- (id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser photoAtIndex:(NSUInteger)index {
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

-(void) keyboardDidShow:(NSNotification *) note
{
    
    
}

-(void) keyboardWillShow:(NSNotification *) notification
{
    if(self.blockAnimations) return;
    CGRect keyboardframe =[[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGSize keyboardSize = keyboardframe.size;
    
    NSTimeInterval animationDuration =[[[notification userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:animationDuration
                     animations:^{
                         self.inputContainerBottom.constant= keyboardSize.height-self.tabBarController.tabBar.frame.size.height;
                         
                     } completion:^(BOOL finished) {
                         
                         [self scrollToBottom];
                     }
     ];
	
}




@end
