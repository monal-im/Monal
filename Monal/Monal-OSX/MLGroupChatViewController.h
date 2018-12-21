//
//  MLGroupChatViewController.h
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 1/10/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface MLGroupChatViewController : NSViewController

@property  (nonatomic, weak) IBOutlet NSTextField *accountText;
@property  (nonatomic, weak) IBOutlet NSComboBox *accounts;

@property  (nonatomic, weak) IBOutlet NSTextField *room;
@property  (nonatomic, weak) IBOutlet NSTextField *host;
@property  (nonatomic, weak) IBOutlet NSTextField *nick;
@property  (nonatomic, weak) IBOutlet NSTextField *password;

@property (nonatomic, weak) IBOutlet NSButton *autoJoin;
@property (nonatomic, weak) IBOutlet NSButton *favorite;




-(IBAction)join:(id)sender;


@end
