//
//  MLContactsViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface MLContactsViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) IBOutlet NSTableView *contactsTable;



// methods requied for XMPP accont to call back 
-(void) showConnecting:(NSDictionary*) info;
-(void) updateConnecting:(NSDictionary*) info;
-(void) hideConnecting:(NSDictionary*) info;

-(void) clearContactsForAccount: (NSString*) accountNo;

-(void) addOnlineUser:(NSDictionary*) user;
-(void) removeOnlineUser:(NSDictionary*) user;

@end
