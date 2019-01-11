//
//  MLKeyRow.h
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 1/10/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLKeyRow : NSTableRowView
@property (nonatomic, weak) IBOutlet NSTextField *key;
@property (nonatomic, weak) IBOutlet NSTextField *deviceid;
@property (nonatomic, weak) IBOutlet NSButton *toggle;
@end

NS_ASSUME_NONNULL_END
