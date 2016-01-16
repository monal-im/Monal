//
//  MLContactDetails.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/13/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface MLContactDetails : NSViewController

@property (nonatomic,weak) IBOutlet NSImageView* buddyIconView;
@property (nonatomic,weak) IBOutlet NSImageView* protocolImage;
@property (nonatomic,weak) IBOutlet NSTextField* buddyName;
@property (nonatomic,weak) IBOutlet NSTextField* fullName;
@property (nonatomic,weak) IBOutlet NSTextField* buddyStatus;
@property (nonatomic,weak) IBOutlet NSTextField* buddyMessage;
@property (nonatomic,strong) IBOutlet NSTextView* resourcesTextView;

@property (nonatomic,strong) NSDictionary *contact;

@end
