//
//  MLXMPPActivityItem.m
//  Monal
//
//  Created by Anurodh Pokharel on 9/5/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLXMPPActivityItem.h"

@implementation MLXMPPActivityItem




-(id) item {
    return [NSString string];
}

- (id)activityViewControllerPlaceholderItem:(UIActivityViewController *)activityViewController
{
    return [[NSString alloc] init];
}

- (nullable id)activityViewController:(UIActivityViewController *)activityViewController itemForActivityType:(nullable UIActivityType)activityType
{
    return @"<message> ?</message>";
}

- (NSString *)activityViewController:(UIActivityViewController *)activityViewController
   dataTypeIdentifierForActivityType:(UIActivityType)activityType{
    return @"im.monal.xmpp";
}

- (NSString *)activityViewController:(UIActivityViewController *)activityViewController
              subjectForActivityType:(UIActivityType)activityType
{
    return @"Encrypted message";
}
@end
