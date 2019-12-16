//
//  MLContactsViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MLChatViewController.h"

@interface MLContactsViewController : NSViewController <NSOutlineViewDelegate, NSOutlineViewDataSource, NSControlTextEditingDelegate, NSTextFieldDelegate, NSSearchFieldDelegate>

@property (nonatomic, strong) IBOutlet NSOutlineView *contactsTable;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *segmentedControl;

@property (nonatomic, weak) MLChatViewController *chatViewController;

-(void) showConversationForContact:(MLContact *) user;

// methods requied for XMPP accont to call back  should be protocol

-(void) clearContactsForAccount: (NSString*) accountNo;


-(void) showAuthRequestForContact:(NSString *) contactName withCompletion: (void (^)(BOOL))completion;

-(IBAction)segmentDidChange:(id)sender;

-(IBAction)deleteItem:(id)sender;
-(IBAction)muteItem:(id)sender;
-(IBAction)startFind:(id)sender;
-(IBAction)toggleEncryption:(id)sender;

-(void)toggleContactsTab;
-(void)toggleActiveChatTab;


-(void) highlightCellForCurrentContact;

@end
