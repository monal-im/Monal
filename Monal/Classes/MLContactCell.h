//
//  MLContactCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/7/13.
//
//

#import "DDBadgeViewCell.h"

@interface MLContactCell : DDBadgeViewCell
{
    UIImageView* _statusOrb;
}

@property (nonatomic, assign) NSInteger status;
@end
