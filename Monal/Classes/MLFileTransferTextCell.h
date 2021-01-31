//
//  MLFileTransferTextCell.h
//  Monal
//
//  Created by Jim Tsai(poormusic2001@gmail.com) on 2020/12/25.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLBaseCell.h"

@protocol OpenFileDelegate

- (void)showData:(NSString*_Nonnull) fileUrlStr withMimeType:(NSString*_Nonnull) mimeType andFileName:(NSString*_Nonnull) fileName andFileEncodeName:(NSString*_Nonnull) encodeName;

@end

NS_ASSUME_NONNULL_BEGIN

@interface MLFileTransferTextCell : MLBaseCell
@property (weak, nonatomic) IBOutlet UIView *fileTransferBackgroundView;
@property (weak, nonatomic) IBOutlet UIView *fileTransferBoarderView;
@property (weak, nonatomic) IBOutlet UILabel *fileTransferHint;
@property (weak, nonatomic) IBOutlet UILabel *sizeLabel;
@property (weak, nonatomic) IBOutlet UIImageView *textFileImageView;
@property (weak, nonatomic) id <OpenFileDelegate> openFileDelegate;
@property (nonatomic) NSString *fileCacheUrlStr;
@property (nonatomic) NSString *fileMimeType;
@property (nonatomic) NSString *fileName;
@property (nonatomic) NSString *fileEncodeName;
@end

NS_ASSUME_NONNULL_END
