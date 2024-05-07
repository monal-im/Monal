//
//  MLHTTPRequest.h
//
//
//  Created by Anurodh Pokharel on 9/16/15.
//  Copyright © 2015 Anurodh Pokharel. All rights reserved.
//

#import "MLHTTPRequest.h"
#import "HelperTools.h"


@interface MLHTTPRequest ()

@end

@implementation MLHTTPRequest

+(NSData*) httpBodyForDictionary:(NSDictionary*) arguments
{
    unsigned int keyCounter = 0;
    if(arguments) {
        NSMutableString* postString =[NSMutableString new];
        for (NSString *key in arguments) {
            
            NSString *value=[arguments objectForKey:key];
            value= [value stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
            
            [postString appendString:[NSString stringWithFormat:@"%@=%@", key, value]];
            if(keyCounter < [arguments allKeys].count - 1)
            {
                [postString appendString:@"&"];
            }
            keyCounter++;
        }
        return [postString dataUsingEncoding:NSUTF8StringEncoding];
    } else
    {
        return nil;
    }
    
}


+(void) sendWithVerb:(NSString*) verb  path:(NSString*) path headers:(NSDictionary*) headers withArguments:(NSDictionary*) arguments  data:(NSData*) postedData andCompletionHandler:(void (^)(NSError *error, id result)) completion
{
    NSMutableURLRequest* theRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:path]
                                                            cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                        timeoutInterval:60.0];
    if(@available(iOS 16.1, macCatalyst 16.1, *))
        theRequest.requiresDNSSECValidation = YES;
    [theRequest setHTTPMethod:verb];
    
    NSData* dataToSubmit = postedData;
    
    [headers enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop __unused) {
        [theRequest addValue:obj forHTTPHeaderField:key];
    }];
    
    if([verb isEqualToString:kPost]||[verb isEqualToString:kPut]) {
        if(arguments && !postedData) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:arguments options:0 error:nil];
            // NSString* jsonString = [[NSString alloc] initWithBytes:[jsonData bytes] length:[jsonData length] encoding:NSUTF8StringEncoding];
            [theRequest addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
            dataToSubmit=jsonData;
        }
        else
        {
           dataToSubmit = postedData;
        }
    }
    
    DDLogVerbose(@"Calling: %@ %@", verb, path);
    
    NSURLSession* session = [HelperTools createEphemeralURLSession];
    void (^completeBlock)(NSData*,NSURLResponse*,NSError*)= ^(NSData* data,NSURLResponse* response, NSError* connectionError)
    {
        
        NSError* errorReply;
        
        if(connectionError)
        {
            errorReply = connectionError; //[NSError errorWithDomain:@"HTTP" code:0 userInfo:@{@"result":@"connection error"}];
        }
        else
        {
            NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*) response;
            if(!(httpResponse.statusCode >= 200 && httpResponse.statusCode <= 399))
            {
                errorReply = [NSError errorWithDomain:@"HTTP" code:httpResponse.statusCode userInfo:@{@"result":[NSHTTPURLResponse localizedStringForStatusCode:httpResponse.statusCode]}];
            }
        }
        completion(errorReply,data);
    };

    if(([verb isEqualToString:kPost]||[verb isEqualToString:kPut]) && dataToSubmit)
    {
        [[session uploadTaskWithRequest:theRequest fromData:dataToSubmit
                    completionHandler:completeBlock] resume];
    }
    else {
        [[session dataTaskWithRequest:theRequest
                    completionHandler:completeBlock] resume];
    }
}

@end
