//
//  MLChatImageCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/24/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLChatCell.h"


@interface MLChatImageCell : MLChatCell

@property (nonatomic, weak) IBOutlet UIImageView *thumbnailImage;

-(void) loadImage;

@end
