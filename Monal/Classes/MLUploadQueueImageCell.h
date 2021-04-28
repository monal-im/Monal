//
//  MLUploadQueueImageCell.h
//  Monal
//
//  Created by Jan on 02.04.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "MLUploadQueueBaseCell.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLUploadQueueImageCell : MLUploadQueueBaseCell

@property (weak, nonatomic) IBOutlet UIImageView* imagePreview;

-(void) initCellWithImage:(UIImage*) image index:(NSUInteger) idx;

@end

NS_ASSUME_NONNULL_END
