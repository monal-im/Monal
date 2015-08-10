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
//#import "MLNotificaitonCenter.h"

@interface MLChatViewController ()

@property (nonatomic, strong) NSMutableArray *messageList;

@property (nonatomic, strong) NSNumber *accountNo;
@property (nonatomic, strong) NSString *contactName;
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
    
    
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) showConversationForContact:(NSDictionary *) contact
{
//    [MLNotificationManager sharedInstance].currentAccountNo=self.accountNo;
//    [MLNotificationManager sharedInstance].currentContact=self.contactName;

    self.accountNo = [contact objectForKey:kAccountID];
    self.contactName = [contact objectForKey:kContactName];
    
    self.messageList =[[DataLayer sharedInstance] messageHistory:self.contactName forAccount: self.accountNo];
    
    [self.chatTable reloadData];
    
}


#pragma mark -- notificaitons
-(void) handleNewMessage:(NSNotification *)notification
{
    
}

-(void) addMessageto:(NSString*)to withMessage:(NSString*) message andId:(NSString *) messageId
{
    
}

-(void) handleSendFailedMessage:(NSNotification *)notification
{
    NSDictionary *dic =notification.userInfo;
   // [self setMessageId:[dic objectForKey:kMessageId]  delivered:NO];
}

-(void) handleSentMessage:(NSNotification *)notification
{
    NSDictionary *dic =notification.userInfo;
  //  [self setMessageId:[dic objectForKey:kMessageId]  delivered:YES];
}

#pragma mark - actions 

-(void) sendMessage:(NSString *) messageText andMessageID:(NSString *)messageID
{
    DDLogVerbose(@"Sending message %@", messageText);
    u_int32_t r = arc4random_uniform(30000000);
    NSString *newMessageID =messageID;
    if(!newMessageID) {
        newMessageID=[NSString stringWithFormat:@"Monal%d", r];
    }
    [[MLXMPPManager sharedInstance] sendMessage:messageText toContact:self.contactName fromAccount:[NSString stringWithFormat:@"%@", self.accountNo]  isMUC:self.isMUC messageId:newMessageID
                          withCompletionHandler:nil];
    
    //dont readd it, use the exisitng
    if(!messageID) {
        [self addMessageto:_contactName withMessage:messageText andId:newMessageID];
    }
}


-(IBAction)send:(id)sender
{
    [self sendMessage:[self.messageBox.string copy] andMessageID:nil];
    self.messageBox.string=@"";
}

#pragma mark -table view datasource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [self.messageList count];
}

#pragma mark - table view delegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn  row:(NSInteger)row
{
    
// MLchatViewCell *cell= [tableView makeViewWithIdentifier:cellIdentifier owner:self];
    return nil;
}


@end
