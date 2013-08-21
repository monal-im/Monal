//
//  MLChatCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/20/13.
//
//

#import "MLChatCell.h"

#define kChatFont 15.0f


@implementation MLChatCell

+(CGFloat) heightForText:(NSString*) text inWidth:(CGFloat) width;
{
    CGSize size = CGSizeMake(width, MAXFLOAT);
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
    }
    return self;
}

- (void)layoutSubviews
{
    
    [super layoutSubviews];  //The default implementation of the layoutSubviews
    CGRect textLabelFrame = self.contentView.frame;

    _messageView.frame=textLabelFrame;
    [self.contentView addSubview:_messageView];
    
}

-(void)prepareForReuse
{
    [super prepareForReuse];
    _messageView.text=nil;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
