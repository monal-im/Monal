//
//  MLUploadQueueAddCell.h
//  Monal
//
//  Created by Jan on 08.06.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// This class is only needed because we need to load an image for iOS 12 devices and SF fonts are missing there. It can be deleted as soon as iOS 12 is no longer supported by monal
@interface MLUploadQueueAddCell : UICollectionViewCell
@property (weak, nonatomic) IBOutlet UIButton* addButton;

@end

NS_ASSUME_NONNULL_END
