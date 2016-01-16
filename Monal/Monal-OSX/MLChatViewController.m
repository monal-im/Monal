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
//#import "MLNotificaitonCenter.h"

#import "MLMainWindow.h"

@interface MLChatViewController ()

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

#pragma mark - notificaitons
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
                           
                           [self.messageList addObject:userInfo];
                         
                           if((self.view.window.occlusionState & NSWindowOcclusionStateVisible)) {
                               [self.chatTable reloadData];
                               [self scrollToBottom];
                               [self markAsRead];
                           }
                       });
    }

    
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
    
    [[DataLayer sharedInstance] addMessageHistoryFrom:self.jid to:to forAccount:[NSString stringWithFormat:@"%@",self.accountNo] withMessage:message actuallyFrom:self.jid withId:messageId withCompletion:^(BOOL result) {
    if(result){
        DDLogVerbose(@"added message %@, %@ %@", message, messageId, [self currentGMTTime]);
        
        NSDictionary* userInfo = @{@"af": self.jid,
                                   @"message": message ,
                                   @"thetime": [self currentGMTTime],
                                   kDelivered:@YES,
                                   kMessageId: messageId
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
    [[MLXMPPManager sharedInstance] sendMessage:messageText toContact:self.contactName fromAccount:self.accountNo isMUC:self.isMUC messageId:newMessageID
                          withCompletionHandler:nil];
    
    //dont readd it, use the exisitng
    if(!messageID) {
        [self addMessageto:_contactName withMessage:messageText andId:newMessageID];
    }
    
    //mark as read
    
    //update badge
}


-(IBAction)sendText:(id)sender
{
    NSString *message= [self.messageBox.string copy];
    if(message.length>0) {
        [self sendMessage:[self.messageBox.string copy] andMessageID:nil];
        self.messageBox.string=@"";
    }
}


-(IBAction)deliveryFailedMessage:(id)sender
{
    NSAlert *userAddAlert = [[NSAlert alloc] init];
    userAddAlert.messageText=@"Message Failed to Send";
    userAddAlert.informativeText =[NSString stringWithFormat:@"This message may may have failed to send."];
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
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn  row:(NSInteger)row
{
    
    NSDictionary *messageRow = [self.messageList objectAtIndex:row];
    MLChatViewCell *cell;
    
    if([[messageRow objectForKey:@"af"] isEqualToString:self.jid]) {
        cell = [tableView makeViewWithIdentifier:@"OutboundTextCell" owner:self];
        cell.isInbound= NO;
        cell.messageText.textColor = [NSColor whiteColor];
        cell.messageText.linkTextAttributes =@{NSForegroundColorAttributeName:[NSColor whiteColor], NSUnderlineStyleAttributeName: @YES};
        
        if([[messageRow objectForKey:@"delivered"] boolValue]!=YES)
        {
            cell.deliveryFailed=YES;
            cell.retry.tag= [[messageRow objectForKey:@"message_history_id"] integerValue];
        }
        else  {
            cell.deliveryFailed=NO;
        }
    
    }
    else  {
        cell = [tableView makeViewWithIdentifier:@"InboundTextCell" owner:self];
        cell.isInbound=YES;
        cell.messageText.linkTextAttributes =@{NSForegroundColorAttributeName:[NSColor blackColor], NSUnderlineStyleAttributeName: @YES};
    }
    
    //reset to remove any links
    cell.messageText.string=@"";
    
    cell.messageText.editable=YES;
    cell.messageText.string =[messageRow objectForKey:@"message"];
    [cell.messageText checkTextInDocument:nil];
    cell.messageText.editable=NO;
    cell.timeStamp.stringValue =[self formattedDateWithSource:[messageRow objectForKey:@"thetime"]];
    
    [cell updateDisplay];   
    
    return cell;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    NSDictionary *messageRow = [self.messageList objectAtIndex:row];
    NSString *messageString =[messageRow objectForKey:@"message"];

    NSRect rect = [MLChatViewCell sizeWithMessage:messageString];
 
    if(rect.size.height<kCellMinHeight)  {
        return  kCellMinHeight;
    }
    else {
        return rect.size.height+5.0+5.0;
    
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

@end
