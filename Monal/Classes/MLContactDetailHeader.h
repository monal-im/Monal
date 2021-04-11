//
//  MLContactDetailHeader.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/29/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLContact.h"

#import <UIKit/UIKit.h>
@import QuartzCore; 

NS_ASSUME_NONNULL_BEGIN

@interface MLContactDetailHeader : UITableViewCell

-(void) loadContentForContact:(MLContact*) contact;

@end

NS_ASSUME_NONNULL_END
