//
//  MLFileTransferTextCell.m
//  Monal
//
//  Created by Jim Tsai(poormusic2001@gmail.com) on 2020/12/25.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLFileTransferTextCell.h"

@implementation MLFileTransferTextCell

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
    
    // Initialization code
    self.fileTransferBackgroundView.layer.cornerRadius = 5.0f;
    self.fileTransferBackgroundView.layer.masksToBounds = YES;
    
    self.fileTransferBoarderView.layer.cornerRadius = 5.0f;
    self.fileTransferBoarderView.layer.borderWidth = 1.3f;
    self.fileTransferBoarderView.layer.borderColor = [UIColor colorWithRed:76.0/255.0 green:155.0/255.0 blue:223.0/255.0 alpha:1.0].CGColor;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {            
    UITouch *touch = [touches anyObject];
    CGPoint touchPoint = [touch locationInView:touch.view];
        
    CGPoint insidePoint = [self.fileTransferBackgroundView convertPoint:touchPoint fromView:touch.view];
    if ([self.fileTransferBackgroundView pointInside:insidePoint withEvent:nil]) {
        [self.openFileDelegate showData:self.fileCacheUrlStr withMimeType:self.fileMimeType andFileName:self.fileName andFileEncodeName:self.fileEncodeName];
    }
}

@end
