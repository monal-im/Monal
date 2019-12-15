//
//  MLChatViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MLTextView.h"
#import "MLContact.h"
#import "MLMessage.h"
@import Quartz;
@import QuickLook;

@interface MLChatViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate>

@property (nonatomic, strong) IBOutlet MLTextView *messageBox;
@property (nonatomic, strong) IBOutlet NSScrollView *messageScroll;
@property (nonatomic, weak) IBOutlet NSView *inputBar;

@property (nonatomic, strong) IBOutlet NSScrollView *tableScroll;
@property (nonatomic, strong) IBOutlet NSTableView *chatTable;
@property (nonatomic, weak) IBOutlet NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) MLContact *contact; 
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *inputContainerHeight;

@property (nonatomic, assign, readonly) BOOL encryptChat;

/**
 full own username with domain e.g. aa@gmail.com
 */
@property (nonatomic, strong) NSString* jid;


-(IBAction)sendText:(id)sender;
-(IBAction)emojiPicker:(id)sender;
-(IBAction)attach:(id)sender;
-(IBAction)showImagePreview:(id)sender;
-(IBAction)toggleEncryption:(id)sender;

-(IBAction)deliveryFailedMessage:(id)sender;

-(void) sendMessage:(NSString *) messageText andMessageID:(NSString *)messageID isUpload:(BOOL) isUpload;

-(void) showConversationForContact:(NSDictionary *)contact;

/**
 mark as conversation as read and update teh application badge
 */
-(void) markAsRead;

@end
