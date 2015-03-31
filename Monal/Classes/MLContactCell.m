//
//  MLContactCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/7/13.
//
//

#import "MLContactCell.h"
#import "MLConstants.h"

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
    self.badgeColor=[UIColor darkGrayColor];
    self.badgeHighlightedColor=[UIColor whiteColor];
    self.badgeText=[NSString stringWithFormat:@"%d", _count];
    }
    else
    {
        self.badgeColor= [UIColor clearColor];
        self.badgeHighlightedColor=[UIColor clearColor];
        self.badgeText=nil; 
    }
    
    
}


@end
