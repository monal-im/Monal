//
//  MLAttributedLabel.m
//  Monal
//
//  Created by Friedrich Altheide on 01.04.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLAttributedLabel.h"

@implementation MLAttributedLabel

-(void) setText:(NSString*) text {
    self.localAttributedText = nil;
    [super setText:text];
}

-(void) setAttributedText:(NSAttributedString*) attributedText {
    [super setAttributedText:attributedText];
    self.localAttributedText = attributedText;
}

-(NSAttributedString *) attributedText {
    return [super attributedText];
}

-(NSAttributedString *) originalAttributedText {
    return self.localAttributedText;
}

@end
