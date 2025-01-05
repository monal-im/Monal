//
//  MLHTTPRequest.h
//
//
//  Created by Anurodh Pokharel on 9/16/15.
//  Copyright © 2015 Anurodh Pokharel. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/MLConstants.h>

#define kGet @"GET"
#define kPost @"POST"
#define kPut @"PUT"

@interface MLHTTPRequest : NSObject <NSURLConnectionDelegate, NSURLConnectionDataDelegate>

/**
 Performs a HTTP call with the specified verb (GET,  PUT, POST etc) to a url . Completion handler will be called with the result as dictinary or array.
 @param postedData optional
 */
+ (void) sendWithVerb:(NSString *) verb  path:(NSString *)path headers:(NSDictionary *) headers withArguments:(NSDictionary *) arguments  data:(NSData *) postedData andCompletionHandler:(void (^)(NSError *error, id result)) completion;

@end
