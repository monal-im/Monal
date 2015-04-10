//
//  MLContactCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/7/13.
//
//

#import "MLContactCell.h"
#import "MLConstants.h"
#import <QuartzCore/QuartzCore.h>

@interface MLContactCell()

@end

@implementation MLContactCell

-(void) awakeFromNib
{
    
}

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

-(void) showStatusText:(NSString *) text
{
    self.statusText.text=text;
    if(text)
    {
        self.centeredDisplayName.hidden=YES;
        self.displayName.hidden=NO;
        self.statusText.hidden=NO;
    }
    else {
        self.centeredDisplayName.hidden=NO;
        self.displayName.hidden=YES;
        self.statusText.hidden=YES;
    }
}

-(void) showDisplayName:(NSString *) name
{
    self.centeredDisplayName.text=name;
    self.displayName.text=name;
}

-(void) setCount:(NSInteger)count
{
    _count=count;
    
    if(_count>0)
    {
        self.badge.hidden=NO;
        [self.badge setTitle:[NSString stringWithFormat:@"%d", _count] forState:UIControlStateNormal];
    }
    else
    {
        self.badge.hidden=YES;
         [self.badge setTitle:@"" forState:UIControlStateNormal];
    }
    
    
}


@end
