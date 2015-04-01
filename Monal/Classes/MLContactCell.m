//
//  MLContactCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/7/13.
//
//

#import "MLContactCell.h"
#import "MLConstants.h"

@interface MLContactCell()
@property (nonatomic, strong) UIImage *badge;

@end

@implementation MLContactCell

-(void) setOrb
{
    switch (_status) {
        case kStatusAway:
        {
            self.statusOrb.image=[UIImage imageNamed:@"away"];
            self.imageView.alpha=1.0f;
            break;
        }
        case kStatusOnline:
        {
            self.statusOrb.image=[UIImage imageNamed:@"available"];
            self.imageView.alpha=1.0f;
            break;
        }
        case kStatusOffline:
        {
            self.statusOrb.image=[UIImage imageNamed:@"offline"];
            self.imageView.alpha=0.5f;
            break;
        }
            
        default:
            break;
    }
}

-(void) setCount:(NSInteger)count
{
    _count=count;
    
    if(_count>0)
    {
        if(!self.badge)
        {
            self.badge =[UIImage imageNamed:@"NotificationBubble"];
            self.badge =[self.badge resizableImageWithCapInsets:UIEdgeInsetsMake(2, 5, 5, 2) resizingMode:UIImageResizingModeStretch];
            self.badgeImage.image= self.badge;
        }
        self.badgeImage.hidden=NO;
    }
    else
    {
        self.badgeImage.hidden=YES;
    }
    
    
}


@end
