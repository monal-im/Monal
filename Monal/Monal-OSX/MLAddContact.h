//
//  MLAddContact.h
//  Monal
//
//  Created by Anurodh Pokharel on 11/18/15.
//  Copyright © 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface MLAddContact : NSViewController

@property  (nonatomic, weak) IBOutlet NSComboBox *accounts;
@property  (nonatomic, weak) IBOutlet NSTextField *contactName;

-(IBAction)add:(id)sender;

@end
