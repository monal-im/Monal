//
//  MLFiletransfer.h
//  monalxmpp
//
//  Created by Thilo Molitor on 12.11.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface MLFiletransfer : NSObject

+(void) checkMimeTypeAndSizeForHistoryID:(NSNumber*) historyId withURL:(NSString*) url;
+(void) downloadFileForHistoryID:(NSNumber*) historyId withURL:(NSString*) url;

@end

NS_ASSUME_NONNULL_END
