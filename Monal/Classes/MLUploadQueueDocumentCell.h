//
//  MLUploadQueueDocumentCell.h
//  Monal
//
//  Created by Jan on 13.04.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MLUploadQueueBaseCell.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLUploadQueueDocumentCell : MLUploadQueueBaseCell

-(void) initCellWithURL:(NSURL*) url index:(NSUInteger) idx;

@property (weak, nonatomic) IBOutlet UILabel* fileName;
@property (weak, nonatomic) IBOutlet UIImageView *previewImage;

@end

NS_ASSUME_NONNULL_END
