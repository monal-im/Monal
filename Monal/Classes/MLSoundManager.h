//
//  MLSoundManager.h
//  Monal
//
//  Created by 阿栋 on 3/6/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MLContact;

@interface MLSoundManager : NSObject


@property (nonatomic, strong) NSString* _Nullable selectedSound;


+(MLSoundManager* _Nonnull) sharedInstance;
- (void)saveSoundData:(NSData* _Nullable)data;
- (void)deleteSoundData;
- (NSString *)loadSoundURL;

@end

NS_ASSUME_NONNULL_END
