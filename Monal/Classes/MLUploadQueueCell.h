//
//  MLUploadQueueDocumentCell.h
//  Monal
//
//  Created by Jan on 13.04.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MLUploadQueueCellDelegate
-(void) notifyUploadQueueRemoval:(NSUInteger)index;
@end

@interface MLUploadQueueCell : UICollectionViewCell

@property (nonatomic) NSUInteger index;
@property (weak, nonatomic) id <MLUploadQueueCellDelegate> uploadQueueDelegate;
@property (weak, nonatomic) IBOutlet UIButton* closeButton;

-(IBAction) closeButtonAction;
-(void) initCellWithPreviewImage:(UIImage* _Nullable) previewImage filename:(NSString* _Nullable) filename index:(NSUInteger) idx;

@property (weak, nonatomic) IBOutlet UILabel* fileName;
@property (weak, nonatomic) IBOutlet UIImageView *previewImage;

@end

NS_ASSUME_NONNULL_END
