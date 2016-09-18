//
//  MLChatViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLChatViewController.h"
#import "MLConstants.h"
#import "DataLayer.h"
#import "DDLog.h"
#import "MLXMPPManager.h"
#import "MLChatViewCell.h"
#import "MLImageManager.h"
#import "MLPreviewObject.h"

#import <DropboxOSX/DropboxOSX.h>

#import "MLMainWindow.h"

@interface MLChatViewController () <DBRestClientDelegate>

@property (nonatomic, strong) NSMutableArray *messageList;

@property (nonatomic, strong)  NSDateFormatter* destinationDateFormat;
@property (nonatomic, strong)  NSDateFormatter* sourceDateFormat;
@property (nonatomic, strong)  NSCalendar *gregorian;
@property (nonatomic, assign) NSInteger thisyear;
@property (nonatomic, assign) NSInteger thismonth;
@property (nonatomic, assign) NSInteger thisday;


@property (nonatomic, strong) NSString *accountNo;
@property (nonatomic, strong) NSString *contactName;
@property (nonatomic, strong) NSString *jid;
@property (nonatomic, assign) BOOL isMUC;

@property (nonatomic, strong) QLPreviewPanel *QLPreview;
@property (nonatomic, strong) NSData *tmpPreviewImageData;

@property (nonatomic, strong) DBRestClient *restClient;

@end

@implementation MLChatViewController 

static const int ddLogLevel = LOG_LEVEL_VERBOSE;

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    [nc addObserver:self selector:@selector(handleSendFailedMessage:) name:kMonalSendFailedMessageNotice object:nil];
    [nc addObserver:self selector:@selector(handleSentMessage:) name:kMonalSentMessageNotice object:nil];
    [nc addObserver:self selector:@selector(refreshData) name:kMonalWindowVisible object:nil];
    
    [self setupDateObjects];
    
    self.progressIndicator.bezeled=NO;
    self.progressIndicator.controlSize=NSMiniControlSize;
    [self endProgressUpdate];
    
}

-(void) viewWillAppear
{
    [super viewWillAppear];
    if(! self.contactName) return;
    
    [self refreshData];
    [self updateWindowForContact:self.contactDic];
        
}


-(void) viewDidAppear
{
    [super viewDidAppear];
    if((self.view.window.occlusionState & NSWindowOcclusionStateVisible)) {
        [self markAsRead];
    }
    
    MLMainWindow *window =(MLMainWindow *)self.view.window.windowController;
    window.chatViewController= self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) refreshData
{
    self.messageList =[[DataLayer sharedInstance] messageHistory:self.contactName forAccount: self.accountNo];

    [self.chatTable reloadData];
    [self scrollToBottom];
}

-(void) showConversationForContact:(NSDictionary *) contact
{
    if([self.accountNo isEqualToString:[NSString stringWithFormat:@"%@",[contact objectForKey:kAccountID]]] && [self.contactName isEqualToString: [contact objectForKey:kContactName]])
    {
        return;
    }
    
    
//    [MLNotificationManager sharedInstance].currentAccountNo=self.accountNo;
//    [MLNotificationManager sharedInstance].currentContact=self.contactName;

    self.accountNo = [NSString stringWithFormat:@"%@",[contact objectForKey:kAccountID]];
    self.contactName = [contact objectForKey:kContactName];
    self.contactDic= contact;
    [self updateWindowForContact:contact];
    
#warning this should be smarter...
    NSArray* accountVals =[[DataLayer sharedInstance] accountVals:self.accountNo];
    if([accountVals count]>0)
    {
        self.jid=[NSString stringWithFormat:@"%@@%@",[[accountVals objectAtIndex:0] objectForKey:kUsername], [[accountVals objectAtIndex:0] objectForKey:kDomain]];
    }
        if((self.view.window.occlusionState & NSWindowOcclusionStateVisible)) {
        [self markAsRead];
    }
    [self refreshData];
    
    
    xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountNo];
    if(xmppAccount.supportsMam0) {
    
      if(self.messageList.count==0)
        {
            //fetch default
            NSDate *yesterday =[NSDate dateWithTimeInterval:-86400 sinceDate:[NSDate date]];
            [xmppAccount setMAMQueryFromStart: yesterday toDate:[NSDate date] andJid:self.contactName];
        }
 
    }
    
}


-(void) scrollToBottom
{
    NSInteger bottom = [self.chatTable numberOfRows];
    if(bottom>0)
    {
        [self.chatTable scrollRowToVisible:bottom-1];
    }
}

-(IBAction)emojiPicker:(id)sender {
    [[NSApplication sharedApplication] orderFrontCharacterPalette:nil];
}

-(void) updateWindowForContact:(NSDictionary *)contact
{
    MLMainWindow *window =(MLMainWindow *)self.view.window.windowController;
    [window updateCurrentContact:contact];
}


-(void) endProgressUpdate
{
    self.progressIndicator.doubleValue=0;
    self.progressIndicator.hidden=YES;
}

#pragma mark - Dropbox upload and delegate

- (void) uploadImageToDropBox:(NSData *) imageData {
    
    NSString *fileName = [NSString stringWithFormat:@"%@.png",[NSUUID UUID].UUIDString];
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
    self.progressIndicator.doubleValue=progress*100;
}

- (void)restClient:(DBRestClient*)restClient loadedSharableLink:(NSString*)link
           forFile:(NSString*)path{
    self.messageBox.string=link;
    [self endProgressUpdate];
}

- (void)restClient:(DBRestClient*)restClient loadSharableLinkFailedWithError:(NSError*)error{
   [self endProgressUpdate];
    DDLogVerbose(@"Failed to get Dropbox link with error: %@", error);
}

#pragma mark uploading attachments

-(void) showNoUploadAlert
{

    NSAlert *userAddAlert = [[NSAlert alloc] init];
    userAddAlert.messageText = @"Error";
    userAddAlert.informativeText =[NSString stringWithFormat:@"This server does not appear to support HTTP file uploads (XEP-0363). Please ask the administrator to enable it. You can also link to DropBox in settings and use that to share files."];
    userAddAlert.alertStyle=NSInformationalAlertStyle;
    [userAddAlert addButtonWithTitle:@"Close"];
    
    [userAddAlert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        [self dismissController:self];
    }];
    
}

-(void) uploadData:(NSData *) data
{
    
    xmpp* account=[[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountNo];
    if(!account.supportsHTTPUpload && !self.restClient)
    {
        [self showNoUploadAlert];
        
        return;
    }
    
    self.progressIndicator.doubleValue=0;
    self.progressIndicator.hidden=NO;
    if(self.restClient)
    {
        [self uploadImageToDropBox:data];
    }
    else {
        
        // start http upload XMPP
        self.progressIndicator.doubleValue=50;
        [[MLXMPPManager sharedInstance] httpUploadData:data withFilename:@"file" andType:@"file"                                                  toContact:self.contactName onAccount:self.accountNo withCompletionHandler:^(NSString *url, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self endProgressUpdate];
                if(url) {
                    self.messageBox.string= url;
                }
                else  {
                    NSAlert *userAddAlert = [[NSAlert alloc] init];
                    userAddAlert.messageText = @"There was an error uploading the file to the server";
                    userAddAlert.informativeText =[NSString stringWithFormat:@"%@", error.localizedDescription];
                    userAddAlert.alertStyle=NSInformationalAlertStyle;
                    [userAddAlert addButtonWithTitle:@"Close"];
                    
                    [userAddAlert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
                        [self dismissController:self];
                    }];
                }
            });
            
        }];
    }
}

-(void) uploadFile:(NSURL *) fileURL
{
    NSData *data =  [NSData dataWithContentsOfURL:fileURL];
    [self uploadData:data];
}



-(IBAction)attach:(id)sender
{
    
    if ([DBSession sharedSession].isLinked) {
        self.restClient = [[DBRestClient alloc] initWithSession:[DBSession sharedSession]];
        self.restClient.delegate = self;
    }
 
    xmpp* account=[[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountNo];
    if(!account.supportsHTTPUpload && !self.restClient)
    {
        [self showNoUploadAlert];
    }
    
    //select file
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel beginSheetModalForWindow:self.view.window completionHandler: ^(NSInteger result) {
        switch(result){
            case NSFileHandlingPanelOKButton:
            {
                [self uploadFile:openPanel.URL];
                break;
            }
            case NSFileHandlingPanelCancelButton:
            {
                break;
            }
        }
    }];

}

#pragma mark - notificaitons
-(void) handleNewMessage:(NSNotification *)notification
{
    DDLogVerbose(@"chat view got new message notice %@", notification.userInfo);
    
    NSNumber *shouldRefresh =[notification.userInfo objectForKey:@"shouldRefresh"];
    if (shouldRefresh.boolValue) {
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           [self refreshData];
                       });
        return;
    }
    
    
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
                           
                           [self.messageList addObject:userInfo];
                         
                           if((self.view.window.occlusionState & NSWindowOcclusionStateVisible)) {
                               [self refreshData];
                               [self markAsRead];
                           }
                       });
    }

    
}

-(void) handleSendFailedMessage:(NSNotification *)notification
{
    NSDictionary *dic =notification.userInfo;
    [self setMessageId:[dic objectForKey:kMessageId]  delivered:NO];
     [self endProgressUpdate];
}

-(void) handleSentMessage:(NSNotification *)notification
{
    NSDictionary *dic =notification.userInfo;
    [self setMessageId:[dic objectForKey:kMessageId]  delivered:YES];
    
    dispatch_async( dispatch_get_main_queue(), ^{
        self.progressIndicator.doubleValue=100;
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5f * NSEC_PER_SEC), dispatch_get_main_queue(),  ^{
           [self endProgressUpdate];
        });
        
    });
}

-(void) markAsRead
{
    //mark as read
    [[DataLayer sharedInstance] markAsReadBuddy:_contactName forAccount:_accountNo];
    
    [[DataLayer sharedInstance] countUnreadMessagesWithCompletion:^(NSNumber * result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if([result integerValue]>0) {
                [[[NSApplication sharedApplication] dockTile] setBadgeLabel:[NSString stringWithFormat:@"%@", result]];
            }
            else
            {
                [[[NSApplication sharedApplication] dockTile] setBadgeLabel:nil];
            }
        });
        
    }];
}

#pragma mark - sending

//always messages going out
-(void) addMessageto:(NSString*)to withMessage:(NSString*) message andId:(NSString *) messageId
{
    if(!self.jid || !message)  {
        DDLogError(@" not ready to send messages");
        return;
    }
    
    [[DataLayer sharedInstance] addMessageHistoryFrom:self.jid to:to forAccount:[NSString stringWithFormat:@"%@",self.accountNo] withMessage:message actuallyFrom:self.jid withId:messageId withCompletion:^(BOOL result, NSString *messageType) {
    if(result){
        DDLogVerbose(@"added message %@, %@ %@", message, messageId, [self currentGMTTime]);
        
        NSDictionary* userInfo = @{@"af": self.jid,
                                   @"message": message ,
                                   @"thetime": [self currentGMTTime],
                                   kDelivered:@YES,
                                   kMessageId: messageId,
                                   kMessageType: messageType
                                   };
        
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           
                           NSString *lastMessageId;
                           if(self.messageList.count>0) {
                               lastMessageId=[[self.messageList objectAtIndex:self.messageList.count-1] objectForKey:@"messageid"];
                           }
                           NSString *nextMessageId = [userInfo objectForKey:kMessageId];
                           if(![lastMessageId isEqualToString:nextMessageId]) {
                               [self.messageList addObject:[userInfo mutableCopy]];
                               [self.chatTable reloadData];
                           }
                           
                           [self scrollToBottom];
                           
                       });
        
    }
    else {
        DDLogVerbose(@"failed to add message");
    }
    }];
    
    [[DataLayer sharedInstance] isActiveBuddy:to forAccount:self.accountNo withCompletion:^(BOOL isActive) {
        if(!isActive) {
            [[DataLayer sharedInstance] addActiveBuddies:to forAccount:self.accountNo withCompletion:nil];

        }
    }];

}

-(void) setMessageId:(NSString *) messageId delivered:(BOOL) delivered
{
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       int row=0;
                       for(NSMutableDictionary *rowDic in self.messageList)
                       {
                           if([[rowDic objectForKey:@"messageid"] isEqualToString:messageId]) {
                               [rowDic setObject:[NSNumber numberWithBool:delivered] forKey:kDelivered];
                              
                               [self.chatTable beginUpdates];
                               NSIndexSet *indexSet =[[NSIndexSet alloc] initWithIndex:row] ;
                               NSIndexSet *columnIndexSet =[[NSIndexSet alloc] initWithIndex:0] ;
                               [self.chatTable reloadDataForRowIndexes:indexSet columnIndexes:columnIndexSet];
                               [self.chatTable endUpdates];
                               
                               break;
                           }
                           row++;
                       }
                   });
}

-(void) sendMessage:(NSString *) messageText andMessageID:(NSString *)messageID
{
    DDLogVerbose(@"Sending message %@", messageText);
    u_int32_t r = arc4random_uniform(30000000);
    NSString *newMessageID =messageID;
    if(!newMessageID) {
        newMessageID=[NSString stringWithFormat:@"Monal%d", r];
    }
    [self.progressIndicator incrementBy:25];
    [[MLXMPPManager sharedInstance] sendMessage:messageText toContact:self.contactName fromAccount:self.accountNo isMUC:self.isMUC messageId:newMessageID
     withCompletionHandler:^(BOOL success, NSString *messageId) {
         if(success)
         {
            dispatch_async( dispatch_get_main_queue(), ^{
              [self.progressIndicator incrementBy:25];
            });
         }
     }];
    
    //dont readd it, use the exisitng
    if(!messageID) {
        [self addMessageto:_contactName withMessage:messageText andId:newMessageID];
    }
    
    //mark as read
    
    //update badge
}


-(IBAction)sendText:(id)sender
{

    self.progressIndicator.doubleValue=0;
    self.progressIndicator.hidden=NO;
    
    [self.messageBox.textStorage enumerateAttribute:NSAttachmentAttributeName
                            inRange:NSMakeRange(0, self.messageBox.textStorage.length)
                            options:0
                         usingBlock:^(id value, NSRange range, BOOL *stop)
     {
         NSTextAttachment* attachment = (NSTextAttachment*)value;
         NSData* attachmentData = attachment.fileWrapper.regularFileContents;
         if(attachmentData)
         {
             [self uploadData:attachmentData];
         }
        
     }];
    
    __block NSMutableString *message= [self.messageBox.string mutableCopy];
    [message replaceOccurrencesOfString:@"\U0000fffc" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, message.length)];
    
    NSAttributedString *messageAttributedString = self.messageBox.attributedString;
   
 [messageAttributedString enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, messageAttributedString.length) options:0 usingBlock:^(id  _Nullable value, NSRange range, BOOL * _Nonnull stop) {
     if(value)
     {
         if(range.length == message.length)
         {
             message=[NSMutableString stringWithString:@""];
         } else  {
             [message appendString:@" "];
         }
         
         [message appendString:(NSString *)value];
     }
 }];
    
    
    if(message.length>0) {
        [self sendMessage:message andMessageID:nil];
    }
    self.messageBox.string=@"";
}


-(IBAction)deliveryFailedMessage:(id)sender
{
    NSAlert *userAddAlert = [[NSAlert alloc] init];
    userAddAlert.messageText=@"Message Failed to Send";
    userAddAlert.informativeText =[NSString stringWithFormat:@"This message may  have failed to send."];
    userAddAlert.alertStyle=NSWarningAlertStyle;
    [userAddAlert addButtonWithTitle:@"Close"];
    [userAddAlert addButtonWithTitle:@"Retry"];
    
     NSInteger historyId = ((NSButton*) sender).tag;
    
    [userAddAlert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode ==1001) { //retry
            
            NSArray *messageArray =[[DataLayer sharedInstance] messageForHistoryID:historyId];
            if([messageArray count]>0) {
                NSDictionary *dic= [messageArray objectAtIndex:0];
                [self sendMessage:[dic objectForKey:@"message"] andMessageID:[dic objectForKey:@"messageid"]];
            }
            
        }
        
        [self dismissController:self];
    }];
    
    
}

#pragma mark -table view datasource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [self.messageList count];
}

#pragma mark - table view delegate

-(BOOL) shouldShowTimeForRow:(NSInteger) row
{
     NSDictionary *previousMessage =nil;
    NSDictionary *messageRow = [self.messageList objectAtIndex:row];
    if(row>0) {
        previousMessage=[self.messageList objectAtIndex:row-1];
    }
    BOOL showTime=NO;
    if(previousMessage)
    {
        NSDate *previousTime=[self.sourceDateFormat dateFromString:[previousMessage objectForKey:@"thetime"]];
        NSDate *currenTime=[self.sourceDateFormat dateFromString:[messageRow objectForKey:@"thetime"]];
        if([currenTime timeIntervalSinceDate:previousTime]>=60*60){
            showTime=YES;
        }
        
    } else  {
        showTime=YES;
    }
    
    return showTime;
    
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn  row:(NSInteger)row
{
    
    NSDictionary *messageRow = [self.messageList objectAtIndex:row];
   
  
    MLChatViewCell *cell;
    
    if([[messageRow objectForKey:@"af"] isEqualToString:self.jid]) {
        cell = [tableView makeViewWithIdentifier:@"OutboundTextCell" owner:self];
        cell.isInbound= NO;
        cell.messageText.textColor = [NSColor whiteColor];
        cell.messageText.linkTextAttributes =@{NSForegroundColorAttributeName:[NSColor whiteColor], NSUnderlineStyleAttributeName: @YES};
    
    }
    else  {
        cell = [tableView makeViewWithIdentifier:@"InboundTextCell" owner:self];
        cell.isInbound=YES;
        cell.messageText.linkTextAttributes =@{NSForegroundColorAttributeName:[NSColor blackColor], NSUnderlineStyleAttributeName: @YES};
    }
    
    NSString *messageString =[messageRow objectForKey:@"message"];
    NSString *messageType =[messageRow objectForKey:kMessageType];
    if([messageType isEqualToString:kMessageTypeImage])
    {
        NSString* cellDirectionID = @"InboundImageCell";
        if([[messageRow objectForKey:@"af"] isEqualToString:self.jid]) {
            cellDirectionID=@"OutboundImageCell";
        }
        
        cell = [tableView makeViewWithIdentifier:cellDirectionID owner:self];
        cell.attachmentImage.image=nil;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableURLRequest *imageRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:messageString]];
            imageRequest.cachePolicy= NSURLRequestReturnCacheDataElseLoad;
            [[[NSURLSession sharedSession] dataTaskWithRequest:imageRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                 cell.imageData= data;
                if(data) {
                    cell.attachmentImage.image = [[NSImage alloc] initWithData:data];
                }
            }] resume];
            
        });
        
    }
    else  {
        
        //reset to remove any links
        cell.messageText.string=@"";
        
        cell.messageText.editable=YES;
        cell.messageText.string =messageString;
        [cell.messageText checkTextInDocument:nil];
        cell.messageText.editable=NO;
    }
    
    
    
    if([[messageRow objectForKey:@"delivered"] boolValue]!=YES)
    {
        cell.deliveryFailed=YES;
        cell.retry.tag= [[messageRow objectForKey:@"message_history_id"] integerValue];
    }
    else  {
        cell.deliveryFailed=NO;
    }
  
    BOOL showTime=[self shouldShowTimeForRow:row];
 
    cell.toolTip=[self formattedDateWithSource:[messageRow objectForKey:@"thetime"]];
    
    if(showTime) {
        cell.timeStamp.hidden=NO;
        cell.timeStampHeight.constant=kCellTimeStampHeight;
        cell.timeStampVeritcalOffset.constant = kCellDefaultPadding;
        cell.timeStamp.stringValue =[self formattedDateWithSource:[messageRow objectForKey:@"thetime"]];
    } else  {
        cell.timeStamp.hidden=YES;
        cell.timeStampHeight.constant=0.0f;
        cell.timeStampVeritcalOffset.constant=0.0f;
    }
    
   [[MLImageManager sharedInstance] getIconForContact:[messageRow objectForKey:@"af"] andAccount:self.accountNo withCompletion:^(NSImage *icon) {
       cell.senderIcon.image=icon;
   }];
    
    [cell updateDisplay];
    
    return cell;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    NSDictionary *messageRow = [self.messageList objectAtIndex:row];
    NSString *messageString =[messageRow objectForKey:@"message"];
    NSString *messageType =[messageRow objectForKey:kMessageType];
    if([messageType isEqualToString:kMessageTypeImage])
    {
        return 200;
    }
    else {
        
        NSRect rect = [MLChatViewCell sizeWithMessage:messageString ];
        
        BOOL showTime=[self shouldShowTimeForRow:row];
        NSInteger timeOffset =0;
        if(!showTime) timeOffset = kCellTimeStampHeight+kCellDefaultPadding;
        
        if(rect.size.height<44)  { // 44 is doublie line height
            return  kCellMinHeight-timeOffset;
        }
        else {
            return rect.size.height+kCellTimeStampHeight+kCellHeightOffset-timeOffset ;
            
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
                
        [self.destinationDateFormat setTimeStyle:NSDateFormatterShortStyle];
        [self.destinationDateFormat setDateStyle:NSDateFormatterMediumStyle];
        dateString = [ self.destinationDateFormat stringFromDate:destinationDate];
    }
    
    return dateString;
}


#pragma  mark - textview delegate
- (BOOL)textView:(NSTextView *)view shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)replacementString;
{
    if([replacementString isEqualToString:@"\n"])
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self sendText:self];
            });
            
            return NO;
      
        }
    return YES;
}

#pragma mark - quick look

-(IBAction)showImagePreview:(id)sender
{
    self.QLPreview = [QLPreviewPanel sharedPreviewPanel];
    if(self.QLPreview.isVisible)
    {
        [self.QLPreview  orderOut:self];
    }
    else  {
        
        NSButton *button =(NSButton*) sender;
        MLChatViewCell *cell = (MLChatViewCell *)button.superview;
        self.tmpPreviewImageData = cell.imageData;
        
        [self.QLPreview makeKeyAndOrderFront:self];
    }
}

#pragma mark - quicklook datasource
- (NSInteger)numberOfPreviewItemsInPreviewPanel:(QLPreviewPanel *)panel
{
    return 1; 
}

- (id<QLPreviewItem>)previewPanel:(QLPreviewPanel *)panel
               previewItemAtIndex:(NSInteger)index
{
    
    MLPreviewObject *preview = [[MLPreviewObject alloc] init];
    preview.previewItemTitle=@"Image Preview";
  
    NSString* tmpFilePath = [NSString stringWithFormat:@"%@tmp.png", NSTemporaryDirectory()];
    BOOL writeSuccess= [self.tmpPreviewImageData writeToFile:tmpFilePath atomically:YES];
    
    if(!writeSuccess)
    {
        DDLogError(@"Could not write tmp file %@", tmpFilePath);
    }
    
    preview.previewItemURL =[NSURL URLWithString:[NSString stringWithFormat:@"file://%@",tmpFilePath]];
    return preview;
}



@end
