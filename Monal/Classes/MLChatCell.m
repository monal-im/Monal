//
//  MLChatCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/20/13.
//
//

#import "MLChatCell.h"
#import "MLImageManager.h"


#define kChatFont 17.0f
#define kNameFont 10.0f

@implementation MLChatCell



+(CGFloat) heightForText:(NSString*) text inWidth:(CGFloat) width 
{
    //.75 would define the bubble size
    CGSize size = CGSizeMake(width*.75 -10 , MAXFLOAT);
    CGSize calcSize= [text sizeWithFont:[UIFont systemFontOfSize:kChatFont] constrainedToSize:size lineBreakMode:NSLineBreakByWordWrapping];
    return calcSize.height+5+5+5;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier andMuc:(BOOL) isMUC
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
        self.MUC=isMUC;
        self.textLabel.font=[UIFont systemFontOfSize:kChatFont];
        self.textLabel.backgroundColor=[UIColor clearColor];
        self.textLabel.lineBreakMode=NSLineBreakByWordWrapping;
        self.textLabel.numberOfLines=0; 
        
        _bubbleImage=[[UIImageView alloc] init];
        //this order for Z index
        [self.contentView insertSubview:_bubbleImage belowSubview:self.textLabel];
        
        if(self.MUC)
        {
        self.name = [[UILabel alloc] init];
        self.name.font=[UIFont systemFontOfSize:kNameFont];
        self.name .backgroundColor=[UIColor clearColor];
        self.name. textColor=[UIColor blackColor];
        self.name .lineBreakMode=NSLineBreakByTruncatingTail;
        self.name .numberOfLines=1;
        [self.contentView insertSubview:self.name aboveSubview:_bubbleImage];

        }
        
      
        
        
    }
    return self;
}

- (void)layoutSubviews
{
    
    [super layoutSubviews];  //The default implementation of the layoutSubviews
    CGRect textLabelFrame = self.contentView.frame;
   
    if(self.MUC)
    {
    textLabelFrame.origin.y+=kNameLabelHeight;
    textLabelFrame.size.height-=kNameLabelHeight;
    }
    
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
    finaltextlabelFrame.origin.x+=15;
    finaltextlabelFrame.size.width-=10;
    
    if(self.MUC)
    {
    CGRect nameLabelFrame = CGRectMake(finaltextlabelFrame.origin.x, 0, finaltextlabelFrame.size.width, kNameLabelHeight);
    self.name.frame=nameLabelFrame;
    }
    
    self.textLabel.frame=finaltextlabelFrame;
    
    CGRect bubbleFrame=textLabelFrame;
   // bubbleFrame.size.height+=5;
    _bubbleImage.frame=bubbleFrame;
    
    
}

-(BOOL) canPerformAction:(SEL)action withSender:(id)sender
{
    if(action == @selector(openlink:))
    {
       if(self.link)
           return  YES;
    }
    
    return (action == @selector(copy:)) ;
    
}


-(void) openlink: (id) sender {

    if(self.link)
    {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:self.link]];
    }
 
}

-(void) copy:(id)sender {
    UIPasteboard *pboard = [UIPasteboard generalPasteboard];
    pboard.string =self.textLabel.text;
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
