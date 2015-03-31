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

@property (nonatomic, assign) NSInteger status;
@property (nonatomic, assign) NSInteger count;
@property (nonatomic, assign) NSInteger accountNo;
@property (nonatomic, strong) NSString *username;

@property (nonatomic, weak) IBOutlet UILabel *displayName;
@property (nonatomic, weak) IBOutlet UILabel *statusText;
@property (nonatomic, weak) IBOutlet UIImageView *statusOrb;
@property (nonatomic, weak) IBOutlet UIImageView *userImage;


-(void) setOrb;

@end
