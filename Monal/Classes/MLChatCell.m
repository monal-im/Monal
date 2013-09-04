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


+ (MLChatCell* )sharedInstance
{
    static dispatch_once_t once;
    static MLChatCell* sharedInstance; 
    dispatch_once(&once, ^{
        sharedInstance = [[MLChatCell alloc]  init];
    
    });
    return sharedInstance;
    
}
-(id) init{
    self=[super init];
    _tempView=[[UITextView alloc] init];
    _tempView.font=[UIFont systemFontOfSize:kChatFont];
    return self;
}

+(CGFloat) heightForText:(NSString*) text inWidth:(CGFloat) width;
{
    //.75 would define the bubble size
    CGSize size = CGSizeMake(width*.75, MAXFLOAT);
//    CGSize calcSize= [text sizeWithFont:[UIFont systemFontOfSize:kChatFont] constrainedToSize:size];
//    
//    return calcSize.height+25;
    [MLChatCell sharedInstance].tempView.text=text; 
    CGSize sizeToReturn=  [[MLChatCell sharedInstance].tempView sizeThatFits:size];
    
    return sizeToReturn.height;
    
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
        _messageView.backgroundColor=[UIColor clearColor];
        //_messageView.dataDetectorTypes = UIDataDetectorTypeAll;
        
        _bubbleImage=[[UIImageView alloc] init];
        
        //this order fro Z index
        [self.contentView addSubview:_bubbleImage];
        [self.contentView addSubview:_messageView];
        
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
            
            _messageView.textColor=[UIColor whiteColor];
            buttonImage2 = [[MLImageManager sharedInstance] outboundImage];
            
        }
        else
        {
            _messageView.textColor=[UIColor blackColor];
            buttonImage2 = [[MLImageManager sharedInstance] inboundImage];
        }
        
    _bubbleImage.image=buttonImage2;
    
    }
    
    
    _messageView.frame=textLabelFrame;
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
