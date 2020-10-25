//
//  MLPush.m
//  Monal
//
//  Created by Anurodh Pokharel on 9/16/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLPush.h"
#import "MLXMPPManager.h"




@implementation MLPush


+(NSString*) stringFromToken:(NSData*) tokenIn
{
    unsigned char* tokenBytes = (unsigned char*)[tokenIn bytes];
    NSMutableString* token = [[NSMutableString alloc] init];
    NSInteger counter = 0;
    while(counter < tokenIn.length)
    {
        [token appendString:[NSString stringWithFormat:@"%02x", (unsigned char)tokenBytes[counter]]];
        counter++;
    }
    return token;
}

+(NSDictionary*) pushServer
{
    if (@available(iOS 13.0, *))        // for ios 13 onwards
        return @{
            @"jid": @"ios13push.monal.im",
            @"url": @"https://ios13push.monal.im:5281/push_appserver"
        };
    else                                // for ios 12
        return @{
            @"jid": @"push.monal.im",
            @"url": @"https://push.monal.im:5281/push_appserver"
        };
}

-(void) postToPushServer:(NSString*) token
{
#ifndef TARGET_IS_EXTENSION
    NSString* node = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    NSString* post = [NSString stringWithFormat:@"type=apns&node=%@&token=%@",
        [node stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]],
        [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]
    ];
    NSData* postData = [post dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    NSString* postLength = [NSString stringWithFormat:@"%luld", [postData length]];
    
    //this is the hardcoded push api endpoint
    NSMutableURLRequest* request = [[NSMutableURLRequest alloc] init];
    [request setURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/register", [MLPush pushServer][@"url"]]]];
    [request setHTTPMethod:@"POST"];
    [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:postData];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSHTTPURLResponse *httpresponse= (NSHTTPURLResponse *) response;
            if(!error && httpresponse.statusCode<400)
            {
                DDLogInfo(@"connection to push api successful");
                NSString *responseBody = [[NSString alloc] initWithData:data  encoding:NSUTF8StringEncoding];
                DDLogInfo(@"push api returned: %@", responseBody);
                NSArray *responseParts=[responseBody componentsSeparatedByString:@"\n"];
                if(responseParts.count>0)
                {
                    if([responseParts[0] isEqualToString:@"OK"] && [responseParts count]==3)
                    {
                        DDLogInfo(@"push api: node='%@', secret='%@'", responseParts[1], responseParts[2]);
                        [[MLXMPPManager sharedInstance] setPushNode:responseParts[1] andSecret:responseParts[2]];
                    }
                    else
                    {
                        DDLogError(@"push api returned invalid data: %@", [responseParts componentsJoinedByString: @" | "]);
                        //this will use the cached values in defaultsDB, if possible
                        [[MLXMPPManager sharedInstance] setPushNode:nil andSecret:nil];
                    }
                }
                else
                {
                    DDLogError(@"push api could  not be broken into parts");
                    //this will use the cached values in defaultsDB, if possible
                    [[MLXMPPManager sharedInstance] setPushNode:nil andSecret:nil];
                }
            }
            else
            {
                DDLogError(@"connection to push api NOT successful");
                //this will use the cached values in defaultsDB, if possible
                [[MLXMPPManager sharedInstance] setPushNode:nil andSecret:nil];
            }
            
        }] resume];
    });
#endif
}


-(void) unregisterPush
{
#ifndef TARGET_IS_EXTENSION
    NSString* node = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    
    NSString* post = [NSString stringWithFormat:@"type=apns&node=%@", [node stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    NSData* postData = [post dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    NSString* postLength = [NSString stringWithFormat:@"%luld",[postData length]];
    
    NSMutableURLRequest* request = [[NSMutableURLRequest alloc] init];
    [request setURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/v1/unregister", [MLPush pushServer][@"url"]]]];
    [request setHTTPMethod:@"POST"];
    [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:postData];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSHTTPURLResponse *httpresponse = (NSHTTPURLResponse*)response;
            if(!error && httpresponse.statusCode<400)
            {
                DDLogInfo(@"connection to push api successful");
                NSString* responseBody = [[NSString alloc] initWithData:data  encoding:NSUTF8StringEncoding];
                DDLogInfo(@"push api returned: %@", responseBody);
                NSArray* responseParts=[responseBody componentsSeparatedByString:@"\n"];
                if(responseParts.count>0)
                {
                    if([responseParts[0] isEqualToString:@"OK"] )
                        DDLogInfo(@"push api: unregistered");
                    else
                        DDLogError(@" push api returned invalid data: %@", [responseParts componentsJoinedByString: @" | "]);
                }
                else
                    DDLogError(@"push api could  not be broken into parts");
            }
            else
                DDLogError(@" connection to push api NOT successful");
        }] resume];
    });
#endif
}



/**
 This is duplicated hard coded code intended to be removed later after most users are on ios 13
 */
-(void) unregisterVOIPPush
{
    #ifndef TARGET_IS_EXTENSION
    NSString *node = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    
    NSString *post = [NSString stringWithFormat:@"type=apns&node=%@", [node stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    NSData *postData = [post dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    NSString *postLength = [NSString stringWithFormat:@"%luld",[postData length]];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    //this is the hardcoded push api endpoint
    NSString *path =[NSString stringWithFormat:@"https://push.monal.im:5281/push_appserver/v1/unregister"];
    [request setURL:[NSURL URLWithString:path]];
    [request setHTTPMethod:@"POST"];
    [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:postData];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            
            NSHTTPURLResponse *httpresponse= (NSHTTPURLResponse *) response;
            
            if(!error && httpresponse.statusCode<400)
            {
                DDLogInfo(@"connection to push api successful");
                
                NSString *responseBody = [[NSString alloc] initWithData:data  encoding:NSUTF8StringEncoding];
                DDLogInfo(@"push api returned: %@", responseBody);
                NSArray *responseParts=[responseBody componentsSeparatedByString:@"\n"];
                if(responseParts.count>0){
                    if([responseParts[0] isEqualToString:@"OK"] )
                    {
                        DDLogInfo(@"push api: unregistered");
                    }
                    else {
                        DDLogError(@" push api returned invalid data: %@", [responseParts componentsJoinedByString: @" | "]);
                    }
                } else {
                    DDLogError(@"push api could  not be broken into parts");
                }
                
            } else
            {
                DDLogError(@" connection to push api NOT successful");
            }
            
        }] resume];
    });
#endif
}
@end
