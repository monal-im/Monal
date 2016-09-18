//
//  MLPreviewObject.h
//  Monal
//
//  Created by Anurodh Pokharel on 9/17/16.
//  Copyright © 2016 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
@import QuickLook;
@import Quartz;

@interface MLPreviewObject : NSObject <QLPreviewItem>

@property(nonatomic, strong) NSURL * previewItemURL;
@property(nonatomic, strong) NSString * previewItemTitle;

@end
