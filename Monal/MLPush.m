//
//  MLPush.m
//  Monal
//
//  Created by Anurodh Pokharel on 9/16/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLPush.h"
#import "MLXMPPManager.h"
#import "DDLog.h"

static const int ddLogLevel = LOG_LEVEL_VERBOSE;

@implementation MLPush


+(NSString *) stringFromToken:(NSData *) tokenIn {
    unsigned char *tokenBytes = (unsigned char *)[tokenIn bytes];
    
    NSMutableString *token = [[NSMutableString alloc] init];
    NSInteger counter=0;
    while(counter< tokenIn.length)
    {
        [token appendString:[NSString stringWithFormat:@"%02x", (unsigned char) tokenBytes[counter]]];
        counter++;
    }
    
    return token;
}

+ (NSString *)pushServer {
    if (@available(iOS 13.0, *)) {
        return @"ios13push.monal.im"; // for ios13 onwards
    } else {
        return @"push.monal.im";
    }
    
}

-(void) postToPushServer:(NSString *) token {
    NSString *node = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    
    NSString *post = [NSString stringWithFormat:@"type=apns&node=%@&token=%@", [node stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]],
                      [token stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    NSData *postData = [post dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    NSString *postLength = [NSString stringWithFormat:@"%luld",[postData length]];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    //this is the hardcoded push api endpoint
    
    NSString *path =[NSString stringWithFormat:@"https://%@:5281/push_appserver/v1/register", [MLPush pushServer]];
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
                    if([responseParts[0] isEqualToString:@"OK"] && [responseParts count]==3)
                    {
                        DDLogInfo(@"push api: node='%@', secret='%@'", responseParts[1], responseParts[2]);
                        [[MLXMPPManager sharedInstance] setPushNode:responseParts[1] andSecret:responseParts[2]];
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
}


@end
