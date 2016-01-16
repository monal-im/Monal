//
//  MLContactsViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MLChatViewController.h"

@interface MLContactsViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate, NSControlTextEditingDelegate, NSTextFieldDelegate, NSSearchFieldDelegate>

@property (nonatomic, strong) IBOutlet NSTableView *contactsTable;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *segmentedControl;

@property (nonatomic, weak) MLChatViewController *chatViewController;

-(void) showConversationForContact:(NSDictionary *) user;

// methods requied for XMPP accont to call back  should be protocol
-(void) showConnecting:(NSDictionary*) info;
-(void) updateConnecting:(NSDictionary*) info;
-(void) hideConnecting:(NSDictionary*) info;

-(void) clearContactsForAccount: (NSString*) accountNo;

-(void) addOnlineUser:(NSDictionary*) user;
-(void) removeOnlineUser:(NSDictionary*) user;

-(void) showAuthRequestForContact:(NSString *) contactName withCompletion: (void (^)(BOOL))completion;

-(IBAction)segmentDidChange:(id)sender;

-(IBAction)deleteItem:(id)sender;
-(IBAction)startFind:(id)sender;

-(void)toggleContactsTab;
-(void)toggleActiveChatTab;

-(void) highlightCellForCurrentContact;

@end
