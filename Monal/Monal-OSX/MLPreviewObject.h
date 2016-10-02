//
//  MLPreviewObject.h
//  Monal
//
//  Created by Anurodh Pokharel on 9/17/16.
//  Copyright © 2016 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifdef __MAC_OS_X_VERSION_MAX_ALLOWED
@import Quartz;
#else
@import QuickLook;
#endif

@interface MLPreviewObject : NSObject <QLPreviewItem>

@property(nonatomic, strong) NSURL * previewItemURL;
@property(nonatomic, strong) NSString * previewItemTitle;

@end
