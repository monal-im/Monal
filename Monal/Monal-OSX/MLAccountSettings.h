//
//  MLAccountSettings.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/29/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MASPreferencesViewController.h"

@interface MLAccountSettings : NSViewController <MASPreferencesViewController, NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, weak) IBOutlet NSTableView *accountTable;

-(void) refreshAccountList; 

-(IBAction)deleteAccount:(id)sender;

-(IBAction)showXMPP:(id)sender;
-(IBAction)showGtalk:(id)sender;




@end
