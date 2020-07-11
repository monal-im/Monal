//
//  HelperTools.h
//  Monal
//
//  Created by Friedrich Altheide on 08.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HelperTools : NSObject

+(NSString* _Nullable) lastInteractionFromJid:(NSString*) contactJid andAccountNo:(NSString*) accountNo;

@end

NS_ASSUME_NONNULL_END
