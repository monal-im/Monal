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

#import "MLXMPPManager.h"
#import "MLChatViewCell.h"
#import "MLImageManager.h"
#import "MLPreviewObject.h"

#import "MLMainWindow.h"
#import "MLLinkViewCell.h"

@import Quartz;

@interface MLChatViewController ()

@property (nonatomic, strong) NSMutableArray *messageList;

@property (nonatomic, strong)  NSDateFormatter* destinationDateFormat;
@property (nonatomic, strong)  NSDateFormatter* sourceDateFormat;
@property (nonatomic, strong)  NSCalendar *gregorian;
@property (nonatomic, assign) NSInteger thisyear;
@property (nonatomic, assign) NSInteger thismonth;
@property (nonatomic, assign) NSInteger thisday;

@property (nonatomic, assign) BOOL isMUC;

@property (nonatomic, strong) QLPreviewPanel *QLPreview;
@property (nonatomic, strong) NSData *tmpPreviewImageData;

@property (nonatomic, assign) BOOL encryptChat;
@property (nonatomic, weak)  NSToolbarItem *encryptButton;


@end

@implementation MLChatViewController 



- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    [nc addObserver:self selector:@selector(handleSendFailedMessage:) name:kMonalSendFailedMessageNotice object:nil];
    [nc addObserver:self selector:@selector(handleSentMessage:) name:kMonalSentMessageNotice object:nil];
    [nc addObserver:self selector:@selector(refreshData) name:kMonalWindowVisible object:nil];
    [nc addObserver:self selector:@selector(refreshMessage:) name:kMonalMessageReceivedNotice object:nil];
    [nc addObserver:self selector:@selector(fetchMoreMessages) name:kMLMAMMore object:nil];
    
    
    [self setupDateObjects];
    
    self.progressIndicator.bezeled=NO;
    self.progressIndicator.controlSize=NSMiniControlSize;
    [self endProgressUpdate];
   
    self.messageScroll.wantsLayer=YES;
    self.messageScroll.layer.cornerRadius=10.0f;
    
  
    [self updateLinguisticSettings];
}

-(void) viewWillAppear
{
    [super viewWillAppear];
    if(!self.contact) {
        self.inputBar.hidden=YES;
        self.tableScroll.hidden=YES;
        return;
    }
 
    [self refreshData];
    [self updateWindowForContact:self.contact];
    [self updateInputViewSize];
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
    if(!self.contact) {
        self.inputBar.hidden=YES;
        self.tableScroll.hidden=YES;
        return;
    }
    
    self.inputBar.hidden=NO;
    self.tableScroll.hidden=NO;
    self.messageList =[[DataLayer sharedInstance] messageHistory:self.contact.contactJid forAccount: self.contact.accountId];
    if(!self.messageList)  {
        self.messageList = [[NSMutableArray alloc] init];
    }
    [self.chatTable reloadData];
    [self scrollToBottom];
    
    self.encryptChat =[[DataLayer sharedInstance] shouldEncryptForJid:self.contact.contactJid  andAccountNo: self.contact.accountId];
    
}

-(void) showConversationForContact:(MLContact *) contact
{
    if([ self.contact.accountId isEqualToString:contact.accountId]
       && [self.contact.contactJid isEqualToString: contact.contactJid])
    {
        return;
    }
  
//    [MLNotificationManager sharedInstance].currentAccountNo=self.contact.accountId;
//    [MLNotificationManager sharedInstance].currentContact=self.contact.contactJid;
    self.contact= contact;
    self.isMUC = contact.isGroup;
    
    NSArray* accountVals =[[DataLayer sharedInstance] accountVals:self.contact.accountId];
    if([accountVals count]>0)
    {
        self.jid=[NSString stringWithFormat:@"%@@%@",[[accountVals objectAtIndex:0] objectForKey:kUsername], [[accountVals objectAtIndex:0] objectForKey:kDomain]];
    }
        if((self.view.window.occlusionState & NSWindowOcclusionStateVisible)) {
        [self markAsRead];
    }
    [self refreshData];
    [self updateWindowForContact:contact];
    
    [self synchChat];
    
#ifndef DISABLE_OMEMO
    xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId];
    [xmppAccount queryOMEMODevicesFrom:self.contact.contactJid];
#endif
}

#pragma mark - MAM

-(void) synchChat
{
    xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId];
        if(xmppAccount.connectionProperties.supportsMam2 & !self.contact.isGroup) {
            if(self.messageList.count==0) {
                [xmppAccount setMAMQueryMostRecentForJid:self.contact.contactJid ];
            }
        }
}


-(void) fetchMoreMessages
{
    [self synchChat];
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

-(void) updateWindowForContact:(MLContact *)contact
{
    NSMutableDictionary *dic = [contact mutableCopy];
    [dic setObject:[NSNumber numberWithBool:self.encryptChat] forKey:@"encrypt"];
  
    MLMainWindow *window =(MLMainWindow *)self.view.window.windowController;
    [window updateCurrentContact:dic];
    
    self.chatTable.accessibilityLabel=[NSString stringWithFormat:@"Chat with %@", contact.contactDisplayName];
}


-(void) endProgressUpdate
{
    dispatch_async(dispatch_get_main_queue(), ^{
    self.progressIndicator.doubleValue=0;
    self.progressIndicator.hidden=YES;
    });
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

-(void) uploadFile:(NSString *)filename andType: (NSString*) mimeType withData:(NSData *) data
{
    xmpp* account=[[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId];
    if(!account.connectionProperties.supportsHTTPUpload)
    {
        [self showNoUploadAlert];
        
        return;
    }
    
    self.progressIndicator.doubleValue=0;
    self.progressIndicator.hidden=NO;
    
    // start http upload XMPP
    self.progressIndicator.doubleValue=50;
    [[MLXMPPManager sharedInstance] httpUploadData:data withFilename:filename andType:mimeType                                                 toContact:self.contact.contactJid onAccount:self.contact.accountId withCompletionHandler:^(NSString *url, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self endProgressUpdate];
            if(url) {
                self.messageBox.string= url;
                [self sendTextWithUpload:YES];
            }
            else  {
                NSAlert *userAddAlert = [[NSAlert alloc] init];
                userAddAlert.messageText = @"There was an error uploading the file to the server.";
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

-(void) uploadFile:(NSURL *) fileURL
{
    NSData *data =  [NSData dataWithContentsOfURL:fileURL];
    NSString *filename = [fileURL lastPathComponent];
    
    NSString *ext = [filename componentsSeparatedByString:@"."].lastObject;

    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)ext, NULL);
    NSString *mimeType = (__bridge_transfer NSString *)(UTTypeCopyPreferredTagWithClass (UTI, kUTTagClassMIMEType));
    if(!mimeType) mimeType=@"application/octet-stream";
    CFRelease(UTI);
    [self uploadFile:filename andType:mimeType withData:data];
}



-(IBAction)attach:(id)sender
{
    xmpp* account=[[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId];
    if(!account.connectionProperties.supportsHTTPUpload )
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
    MLMessage *contact = [notification.userInfo objectForKey:@"message"];
    
    if([[notification.userInfo objectForKey:kMessageType] isEqualToString:kMessageTypeStatus])
    {
//        NSMutableDictionary *mutableContact = [self.contactDic mutableCopy];
//        [mutableContact setObject:[notification.userInfo objectForKey:@"muc_subject"]  forKey:@"muc_subject"];
//        self.contactDic= [mutableContact copy];
//        dispatch_async(dispatch_get_main_queue(), ^{
//            [self updateWindowForContact:self.contactDic];
//
//        });
        
    }
    
    NSNumber *shouldRefresh =[notification.userInfo objectForKey:@"shouldRefresh"];
    if (shouldRefresh.boolValue) {
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           [self refreshData];
                       });
        return;
    }
    
    
    if([[notification.userInfo objectForKey:@"accountNo"] isEqualToString:self.contact.accountId]
       &&( ( [[notification.userInfo objectForKey:@"from"] isEqualToString:self.contact.contactJid]) || ([[notification.userInfo objectForKey:@"to"] isEqualToString:self.contact.contactJid] ))
       )
    {
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                          
                           NSDictionary* userInfo;
                           if([[notification.userInfo objectForKey:@"to"] isEqualToString:self.contact.contactJid])
                           {
                               userInfo = @{@"af": [notification.userInfo objectForKey:@"actuallyfrom"],
                                            @"message": [notification.userInfo objectForKey:@"messageText"],
                                             @"messageid": [notification.userInfo objectForKey:@"messageid"],
                                            @"thetime": [self currentGMTTime],   @"delivered":@YES};
                               
                           } else  {
                               userInfo = @{@"af": [notification.userInfo objectForKey:@"actuallyfrom"],
                                            @"message": [notification.userInfo objectForKey:@"messageText"],
                                             @"messageid": [notification.userInfo objectForKey:@"messageid"],
                                            @"thetime": [self currentGMTTime]
                                            };
                           }
                           
                           [self.messageList addObject:[userInfo mutableCopy]];
                         
                           if((self.view.window.occlusionState & NSWindowOcclusionStateVisible)) {
                               [self refreshData];
                               [self markAsRead];
                           }
                       });
    }

  
    
    
}


-(void) refreshMessage:(NSNotification *)notification
{
    NSDictionary *dic =notification.userInfo;
    [self setMessageId:[dic objectForKey:kMessageId]  received:YES];
    [self endProgressUpdate];
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
    [[DataLayer sharedInstance] markAsReadBuddy:self.contact.contactJid forAccount:self.contact.accountId];
    
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

#pragma mark - encryption
-(IBAction)toggleEncryption:(id)sender
{
    // check for trusted keys
    
    // ask if disabling encryption
    if(self.encryptChat==YES) {
        [[DataLayer sharedInstance] disableEncryptForJid:self.contact.contactJid andAccountNo:self.contact.accountId];
        self.encryptButton =(NSToolbarItem *)sender;
        self.encryptButton.image = [NSImage imageNamed:@"745-unlocked"];
        self.encryptChat=NO;
    }
    else {
        [[DataLayer sharedInstance] encryptForJid:self.contact.contactJid andAccountNo:self.contact.accountId];
        self.encryptButton =(NSToolbarItem *)sender;
        self.encryptButton.image = [NSImage imageNamed:@"744-locked-selected"];
        self.encryptChat=YES; 
    }
}

#pragma mark - sending

//always messages going out
-(void) addMessageto:(NSString*)to withMessage:(NSString*) message andId:(NSString *) messageId
{
    if(!self.jid || !message)  {
        DDLogError(@" not ready to send messages");
        return;
    }
    
    [[DataLayer sharedInstance] addMessageHistoryFrom:self.jid to:to forAccount:[NSString stringWithFormat:@"%@",self.contact.accountId] withMessage:message actuallyFrom:self.jid withId:messageId encrypted:self.encryptChat withCompletion:^(BOOL result, NSString *messageType) {
    if(result){
        DDLogVerbose(@"added message %@, %@ %@", message, messageId, [self currentGMTTime]);
        
        NSDictionary* userInfo = @{@"af": self.jid,
                                   @"message": message ,
                                   @"thetime": [self currentGMTTime],
                                   kDelivered:@YES,
                                   @"messageid": messageId,
                                   kMessageType: messageType,
                                   @"encrypted":[NSNumber numberWithBool:self.encryptChat]
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
    
    [[DataLayer sharedInstance] isActiveBuddy:to forAccount:self.contact.accountId withCompletion:^(BOOL isActive) {
        if(!isActive) {
            [[DataLayer sharedInstance] addActiveBuddies:to forAccount:self.contact.accountId withCompletion:nil];

        }
    }];

}

-(void) setMessageId:(NSString *) messageId received:(BOOL) delivered
{
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       int row=0;
                       for(NSMutableDictionary *rowDic in self.messageList)
                       {
                           if([[rowDic objectForKey:@"messageid"] isEqualToString:messageId]) {
                               
                               [rowDic setObject:[NSNumber numberWithBool:delivered] forKey:kReceived];
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

-(void) sendMessage:(NSString *) messageText andMessageID:(NSString *)messageID isUpload:(BOOL) isUpload
{
    DDLogVerbose(@"Sending message %@", messageText);
    NSString *newMessageID =[[NSUUID UUID] UUIDString];
    [self.progressIndicator incrementBy:25];
    [[MLXMPPManager sharedInstance] sendMessage:messageText toContact:self.contact.contactJid fromAccount:self.contact.accountId isEncrypted:self.encryptChat isMUC:self.isMUC isUpload:isUpload messageId:newMessageID
     withCompletionHandler:^(BOOL success, NSString *messageId) {
         if(success)
         {
            dispatch_async( dispatch_get_main_queue(), ^{
              [self.progressIndicator incrementBy:25];
            });
         } else {
             
         }
     }];
    
    //dont readd it, use the exisitng
    if(!messageID) {
        [self addMessageto:self.contact.contactJid withMessage:messageText andId:newMessageID];
    }
    

}


-(IBAction)sendText:(id)sender
{
    [self sendTextWithUpload:NO];
}

-(IBAction)sendTextWithUpload:(BOOL) isUpload;
{
    
    self.progressIndicator.doubleValue=0;
    self.progressIndicator.hidden=NO;
    __block BOOL upload =  isUpload;
    
    [self.messageBox.textStorage enumerateAttribute:NSAttachmentAttributeName
                                            inRange:NSMakeRange(0, self.messageBox.textStorage.length)
                                            options:0
                                         usingBlock:^(id value, NSRange range, BOOL *stop)
     {
         NSTextAttachment* attachment = (NSTextAttachment*)value;
         NSData* attachmentData = attachment.fileWrapper.regularFileContents;
         
         NSString *filename = attachment.fileWrapper.preferredFilename;
         
         NSString *ext = [filename componentsSeparatedByString:@"."].lastObject;
         
         CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)ext, NULL);
         NSString *mimeType = (__bridge_transfer NSString *)(UTTypeCopyPreferredTagWithClass (UTI, kUTTagClassMIMEType));
         if(!mimeType) mimeType=@"application/octet-stream";
         CFRelease(UTI);
         if(attachmentData)
         {
             [self uploadFile:filename andType:mimeType withData:attachmentData];
             upload=YES;
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
            
            NSString *valuetoAppend ;
            if([value isKindOfClass:[NSString class]])
            {
                valuetoAppend= value;
            }
            else if([value isKindOfClass:[NSURL class]])
            {
                valuetoAppend = [value absoluteString];
            }
            else  {
                DDLogWarn(@"non string or url in attributed text");
            }
            
            if(valuetoAppend) {
                [message appendString:valuetoAppend];
            }
        }
    }];
    
    
    if(message.length>0) {
        [self sendMessage:message andMessageID:nil isUpload:upload];
    }
    self.messageBox.string=@"";
    self.messageBox.backgroundColor=[NSColor textBackgroundColor];
    self.messageBox.textColor =[NSColor textColor];
    self.messageBox.alignment =NSTextAlignmentLeft;
    self.messageBox.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    [self updateInputViewSize];
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
                [self sendMessage:[dic objectForKey:@"message"] andMessageID:[dic objectForKey:@"messageid"] isUpload:NO];
            }
            
        }
        
        [self dismissController:self];
    }];
    
    
}

#pragma mark - table view datasource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [self.messageList count];
}

#pragma mark - table view delegate

-(BOOL) shouldShowTimeForRow:(NSInteger) row
{
    MLMessage *previousMessage =nil;
    MLMessage *messageRow = [self.messageList objectAtIndex:row];
    if(row>0) {
        previousMessage=[self.messageList objectAtIndex:row-1];
    }
    BOOL showTime=NO;
    if(previousMessage)
    {
        NSDate *previousTime=previousMessage.timestamp;
        NSDate *currenTime=messageRow.timestamp;
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
    MLMessage *messageRow = [self.messageList objectAtIndex:row];
    MLChatViewCell *cell;
    
    NSString *messageString = messageRow.messageText;
    NSString *messageType =messageRow.messageType;
    cell.timeStamp.stringValue=@""; //remove template values to not break voice over
    
    if([messageType isEqualToString:kMessageTypeStatus])
    {
        cell = [tableView makeViewWithIdentifier:@"statusCell" owner:self];
        cell.timeStamp.stringValue=messageString;
        return cell;
    }
    
    NSMutableString *accessibility =[[NSMutableString alloc] init];
   
    [accessibility appendString:@""];
    
    if([messageType isEqualToString:kMessageTypeText]) {
        if([messageRow.actualFrom isEqualToString:self.jid]) {
            cell = [tableView makeViewWithIdentifier:@"OutboundTextCell" owner:self];
            cell.isInbound= NO;
            cell.messageText.textColor = [NSColor whiteColor];
            cell.messageText.linkTextAttributes =@{NSForegroundColorAttributeName:[NSColor whiteColor], NSUnderlineStyleAttributeName: @YES};
            [accessibility appendString:@"Your Message "];
            
        }
        else  {
            cell = [tableView makeViewWithIdentifier:@"InboundTextCell" owner:self];
            cell.isInbound=YES;
            cell.messageText.linkTextAttributes =@{NSForegroundColorAttributeName:[NSColor blackColor], NSUnderlineStyleAttributeName: @YES};
            [accessibility appendString:@"Message "];
        }
        
        
        //reset to remove any links
        cell.messageText.string=@"";
        cell.messageText.editable=YES;
        cell.messageText.string =messageString;
        [cell.messageText checkTextInDocument:nil];
        cell.messageText.editable=NO;
        
        [accessibility appendString:messageString];

    }
    
     if([messageType isEqualToString:kMessageTypeImage])
    {
        NSString* cellDirectionID = @"InboundImageCell";
        if([messageRow.actualFrom  isEqualToString:self.jid]) {
            cellDirectionID=@"OutboundImageCell";
        }
        
        cell = [tableView makeViewWithIdentifier:cellDirectionID owner:self];
        cell.attachmentImage.canDrawSubviewsIntoLayer=YES;
        if(![cell.link isEqualToString:messageString]) {
            cell.attachmentImage.image=nil;
            cell.link=messageString;
            [cell loadImage:cell.link WithCompletion:^{
                
            }];
        }
        
        
 
    }
    
    if([messageType isEqualToString:kMessageTypeUrl])
    {
        NSString* cellDirectionID = @"InboundLinkCell";
        if([messageRow.actualFrom  isEqualToString:self.jid]) {
            cellDirectionID=@"OutboundLinkCell";
        }
        MLLinkViewCell *linkCell = [tableView makeViewWithIdentifier:cellDirectionID owner:self];
        cell.attachmentImage.image=nil;
        cell.attachmentImage.canDrawSubviewsIntoLayer=YES;
        linkCell.link=messageString;
      
        if(messageRow.previewImage
           || [messageRow.previewText length]>0)
        {
            linkCell.link=messageString;
            linkCell.webURL=messageString;
            linkCell.previewText.stringValue = messageRow.previewText ;
            linkCell.website.stringValue=messageString; 
            [linkCell loadImage:messageRow.previewImage.absoluteString WithCompletion:nil];
        }  else {
            [linkCell loadPreviewWithCompletion:^{
                if(linkCell.previewText.stringValue.length==0) (linkCell.previewText.stringValue=@" "); // prevent repeated calls
                [[DataLayer sharedInstance] setMessageId:messageRow.messageId previewText:linkCell.previewText.stringValue  andPreviewImage:linkCell.imageUrl];
            }];
        }
        
        cell=linkCell;
    }
   
    if(messageRow.hasBeenSent!=YES)
    {
        cell.deliveryFailed=YES;
        cell.retry.accessibilityLabel=@"Retry Sending";
        cell.retry.tag= [messageRow.messageId integerValue];
    }
    else  {
        cell.deliveryFailed=NO;
    }
 
    cell.messageStatus.accessibilityLabel=@"Delivered";
    if(messageRow.hasBeenReceived==YES) {
        NSDictionary *prior =nil;
        if(row>0)
        {
            prior = [self.messageList objectAtIndex:row-1];
        }
        if(row==self.messageList.count-1 || ![[prior objectForKey:@"af"] isEqualToString:self.jid]) {
            cell.messageStatus.hidden=NO;
        } else  {
            cell.messageStatus.hidden=YES;
        }
    }
    else  {
        cell.messageStatus.hidden=YES;
    }
    
    if(messageRow.encrypted==YES)
    {
        cell.lockImage.hidden=NO;
        cell.lockImage.accessibilityLabel=@"encrypted";
    }
    else  {
        cell.lockImage.hidden=YES;
    }
    
    
    BOOL showTime=[self shouldShowTimeForRow:row];
    
    NSString *dateString=[self formattedDateWithSource:messageRow.timestamp];
    cell.toolTip=dateString;
   
    if(showTime) {
        cell.timeStamp.hidden=NO;
        cell.timeStampHeight.constant=kCellTimeStampHeight;
        cell.timeStampVeritcalOffset.constant = kCellDefaultPadding;
        cell.timeStamp.stringValue =[self formattedDateWithSource:messageRow.timestamp];
    } else  {
        cell.timeStamp.hidden=YES;
        cell.timeStampHeight.constant=0.0f;
        cell.timeStampVeritcalOffset.constant=0.0f;
       
        if(dateString) {
            [accessibility appendString:@" "];
            [accessibility appendString:dateString];
        }
        
    }
    
    cell.scrollArea.accessibilityLabel=accessibility;
   
    
   [[MLImageManager sharedInstance] getIconForContact:messageRow.actualFrom andAccount:self.contact.accountId withCompletion:^(NSImage *icon) {
       cell.senderIcon.image=icon;
   }];

    if(self.isMUC && cell.isInbound)
    {
        cell.senderName.stringValue=messageRow.actualFrom;
        cell.senderName.hidden=NO;
        cell.nameHeight.constant=kCellTimeStampHeight;
        cell.timeStampHeight.constant=kCellTimeStampHeight;
        cell.timeStampVeritcalOffset.constant=kCellDefaultPadding;
    } else  {
        cell.nameHeight.constant=0.0f;
        cell.senderName.hidden=YES;
    }
    
    [cell updateDisplay];
    
    return cell;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    MLMessage *messageRow = [self.messageList objectAtIndex:row];
    NSString *messageString =messageRow.messageText;
    NSString *messageType =messageRow.messageType;
    if([messageType isEqualToString:kMessageTypeStatus])
    {
        return 45;
    }
    
    if([messageType isEqualToString:kMessageTypeImage])
    {
        return 230;
    }
    if([messageType isEqualToString:kMessageTypeUrl])
    {
        return 235;
    }
    else {
        
        NSRect rect = [MLChatViewCell sizeWithMessage:messageString ];
        
        BOOL showTime=[self shouldShowTimeForRow:row];
        NSInteger timeOffset =0;
        if(!showTime && !self.isMUC) timeOffset = kCellTimeStampHeight+kCellDefaultPadding;
        
        if(rect.size.height<44 )  { // 44 is doublie line height
            return  kCellMinHeight-timeOffset;
        }
        else {
            return rect.size.height+kCellTimeStampHeight+kCellHeightOffset-timeOffset ;
            
        }
    }
}

#pragma mark - date time

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

-(NSString*) formattedDateWithSource:(NSDate*) sourceDate
{
    NSString* dateString;
    
        [self.destinationDateFormat setTimeStyle:NSDateFormatterShortStyle];
        [self.destinationDateFormat setDateStyle:NSDateFormatterMediumStyle];
        dateString = [ self.destinationDateFormat stringFromDate:sourceDate];
    
    return dateString;
}



#pragma  mark - textview delegate
- (BOOL)textView:(NSTextView *)view shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)replacementString;
{
    NSUInteger flags = [[NSApp currentEvent] modifierFlags];
    if([replacementString isEqualToString:@"\n"]   && !(flags & NSShiftKeyMask))
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self sendText:self];
            });
            return NO;
        }
    
    return YES;
}

-(BOOL)textShouldEndEditing:(NSText *)textObject
{
    [self saveLinguisticSettings];
    return YES;
}

- (void)textDidChange:(NSNotification *)notification;
{
     [self updateInputViewSize];
}

-(void) updateInputViewSize
{
    
    if(self.messageBox.intrinsicContentSize.height>22) {
        self.inputContainerHeight.constant= self.messageBox.intrinsicContentSize.height+16+10;
        if(self.inputContainerHeight.constant>300) self.inputContainerHeight.constant=300;
          self.messageScroll.contentInsets = NSEdgeInsetsMake(5, 0, 5, 0);
    } else
    {
        self.inputContainerHeight.constant=38.0f;
          self.messageScroll.contentInsets = NSEdgeInsetsMake(5, 0, 5, 0);
    }
    //  [self.messageScroll setScrollEnabled:NO];
    [self.inputBar layout];
    //  [self.messageBox setScrollEnabled:YES];
    [self.messageBox scrollRangeToVisible:NSMakeRange(0, 0)];
}


-(void) updateLinguisticSettings
{
    if([[NSUserDefaults standardUserDefaults] objectForKey:@"CotinuousSpellCheck"]) {
        self.messageBox.continuousSpellCheckingEnabled= [[NSUserDefaults standardUserDefaults] boolForKey:@"CotinuousSpellCheck"];
        self.messageBox.automaticSpellingCorrectionEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"AutoSpellCheck"];
        self.messageBox.grammarCheckingEnabled =[[NSUserDefaults standardUserDefaults] boolForKey:@"GrammarCheck"];
    }
}


-(void) saveLinguisticSettings
{
    [[NSUserDefaults standardUserDefaults] setBool:self.messageBox.continuousSpellCheckingEnabled forKey:@"CotinuousSpellCheck"];
    [[NSUserDefaults standardUserDefaults] setBool:self.messageBox.automaticSpellingCorrectionEnabled forKey:@"AutoSpellCheck"];
    [[NSUserDefaults standardUserDefaults] setBool:self.messageBox.grammarCheckingEnabled forKey:@"GrammarCheck"];
    
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
        
        MLImageView *clickedImage =(MLImageView*) sender;
        MLChatViewCell *cell = (MLChatViewCell *)clickedImage.superview;
        self.tmpPreviewImageData = cell.imageData;
        [self.view.window makeFirstResponder:self.view];
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
