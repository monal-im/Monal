//
//  MLCloudStorageSettings.h
//  Monal
//
//  Created by Anurodh Pokharel on 2/25/16.
//  Copyright © 2016 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MASPreferencesViewController.h"

@interface MLCloudStorageSettings : NSViewController <MASPreferencesViewController>

@property (nonatomic, weak) IBOutlet NSButton *dropBox;
@property (nonatomic, weak) IBOutlet NSButton *box;
@property (nonatomic, weak) IBOutlet NSButton *ownCloud;
@property (nonatomic, weak) IBOutlet NSProgressIndicator *progressIndicator;

-(IBAction)toggleDropBox:(id)sender;

@end
