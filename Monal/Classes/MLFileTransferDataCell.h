//
//  MLFileTransferDataCell.h
//  Monal
//
//  Created by Jim Tsai(poormusic2001@gmail.com) on 2020/12/7.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MLBaseCell.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, transferFileState) {
    transferCheck = 0,
    transferFileTypeNeedDowndload,
};

@interface MLFileTransferDataCell : MLBaseCell

@property (weak, nonatomic) IBOutlet UIView* fileTransferBackgroundView;
@property (weak, nonatomic) IBOutlet UIView* fileTransferBoarderView;
@property (weak, nonatomic) IBOutlet UILabel* fileTransferHint;
@property (weak, nonatomic) IBOutlet UILabel* sizeLabel;
@property (weak, nonatomic) IBOutlet UIImageView* downloadImageView;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView* loadingView;
@property (nonatomic, copy) NSNumber* messageDBId;
@property (nonatomic) transferFileState transferStatus;

-(void) initCellForMessageId:(NSNumber*) messageId andFilename:(NSString*) filename andMimeType:(NSString* _Nullable) mimeType andFileSize:(long long) fileSize;

@end

NS_ASSUME_NONNULL_END
