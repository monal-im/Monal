//
//  MLChatImageCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/24/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLBaseCell.h"

@class MLMessage;

@interface MLChatImageCell : MLBaseCell

@property (nonatomic, weak) IBOutlet UIImageView *thumbnailImage;
@property (nonatomic, weak) IBOutlet UIActivityIndicatorView *spinner;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *imageHeight;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic) MLMessage* msg;

-(void) loadImage;

@end

