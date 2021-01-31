//
//  MLFileTransferFileViewController.h
//  Monal
//
//  Created by Jim Tsai(poormusic2001@gmail.com) on 2020/12/28.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <QuickLook/QuickLook.h>
#import <QuickLook/QLPreviewItem.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLFileTransferFileViewController : QLPreviewController <QLPreviewControllerDataSource,QLPreviewControllerDelegate>
@property (nonatomic) NSString *fileUrlStr;
@property (nonatomic) NSString *mimeType;
@property (nonatomic) NSString *fileName;
@property (nonatomic) NSString *fileEncodeName;
@end

NS_ASSUME_NONNULL_END
