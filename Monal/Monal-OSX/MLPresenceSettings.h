//
//  MLPresenceSettings.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/29/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MASPreferencesViewController.h"

@interface MLPresenceSettings : NSViewController <MASPreferencesViewController>

@property (nonatomic, weak) IBOutlet NSTextField *status;
@property (nonatomic, weak) IBOutlet NSTextField *priority;

@property (nonatomic, weak) IBOutlet NSButton *away;
@property (nonatomic, weak) IBOutlet NSButton *visibility;


-(IBAction)toggleVisble:(id)sender;
-(IBAction)toggleAway:(id)sender;

@end
