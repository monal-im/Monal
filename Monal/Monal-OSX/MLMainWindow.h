//
//  MLMainWindow.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface MLMainWindow : NSWindowController <NSUserNotificationCenterDelegate>

@property (nonatomic, strong) IBOutlet NSTextField *contactNameField;

/**
 Allows  the window to know what contact is currently selected
 */
-(void) updateCurrentContact:(NSDictionary *) contact;


@end
