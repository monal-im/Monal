//
//  MLContactCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/7/13.
//
//

#import "DDBadgeViewCell.h"



typedef enum {
    kStatusOnline=1,
    kStatusOffline,
    kStatusAway
} statusType;

@interface MLContactCell : DDBadgeViewCell
{
    UIView* _statusOrb;
}

@property (nonatomic, assign) NSInteger status;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign) NSInteger accountNo;
@property (nonatomic, strong) NSString* username;

@end
