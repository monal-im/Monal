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

typedef id _Nullable (^monal_sqlite_operations_t)(void);
typedef BOOL (^monal_sqlite_bool_operations_t)(void);

@interface MLSQLite : NSObject

+(id) sharedInstanceForFile:(NSString*) dbFile;

-(void) voidWriteTransaction:(monal_void_block_t) operations;
-(BOOL) boolWriteTransaction:(monal_sqlite_bool_operations_t) operations;
-(id) idWriteTransaction:(monal_sqlite_operations_t) operations;
-(void) beginWriteTransaction;
-(void) endWriteTransaction;

-(id) executeScalar:(NSString*) query;
-(id) executeScalar:(NSString*) query andArguments:(NSArray*) args;

-(NSMutableArray*) executeReader:(NSString*) query;
-(NSMutableArray*) executeReader:(NSString*) query andArguments:(NSArray*) args;

-(BOOL) executeNonQuery:(NSString*) query;
-(BOOL) executeNonQuery:(NSString*) query andArguments:(NSArray *) args;

-(NSNumber*) lastInsertId;

@end

NS_ASSUME_NONNULL_END
