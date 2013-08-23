//
//  MLContactCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/7/13.
//
//

#import "MLContactCell.h"

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
	_statusOrb = [[UIImageView alloc] initWithFrame:orbRectangle];
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
            _statusOrb.image=[UIImage imageNamed:@"away"];
            self.imageView.alpha=1.0f;
            break;
        }
        case kStatusOnline:
        {
            _statusOrb.image=[UIImage imageNamed:@"available"];
            self.imageView.alpha=1.0f;
            break;
        }
        case kStatusOffline:
        {
            _statusOrb.image=[UIImage imageNamed:@"offline"];
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
//    self.textLabel.text=nil;
//    self.detailTextLabel.text=nil;
//    self.imageView.image=nil; 
//    self.badgeColor= [UIColor clearColor];
//    self.badgeHighlightedColor=[UIColor clearColor];
//    self.badgeText=nil;
//    self.imageView.image=[UIImage imageNamed:@"noicon"];
}


@end
