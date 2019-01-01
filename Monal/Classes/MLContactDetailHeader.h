//
//  MLContactDetailHeader.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/29/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
@import QuartzCore; 

NS_ASSUME_NONNULL_BEGIN

@interface MLContactDetailHeader : UITableViewCell

@property (nonatomic,weak) IBOutlet UIImageView* buddyIconView;
@property (nonatomic,weak) IBOutlet UIImageView* background;
@property (nonatomic,weak) IBOutlet UILabel* jid;
@property (nonatomic,weak) IBOutlet UILabel* buddyStatus;

@property (nonatomic,weak) IBOutlet UIButton* muteButton;
@property (nonatomic,weak) IBOutlet UIButton* lockButton;


@end

NS_ASSUME_NONNULL_END
