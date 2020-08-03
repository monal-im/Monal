//
//  MLSQLite.h
//  Monal
//
//  Created by Thilo Molitor on 31.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLSQLite : NSObject

+(id) sharedInstanceForFile:(NSString*) dbFile;
-(void) beginWriteTransaction;
-(void) endWriteTransaction;
-(NSObject*) executeScalar:(NSString*) query andArguments:(NSArray*) args;
-(NSMutableArray*) executeReader:(NSString*) query andArguments:(NSArray*) args;
-(BOOL) executeNonQuery:(NSString*) query andArguments:(NSArray *) args;
-(void) executeScalar:(NSString*) query withCompletion:(void (^)(NSObject*)) completion;
-(void) executeReader:(NSString*) query withCompletion:(void (^)(NSMutableArray*)) completion;
-(void) executeNonQuery:(NSString*) query withCompletion:(void (^)(BOOL)) completion;
-(void) executeScalar:(NSString*) query andArguments:(NSArray*) args withCompletion:(void (^)(NSObject*)) completion;
-(void) executeReader:(NSString*) query andArguments:(NSArray*) args withCompletion:(void (^)(NSMutableArray*)) completion;
-(void) executeNonQuery:(NSString*) query andArguments:(NSArray*) args  withCompletion:(void (^)(BOOL)) completion;
-(NSNumber*) lastInsertId;

@end

NS_ASSUME_NONNULL_END
