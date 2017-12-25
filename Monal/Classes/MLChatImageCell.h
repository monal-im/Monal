//
//  MLChatImageCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/24/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLBaseCell.h"


@interface MLChatImageCell : MLBaseCell
@property (nonatomic, strong) NSString* link;

@property (nonatomic, weak) IBOutlet UIImageView *thumbnailImage;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *imageHeight;


-(void) loadImageWithcompletion:(void (^)(void))completion;

@end

