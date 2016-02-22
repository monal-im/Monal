//
//  chat.m
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "chatViewController.h"
#import "MLConstants.h"
#import "MonalAppDelegate.h"
@import QuartzCore;
@import MobileCoreServices;

static const int ddLogLevel = LOG_LEVEL_ERROR;

@interface chatViewController()

@property (nonatomic, strong)  NSDateFormatter* destinationDateFormat;
@property (nonatomic, strong)  NSDateFormatter* sourceDateFormat;
@property (nonatomic, strong)  NSCalendar *gregorian;
@property (nonatomic, assign) NSInteger thisyear;
@property (nonatomic, assign) NSInteger thismonth;
@property (nonatomic, assign) NSInteger thisday;



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
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    [nc addObserver:self selector:@selector(handleSendFailedMessage:) name:kMonalSendFailedMessageNotice object:nil];
    [nc addObserver:self selector:@selector(handleSentMessage:) name:kMonalSentMessageNotice object:nil];
    
    
    [nc addObserver:self selector:@selector(dismissKeyboard:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(handleForeGround) name:UIApplicationWillEnterForegroundNotification object:nil];
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
    
    self.topIcon.layer.cornerRadius= self.topIcon.frame.size.height/2;
    self.topIcon.clipsToBounds=YES;

    
}

-(void) handleForeGround {
    [self refreshData];
    [self refreshCounter];
}


-(void)viewWillAppear:(BOOL)animated
{
    
    [super viewWillAppear:animated];
    
    [MLNotificationManager sharedInstance].currentAccountNo=self.accountNo;
    [MLNotificationManager sharedInstance].currentContact=self.contactName;
    
 
    if(![_contactFullName isEqualToString:@"(null)"] && [[_contactFullName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]>0)
    {
        _topName.text=_contactFullName;
    }
    else {
        _topName.text=_contactName;
    }
    
    if(_day) {
        self.title=  [NSString stringWithFormat:@"%@(%@)", _topName.text, _day];
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [containerView removeFromSuperview];
        [_topIcon removeFromSuperview];
    }
    else
    {
        _topIcon.image=[[MLImageManager sharedInstance] getIconForContact:_contactName andAccount:_accountNo];
        
    }
    self.navigationItem.titleView=self.topBarView;
    
    [self handleForeGround];
    
    
    xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountNo];
    if(xmppAccount.supportsMam0) {
        
        if(_messagelist.count==0)
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

- (BOOL)shouldAutorotate
{
   	[self.chatInput resignFirstResponder];
    return YES;
}

-(void) willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
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
    //coming in  from background
    if(!_day) {
        [[DataLayer sharedInstance] markAsReadBuddy:self.contactName forAccount:self.accountNo];
        
        MonalAppDelegate* appDelegate= (MonalAppDelegate*) [UIApplication sharedApplication].delegate;
        [appDelegate updateUnread];
    }
    
}

-(void) refreshData
{
    if(!_day) {
        _messagelist =[[DataLayer sharedInstance] messageHistory:_contactName forAccount: _accountNo];
        [[DataLayer sharedInstance] countUserUnreadMessages:_contactName forAccount: _accountNo withCompletion:^(NSNumber *unread) {
            if([unread integerValue]==0) _firstmsg=YES;
            
        }];
        _isMUC=[[DataLayer sharedInstance] isBuddyMuc:_contactName forAccount: _accountNo];
        
    }
    else
    {
        _messagelist =[[[DataLayer sharedInstance] messageHistoryDate:_contactName forAccount: _accountNo forDate:_day] mutableCopy];
        
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
    NSUInteger r = arc4random_uniform(NSIntegerMax);
    NSString *newMessageID =messageID;
    if(!newMessageID) {
        newMessageID=[NSString stringWithFormat:@"Monal%lu", (unsigned long)r];
    }
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
        [self.chatInput resignFirstResponder];//apply autocorrect
        [self.chatInput becomeFirstResponder];
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

#pragma mark -image picker

-(IBAction)attach:(id)sender
{
    xmpp* account=[[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountNo];
    if(!account.supportsHTTPUpload)
    {
        
        UIAlertView *addError = [[UIAlertView alloc]
                                 initWithTitle:@"Error"
                                 message:@"This server does not appear to support HTTP file uploads (XEP-0363). Please ask the administrator to enable it."
                                 delegate:nil cancelButtonTitle:@"Close"
                                 otherButtonTitles: nil] ;
        [addError show];
        
        return;
    }
    
    //TODO ask again for camera or photos
    UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
    imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;//or camera
    imagePicker.delegate =self;
    [self presentViewController:imagePicker animated:YES completion:nil];
    
    
}


- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary<NSString *,
                               id> *)info
{
    [self dismissViewControllerAnimated:YES completion:nil];

    NSString *mediaType = info[UIImagePickerControllerMediaType];
    if([mediaType isEqualToString:(NSString *)kUTTypeImage]) {
        UIImage *selectedImage= info[UIImagePickerControllerEditedImage];
        if(!selectedImage) selectedImage= info[UIImagePickerControllerOriginalImage];
        NSData *pngData=  UIImageJPEGRepresentation(selectedImage, 0.5f);
        if(pngData)
        {
            [UIApplication sharedApplication].networkActivityIndicatorVisible=YES;
            
            [[MLXMPPManager sharedInstance]  httpUploadPngData:pngData toContact:self.contactName onAccount:self.accountNo withCompletionHandler:^(NSString *url, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [UIApplication sharedApplication].networkActivityIndicatorVisible=NO;
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
    
	[[DataLayer sharedInstance] addMessageHistoryFrom:self.jid to:to forAccount:_accountNo withMessage:message actuallyFrom:self.jid withId:messageId withCompletion:^(BOOL result) {
		DDLogVerbose(@"added message");
        
        if(result) {
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           NSDictionary* userInfo = @{@"af": self.jid,
                                                      @"message": message ,
                                                      @"thetime": [self currentGMTTime],
                                                      @"delivered":@YES,
                                                             kMessageId: messageId
                                                             };
                           [_messagelist addObject:[userInfo mutableCopy]];
                           
                           NSIndexPath *path1;
                           [_messageTable beginUpdates];
                           NSInteger bottom = [_messagelist count]-1;
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
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           NSDictionary* userInfo;
                           if([[notification.userInfo objectForKey:@"to"] isEqualToString:_contactName])
                           {
                               userInfo = @{@"af": [notification.userInfo objectForKey:@"actuallyfrom"],
                                            @"message": [notification.userInfo objectForKey:@"messageText"],
                                            @"thetime": [self currentGMTTime],   @"delivered":@YES};
                               
                           } else  {
                               userInfo = @{@"af": [notification.userInfo objectForKey:@"actuallyfrom"],
                                            @"message": [notification.userInfo objectForKey:@"messageText"],
                                            @"thetime": [self currentGMTTime]
                                            };
                           }
                           
                           [_messagelist addObject:userInfo];
                           
                           [_messageTable beginUpdates];
                           NSIndexPath *path1;
                           NSInteger bottom =  _messagelist.count-1; 
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
    }
}

-(void) setMessageId:(NSString *) messageId delivered:(BOOL) delivered
{
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       int row=0;
                       [_messageTable beginUpdates];
                       for(NSMutableDictionary *rowDic in _messagelist)
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
-(void) popContacts
{
    DDLogVerbose(@"pop out contacts");
    
    //    UITableViewController* tbv = [UITableViewController alloc];
    //    tbv.tableView=contactList;
    //    popOverController = [[UIPopoverController alloc] initWithContentViewController:tbv];
    //
    //    popOverController.popoverContentSize = CGSizeMake(320, 480);
    //    [popOverController presentPopoverFromBarButtonItem:contactsButton permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    //
    //
    //
}


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
                             initWithCalendarIdentifier:NSGregorianCalendar];
    
    NSDate* now =[NSDate date];
    self.thisday =[self.gregorian components:NSDayCalendarUnit fromDate:now].day;
    self.thismonth =[self.gregorian components:NSMonthCalendarUnit fromDate:now].month;
    self.thisyear =[self.gregorian components:NSYearCalendarUnit fromDate:now].year;

    
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
        
        NSInteger msgday =[self.gregorian components:NSDayCalendarUnit fromDate:destinationDate].day;
        NSInteger msgmonth=[self.gregorian components:NSMonthCalendarUnit fromDate:destinationDate].month;
        NSInteger msgyear =[self.gregorian components:NSYearCalendarUnit fromDate:destinationDate].year;
        
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
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"8.0"))
    {
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
    else{
    
    }
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
            toReturn=[_messagelist count];
            break;
        }
        default:
            break;
    }
    
    return toReturn;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    MLChatCell* cell;
    if(indexPath.row <0 || indexPath.row>=[_messagelist count])
    {
        cell =[[MLChatCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ChatCell"  Muc:_isMUC andParent:self];
        return cell;
    }
    
    NSDictionary* row= [_messagelist objectAtIndex:indexPath.row];
    
    if([[row objectForKey:@"af"] isEqualToString:_jid])
    {
        cell=[tableView dequeueReusableCellWithIdentifier:@"ChatCellOut"];
    }
    else
    {
        cell=[tableView dequeueReusableCellWithIdentifier:@"ChatCellIn"];
    }
    
    if(!cell)
    {
        cell =[[MLChatCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ChatCell"  Muc:_isMUC andParent:self];
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
    
    NSString* lowerCase= [[row objectForKey:@"message"] lowercaseString];
    NSRange pos = [lowerCase rangeOfString:@"http://"];
    if(pos.location==NSNotFound) {
        pos=[lowerCase rangeOfString:@"https://"];
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
       
        
        cell.link=urlString;
    }
    else
    {
        cell.link=nil;
    }
    
    
    if(pos.location!=NSNotFound)
    {
        NSDictionary *underlineAttribute = @{NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)};
        NSAttributedString* underlined = [[NSAttributedString alloc] initWithString:cell.link
                                                                         attributes:underlineAttribute];
        
        
        if ([underlined length]==[[row objectForKey:@"message"] length])
        {
            cell.textLabel.attributedText=underlined;
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
            cell.textLabel.attributedText=stitchedString;
        }
        
    }
    else
    {
        cell.textLabel.text =[row objectForKey:@"message"];
    }
    
    
    
    cell.selectionStyle=UITableViewCellSelectionStyleNone;
    
    if([[row objectForKey:@"af"] isEqualToString:_jid])
    {
        cell.outBound=YES;
    }
    
    return cell;
}

#pragma mark - tableview delegate
-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self.chatInput resignFirstResponder];
    
    MLChatCell* cell = (MLChatCell*)[tableView cellForRowAtIndexPath:indexPath];
    if(cell.link)
    {
        [cell openlink:self];
    }
}

#pragma mark tableview datasource
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if(indexPath.row>=[_messagelist count])  {
        return 0;
    }
    NSDictionary* row=[_messagelist objectAtIndex:indexPath.row];
    CGFloat height= [MLChatCell heightForText:[row objectForKey:@"message"] inWidth:tableView.frame.size.width-20];
    height+=kNameLabelHeight;
    
    return height;
    
}

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
        NSDictionary* message= [_messagelist objectAtIndex:indexPath.row];
        
        DDLogVerbose(@"%@", message);
        
        if([message objectForKey:@"message_history_id"])
        {
            [[DataLayer sharedInstance] deleteMessageHistory:[NSString stringWithFormat:@"%@",[message objectForKey:@"message_history_id"]]];
        }
        else
        {
            return;
        }
        [_messagelist removeObjectAtIndex:indexPath.row];
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
    if(self.chatInput.intrinsicContentSize.height>40) {
        self.inputContainerHeight.constant= self.chatInput.intrinsicContentSize.height+18;
    } else
    {
         self.inputContainerHeight.constant=43.0f;
    }
    [self.inputContainerView layoutIfNeeded];
    self.chatInput.contentInset = UIEdgeInsetsMake(5, 0, 0, 0);
 
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
    }
    
    [self updateInputViewSize];
    return shouldinsert; 
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
                         if([_messagelist count]>0)
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
                         self.inputContainerBottom.constant= keyboardSize.height;
                         
                     } completion:^(BOOL finished) {
                         
                         [self scrollToBottom];
                     }
     ];
	
}




@end
