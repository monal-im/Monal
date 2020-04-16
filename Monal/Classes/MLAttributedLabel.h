//
//  MLAttributedLabel.h
//  Monal
//
//  Created by Friedrich Altheide on 01.04.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface MLAttributedLabel : UILabel

@property (nonatomic, strong) NSAttributedString* localAttributedText;

-(void) setText:(NSString*) text;
-(void) setAttributedText: (NSAttributedString*) attributedText;
-(NSAttributedString*) attributedText;
-(NSAttributedString*) originalAttributedText;
@end
