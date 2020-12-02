//
//  MLContactCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/7/13.
//
//

#import "MLContactCell.h"
#import "MLConstants.h"
#import <QuartzCore/QuartzCore.h>

@interface MLContactCell()

@end

@implementation MLContactCell

-(void) awakeFromNib
{
    [super awakeFromNib];
}

-(void) showStatusText:(NSString *) text
{
    if(![self.statusText.text isEqualToString:text]) {
        self.statusText.text=text;
        [self setStatusTextLayout:text];
    }
}

-(void) showStatusTextItalic:(NSString *) text withItalicRange:(NSRange)italicRange
{
    UIFont* italicFont = [UIFont italicSystemFontOfSize:self.statusText.font.pointSize];
    NSMutableAttributedString *italicString = [[NSMutableAttributedString alloc] initWithString:text];
    [italicString addAttribute:NSFontAttributeName value:italicFont range:italicRange];

    if(![italicString isEqualToAttributedString:self.statusText.originalAttributedText]) {
        self.statusText.attributedText = italicString;
        [self setStatusTextLayout:text];
    }
}

-(void) setStatusTextLayout:(NSString *) text {
    if(text) {
        self.centeredDisplayName.hidden=YES;
        self.displayName.hidden=NO;
        self.statusText.hidden=NO;
    } else {
        self.centeredDisplayName.hidden=NO;
        self.displayName.hidden=YES;
        self.statusText.hidden=YES;
    }
}

-(void) showDisplayName:(NSString *) name
{
    if(![self.displayName.text isEqualToString:name]){
        self.centeredDisplayName.text=name;
        self.displayName.text=name;
    }
}

-(void) setCount:(NSInteger)count
{
    if(_count!=count) {
        _count=count;
        if(_count>0)
        {
            self.badge.hidden=NO;
            [self.badge setTitle:[NSString stringWithFormat:@"%ld", (long)_count] forState:UIControlStateNormal];
        }
    }
    else{
        if(!self.badge.hidden) { //handle initial load
            self.badge.hidden=YES;
            [self.badge setTitle:@"" forState:UIControlStateNormal];
        }
    }
}

-(void) setPinned:(BOOL) pinned
{
    self.isPinned = pinned;
    
    if(pinned) {
        self.backgroundColor =  [UIColor colorNamed:@"activeChatsPinnedColor"];
    } else {
        self.backgroundColor = UIColor.clearColor;
    }
}

@end
