//
//  MLChatCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/20/13.
//
//

#import "MLChatCell.h"
#import "MLImageManager.h"


#define kChatFont 15.0f


@implementation MLChatCell



+(CGFloat) heightForText:(NSString*) text inWidth:(CGFloat) width;
{
    //.75 would define the bubble size
    CGSize size = CGSizeMake(width*.75 -10 , MAXFLOAT);
    CGSize calcSize= [text sizeWithFont:[UIFont systemFontOfSize:kChatFont] constrainedToSize:size lineBreakMode:NSLineBreakByWordWrapping];
    return calcSize.height+5+5;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
       
        self.textLabel.font=[UIFont systemFontOfSize:kChatFont];
        self.textLabel.backgroundColor=[UIColor clearColor];
        self.textLabel.lineBreakMode=NSLineBreakByWordWrapping;
        self.textLabel.numberOfLines=0; 
        
        self.name = [[UILabel alloc] init];
       
        _bubbleImage=[[UIImageView alloc] init];
        //this order for Z index
        [self.contentView insertSubview:_bubbleImage belowSubview:self.textLabel];
       
        [self.contentView addSubview:self.name];
        
    }
    return self;
}

- (void)layoutSubviews
{
    
    [super layoutSubviews];  //The default implementation of the layoutSubviews
    CGRect textLabelFrame = self.contentView.frame;
    textLabelFrame.size.width=(textLabelFrame.size.width*.75);
    UIImage *buttonImage2 ;
    if(_outBound)
    {
        textLabelFrame.origin.x= self.contentView.frame.size.width-textLabelFrame.size.width;
        textLabelFrame.size.width-=10;
        
    }
    else
    {
        textLabelFrame.origin.x+=10;
    }
    
    if(!_bubbleImage.image)
    {
        
        if(_outBound)
        {
            
            self.textLabel.textColor=[UIColor whiteColor];
            buttonImage2 = [[MLImageManager sharedInstance] outboundImage];
            
        }
        else
        {
            self.textLabel.textColor=[UIColor blackColor];
            buttonImage2 = [[MLImageManager sharedInstance] inboundImage];
        }
        
    _bubbleImage.image=buttonImage2;
    
    }
    
    CGRect finaltextlabelFrame = textLabelFrame;
    finaltextlabelFrame.origin.x+=5;
    finaltextlabelFrame.size.width-=10;
   
    
    self.textLabel.frame=finaltextlabelFrame;
    _bubbleImage.frame=textLabelFrame;
    
    
}

-(void)prepareForReuse
{
    [super prepareForReuse];
//    _messageView.text=nil;
//    _outBound=NO;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];
    
    // Configure the view for the selected state
}

@end
