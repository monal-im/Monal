//
//  MLLinkCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 10/29/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLBaseCell.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLLinkCell : MLBaseCell
@property (nonatomic, strong) IBOutlet UILabel* messageTitle;
@property (nonatomic, strong) IBOutlet UIImageView* previewImage;

@end

NS_ASSUME_NONNULL_END
