//
//  MLChatViewCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#define kCellHorizontalFixedPadding 208
#define kCellMaxWidth 285
#define kCellMinWidth 100
#define kCellMinHeight 50
#define kCellTimeLabelHeightAndOffset 25

@interface MLChatViewCell : NSTableCellView

@property (nonatomic, strong) IBOutlet NSTextView *messageText;
@property (nonatomic, strong) IBOutlet NSTextField *timeStamp;

@property (nonatomic, assign) BOOL isInbound;
@property (nonatomic, assign) NSRect messageRect;

@property (nonatomic, assign) BOOL deliveryFailed;
@property (nonatomic, strong) IBOutlet NSButton* retry;


+ (NSRect) sizeWithMessage:(NSString *)messageString forTableWidth:(CGFloat) width;

-(void) updateDisplayWithWidth:(CGFloat) width;

@end
