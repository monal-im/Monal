//
//  MLAccountRow.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/7/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface MLAccountRow : NSTableRowView

@property (nonatomic, weak) IBOutlet NSButton *enabledCheckBox;
@property (nonatomic, weak) IBOutlet NSTextField *accountName;
@property (nonatomic, weak) IBOutlet NSImageView *accountStatus;
@property (nonatomic, strong) NSDictionary *account; 

-(void) updateWithAccountDictionary:(NSDictionary *) account;

-(IBAction)checkBoxAction:(id)sender;

@end
