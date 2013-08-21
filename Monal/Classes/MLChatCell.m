//
//  MLChatCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/20/13.
//
//

#import "MLChatCell.h"
#import <QuartzCore/QuartzCore.h>

#define kChatFont 15.0f


@implementation MLChatCell

+(CGFloat) heightForText:(NSString*) text inWidth:(CGFloat) width;
{
    //.75 would define the bubble size
    CGSize size = CGSizeMake(width*.75, MAXFLOAT);
    CGSize calcSize= [text sizeWithFont:[UIFont systemFontOfSize:kChatFont] constrainedToSize:size lineBreakMode:NSLineBreakByWordWrapping];
    
    return calcSize.height+15;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
        _messageView=[[UITextView alloc] init];
        _messageView.scrollEnabled=NO;
        _messageView.scrollsToTop=NO;
        _messageView.editable=NO;
        _messageView.font=[UIFont systemFontOfSize:kChatFont];
        _messageView.layer.cornerRadius=5.0f;
    }
    return self;
}

- (void)layoutSubviews
{
    
    [super layoutSubviews];  //The default implementation of the layoutSubviews
    CGRect textLabelFrame = self.contentView.frame;
    textLabelFrame.size.width=textLabelFrame.size.width*.75; 


    
    if(_outBound)
    {
        
        _messageView.textColor=[UIColor whiteColor];
        _messageView.backgroundColor=[UIColor colorWithRed:0.17f green:0.53f blue:0.98f alpha:1];
        textLabelFrame.origin.x= self.contentView.frame.size.width-textLabelFrame.size.width;
        
    }
    else
    {
        _messageView.textColor=[UIColor blackColor];
        _messageView.backgroundColor=[UIColor lightGrayColor];
       
        
    }
    
    _messageView.frame=textLabelFrame;
    [self.contentView addSubview:_messageView];
    
}

-(void)prepareForReuse
{
    [super prepareForReuse];
    _messageView.text=nil;
    _outBound=NO; 
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
