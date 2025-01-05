//
//  MLBaseCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/24/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/MLMessage.h>

#define kDefaultTextHeight 20
#define kDefaultTextOffset 5

#define kSending NSLocalizedString(@"Sending...", @"")
#define kSent LocalizationNotNeeded(@"")
#define kReceived LocalizationNotNeeded(@"✓")
#define kDisplayed LocalizationNotNeeded(@"✓✓")


@interface MLBaseCell : UITableViewCell

-(id) init;

@property (nonatomic, assign) BOOL outBound;
@property (nonatomic, assign) BOOL MUC;

@property (nonatomic, strong) IBOutlet UILabel* name;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *nameHeight;

@property (nonatomic, strong) IBOutlet UILabel* date;
@property (nonatomic, strong) IBOutlet UILabel* messageBody;
@property (nonatomic, strong) IBOutlet UILabel* messageStatus;
@property (nonatomic, strong) IBOutlet UILabel* dividerDate;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *dividerHeight;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *bubbleTop;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *dayTop;

@property (nonatomic, strong) NSString* link;
@property (nonatomic, strong) IBOutlet UIView* bubbleView;

@property (nonatomic, weak) IBOutlet UIImageView *bubbleImage;
@property (nonatomic, weak) IBOutlet UIImageView *lockImage;

@property (nonatomic, assign) BOOL deliveryFailed;
@property (nonatomic, strong) IBOutlet UIButton* retry;
@property (nonatomic, strong) NSNumber* messageHistoryId;
@property (nonatomic, weak) UIViewController *parent;

/**
 Updates ths cells spacing and display
 @param newSender determines if the sender of this cell
 is the same as the prior cell's sender
 **/
-(void) updateCellWithNewSender:(BOOL) newSender;

-(void) initCell:(MLMessage*) message;

@end
