//
//  MLContactCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/7/13.
//
//

#import "MLContactCell.h"

@implementation MLContactCell

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
        self.detailTextLabel.text=nil;
        self.accessoryType = UITableViewCellAccessoryNone;
        self.imageView.alpha=1.0;
        
        
        self.badgeText =nil;
        self.badgeColor = [UIColor whiteColor];
        self.badgeHighlightedColor = [UIColor blueColor];
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
    
    
}



@end
