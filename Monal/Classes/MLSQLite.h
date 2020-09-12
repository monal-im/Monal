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

-(NSObject*) executeScalar:(NSString*) query;
-(NSObject*) executeScalar:(NSString*) query andArguments:(NSArray*) args;

-(NSMutableArray*) executeReader:(NSString*) query;
-(NSMutableArray*) executeReader:(NSString*) query andArguments:(NSArray*) args;

-(BOOL) executeNonQuery:(NSString*) query;
-(BOOL) executeNonQuery:(NSString*) query andArguments:(NSArray *) args;

-(NSNumber*) lastInsertId;

@end

NS_ASSUME_NONNULL_END
