//
//  IPC.h
//  Monal
//
//  Created by Thilo Molitor on 31.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/MLConstants.h>

#define kMonalIncomingIPC @"kMonalIncomingIPC"

NS_ASSUME_NONNULL_BEGIN

typedef void (^IPC_response_handler_t)(NSDictionary*);

@interface IPC : NSObject

+(void) initializeForProcess:(NSString*) processName;
+(id) sharedInstance;
+(void) terminate;
-(void) sendMessage:(NSString*) name withData:(NSData* _Nullable) data to:(NSString*) destination;
-(void) sendMessage:(NSString*) name withData:(NSData* _Nullable) data to:(NSString*) destination withResponseHandler:(IPC_response_handler_t _Nullable) responseHandler;
-(void) sendBroadcastMessage:(NSString*) name withData:(NSData* _Nullable) data;
-(void) sendBroadcastMessage:(NSString*) name withData:(NSData* _Nullable) data withResponseHandler:(IPC_response_handler_t _Nullable) responseHandler;
-(NSString* _Nullable) exportDB;

-(void) respondToMessage:(NSDictionary*) message withData:(NSData* _Nullable) data;

@end

NS_ASSUME_NONNULL_END
