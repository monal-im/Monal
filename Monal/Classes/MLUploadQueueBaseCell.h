//
//  MLUploadQueueBaseCell.h
//  Monal
//
//  Created by Jan on 15.04.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MLUploadQueueCellDelegate
-(void) notifyUploadQueueRemoval:(NSUInteger)index;
@end

@interface MLUploadQueueBaseCell : UICollectionViewCell
@property (nonatomic) NSUInteger index;
@property (weak, nonatomic) id <MLUploadQueueCellDelegate> uploadQueueDelegate;
@property (weak, nonatomic) IBOutlet UIButton* closeButton;

-(IBAction) closeButtonAction;
@end

NS_ASSUME_NONNULL_END
