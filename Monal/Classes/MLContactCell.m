//
//  MLContactCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/7/13.
//
//

#import "MLContactCell.h"
#import <QuartzCore/QuartzCore.h>

@implementation MLContactCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
        self.detailTextLabel.text=nil;
        self.accessoryType = UITableViewCellAccessoryNone;
        self.imageView.alpha=1.0;
        
        self.badgeColor= [UIColor clearColor];
        self.badgeHighlightedColor=[UIColor clearColor];
        self.badgeText =nil;
        self.textLabel.textColor = [UIColor blackColor];
    }
    return self;
}

- (void)layoutSubviews
{
    
    [super layoutSubviews];  //The default implementation of the layoutSubviews
    
    CGRect orbRectangle = CGRectMake(51-13+8,(self.frame.size.height/2) -7,15,15);
	_statusOrb = [[UIView alloc] initWithFrame:orbRectangle];
    _statusOrb.layer.cornerRadius=orbRectangle.size.height/2; 
    [self.contentView addSubview: _statusOrb ];

    
    CGRect textLabelFrame = self.textLabel.frame;
    textLabelFrame.origin.x=51+13;
    textLabelFrame.size.width = self.frame.size.width-51-13-35-45;
    self.textLabel.frame = textLabelFrame;
    
    CGRect detailLabelFrame = self.detailTextLabel.frame;
    detailLabelFrame.origin.x=51+13;
    detailLabelFrame.size.width = self.frame.size.width-51-13-35-45;
    self.detailTextLabel.frame = detailLabelFrame;
    
    [self setOrb];
 
}

-(void) setOrb
{
    switch (_status) {
        case kStatusAway:
        {
            _statusOrb.layer.backgroundColor=[UIColor colorWithRed:.69f green:.23f blue:0.09 alpha:1].CGColor;
            self.imageView.alpha=1.0f;
            break;
        }
        case kStatusOnline:
        {
            _statusOrb.layer.backgroundColor=[UIColor colorWithRed:.22f green:.58f blue:0.03 alpha:1].CGColor;
            self.imageView.alpha=1.0f;
            break;
        }
        case kStatusOffline:
        {
            _statusOrb.layer.backgroundColor=[UIColor colorWithRed:.35f green:.35f blue:.35f alpha:1].CGColor;
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

-(void) setStatus:(NSInteger)status
{
    _status=status;

    if(_statusOrb) [self setOrb];
}

-(void)prepareForReuse
{
    [super prepareForReuse];
    self.textLabel.text=nil;
    self.detailTextLabel.text=nil;
    self.imageView.image=nil; 
    self.badgeColor= [UIColor clearColor];
    self.badgeHighlightedColor=[UIColor clearColor];
    self.badgeText=nil;
    self.imageView.image=[UIImage imageNamed:@"noicon"];
}


@end
