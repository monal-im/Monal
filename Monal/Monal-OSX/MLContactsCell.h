//
//  MLContactsCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>

typedef enum {
    kStatusOnline=1,
    kStatusOffline,
    kStatusAway
} stateType ;

@interface MLContactsCell : NSTableCellView

@property (nonatomic, weak) IBOutlet NSImageView *icon;
@property (nonatomic, assign) NSInteger state;
@property (nonatomic, weak) IBOutlet NSTextField *name;
@property (nonatomic, weak) IBOutlet NSTextField *status;

@property (nonatomic, weak) IBOutlet NSImageView *statusOrb;

-(void) setOrb;

@end
