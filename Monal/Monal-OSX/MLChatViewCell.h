//
//  MLChatViewCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MLImageView.h"

#define kCellMaxWidth 285
#define kCellMinHeight 50
#define kCellHeightOffset 11
#define kCellTimeStampHeight 14
#define kCellDefaultPadding 5

@interface MLChatViewCell : NSTableCellView

@property (nonatomic, strong) IBOutlet NSTextView *messageText;
@property (nonatomic, weak) IBOutlet NSTextField *timeStamp;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *timeStampHeight;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *timeStampVeritcalOffset;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *nameHeight;
@property (nonatomic, weak) IBOutlet NSImageView *senderIcon;
@property (nonatomic, weak) IBOutlet NSImageView *lockImage;
@property (nonatomic, weak) IBOutlet NSTextField *senderName;
@property (nonatomic, weak) IBOutlet NSTextField *messageStatus;
@property (nonatomic, weak) IBOutlet NSScrollView *scrollArea;

@property (nonatomic, weak) IBOutlet MLImageView *attachmentImage;
@property (nonatomic, strong) NSData *imageData; 

@property (nonatomic, assign) BOOL isInbound;


@property (nonatomic, assign) NSRect messageRect;

@property (nonatomic, assign) BOOL deliveryFailed;
@property (nonatomic, strong) IBOutlet NSButton* retry;

@property (nonatomic, weak) IBOutlet NSLayoutConstraint *imageHeight;

@property (nonatomic, strong)  NSString* link;

+ (NSRect) sizeWithMessage:(NSString *)messageString;

-(void) updateDisplay;
-(void) loadImage:(NSString *) link WithCompletion:(void (^)(void))completion;

@end
