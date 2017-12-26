//
//  MLChatCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/20/13.
//
//

#import "MLChatCell.h"
#import "MLImageManager.h"
#import "MLConstants.h"
@import SafariServices;


@implementation MLChatCell

-(void) updateCell
{
    [super updateCell];
    UIImage * buttonImage2;
    if(!self.bubbleImage.image)
    {
        if(self.outBound)
        {
            self.textLabel.textColor=[UIColor whiteColor];
            buttonImage2 = [[MLImageManager sharedInstance] outboundImage];
        }
        else
        {
            self.textLabel.textColor=[UIColor blackColor];
            buttonImage2 = [[MLImageManager sharedInstance] inboundImage];
        }
        self.bubbleImage.image=buttonImage2;
    }
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
        NSURL *url= [NSURL URLWithString:self.link];
        
        if ([url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"]) {
            SFSafariViewController *safariView = [[ SFSafariViewController alloc] initWithURL:url];
            [self.parent presentViewController:safariView animated:YES completion:nil];
        }
        
    }
}

-(void) copy:(id)sender {
    UIPasteboard *pboard = [UIPasteboard generalPasteboard];
    pboard.string =self.messageBody.text;
}

-(void)prepareForReuse
{
    [super prepareForReuse];
    self.messageBody.text=@"";
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];
    
    // Configure the view for the selected state
}

@end
