//
//  MLInfoCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/12/13.
//
//

#import "MLInfoCell.h"
#import "MLConstants.h"


@implementation MLInfoCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
    }
    return self;
}

- (void)layoutSubviews
{
    
    [super layoutSubviews];  //The default implementation of the layoutSubviews
   
    self.contentView.backgroundColor=[UIColor darkGrayColor];
    self.textLabel.textColor=[UIColor whiteColor];
    self.textLabel.backgroundColor=[UIColor clearColor];
    self.detailTextLabel.textColor=[UIColor lightGrayColor];
    self.detailTextLabel.backgroundColor=[UIColor clearColor];
    
    
    CGRect textLabelFrame = self.textLabel.frame;
    textLabelFrame.origin.x=51+13;
    textLabelFrame.size.width = self.frame.size.width-51-13-35-45;
    self.textLabel.frame = textLabelFrame;
    
    CGRect detailLabelFrame = self.detailTextLabel.frame;
    detailLabelFrame.origin.x=51+13;
    detailLabelFrame.size.width = self.frame.size.width-51-13-35-45;
    self.detailTextLabel.frame = detailLabelFrame;
    
    
//    _Cancel=[UIButton buttonWithType:UIButtonTypeRoundedRect];
//    
//    UIImage *buttonImage2 = [[UIImage imageNamed:@"blueButton"]
//                             resizableImageWithCapInsets:UIEdgeInsetsMake(10, 10, 10, 10)];
//    UIImage *buttonImageHighlight2 = [[UIImage imageNamed:@"blueButtonHighlight"]
//                                      resizableImageWithCapInsets:UIEdgeInsetsMake(18, 18, 10, 10)];
    
//    [_Cancel setBackgroundImage:buttonImage2 forState:UIControlStateNormal];
//    [_Cancel setBackgroundImage:buttonImageHighlight2 forState:UIControlStateSelected];
//    
//
//    [_Cancel  setTitle:@"Cancel" forState:UIControlStateNormal];
//    [_Cancel setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
//    
//    _Cancel.frame=CGRectMake(textLabelFrame.origin.x+textLabelFrame.size.width+5, textLabelFrame.origin.y+5, 70, 30);
//    [self.contentView addSubview:_Cancel];
    
    if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))
       {
           [self.contentView setBackgroundColor:[UIColor darkGrayColor]];
       }
       else
    [self.contentView setBackgroundColor:[UIColor colorWithPatternImage:[UIImage imageNamed:@"debut_dark"]]];
    
}

-(void)setType:(NSString *)type
{
    _type=type;
    if([type isEqualToString:@"connect"])
       {
           //self.imageView.image=[UIImage imageNamed:@"connect"];
           _spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
           CGRect frame = _spinner.frame;
           frame.origin.x+=5;
           frame.origin.y+=2.5;
           _spinner.frame=frame; 
           [self.contentView addSubview:_spinner];
    
       }

    
}


- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
