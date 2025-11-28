//
//  MLReactionsEntry.h
//  monalxmpp
//
//  Created by Thilo Molitor on 08.12.25.
//  Copyright © 2025 monal-im.org. All rights reserved.
//

#ifndef MLReactionsEntry_h
#define MLReactionsEntry_h

NS_ASSUME_NONNULL_BEGIN

@protocol MLContactProtocol;
@class MLMessage;

@interface MLReactionsEntry : NSObject

-(instancetype) initWithDictionary:(NSDictionary*) dict;

@property (nonatomic, readonly) NSNumber* historyId;
@property (nonatomic, readonly) NSString* _Nullable jid;
@property (nonatomic, readonly) NSString* _Nullable occupantId;
@property (nonatomic, readonly) NSString* _Nullable mucNick;
@property (nonatomic, readonly) NSSet<NSString*>* reactions;
@property (nonatomic, readonly) NSDate* timestamp;
@property (nonatomic, readonly) MLMessage* message;
@property (nonatomic, readonly) id<MLContactProtocol> contact;

@property (readonly) NSString* id;     //for Identifiable protocol

@end

NS_ASSUME_NONNULL_END

#endif /* MLReactionsEntry_h */
