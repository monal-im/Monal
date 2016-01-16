//
//  MLChatViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface MLChatViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate>

@property (nonatomic, strong) IBOutlet NSTextView *messageBox;
@property (nonatomic, strong) IBOutlet NSTableView *chatTable;
@property (nonatomic, strong) NSDictionary *contactDic;
@property (nonatomic, strong, readonly) NSString *contactName;

-(IBAction)sendText:(id)sender;
-(IBAction)emojiPicker:(id)sender;
-(IBAction)deliveryFailedMessage:(id)sender;

-(void) sendMessage:(NSString *) messageText andMessageID:(NSString *)messageID;

-(void) showConversationForContact:(NSDictionary *)contact;

@end
