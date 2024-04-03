//
//  MLSoundManager.h
//  Monal
//
//  Created by 阿栋 on 3/29/24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MLContact;

@interface MLSoundManager : NSObject


@property (nonatomic, strong) NSString* _Nullable selectedSound;


+ (MLSoundManager*) sharedInstance;
-(NSArray<NSString*>*) listBundledSounds;
-(NSData*) getSoundDataForSenderJID:(NSString*) senderJID andReceiverJID:(NSString*) receiverJID;
-(NSString*) getSoundNameForSenderJID:(NSString*) senderJID andReceiverJID:(NSString*) receiverJID;
-(void) saveSoundData:(NSData*) soundData forSenderJID:(NSString*) senderJID andReceiverJID:(NSString*) receiverJID WithSoundFileName:(NSString*) filename isCustomSound:(NSNumber*) isCustom;
-(NSNumber*) getIsCustomSoundForAccountId:(NSString*) accountId buddyId:(NSString*) buddyId;
-(void) deleteContactForAccountId:(NSString*) accountId;
@end

NS_ASSUME_NONNULL_END

