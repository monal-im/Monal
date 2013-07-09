//
//  MLContactCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/7/13.
//
//

#import "DDBadgeViewCell.h"


#define kStatusOnline 1;
#define kStatusOffline 2;
#define kStatusAway 3; 

@interface MLContactCell : DDBadgeViewCell
{
    UIImageView* _statusOrb;
}

@property (nonatomic, assign) NSInteger status;
@property (nonatomic, assign) NSInteger count;

@end
