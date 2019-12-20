//
//  MLMetaInfo.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/6/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLMetaInfo.h"

@implementation MLMetaInfo

+ (NSString * _Nullable) ogContentWithTag:(NSString *) tag inHTML:(NSString *) body
{
    NSRange titlePos = [body rangeOfString:tag];
    if(titlePos.location==NSNotFound) return nil;
    NSRange end = [body rangeOfString:@">" options:NSCaseInsensitiveSearch range:NSMakeRange(titlePos.location, body.length-titlePos.location)];
    NSString *subString = [body substringWithRange:NSMakeRange(titlePos.location, end.location-titlePos.location)];
    NSArray *parts = [subString componentsSeparatedByString:@"content="];
    NSString *text = parts.lastObject;
    if(text.length>2) {
        
        if([tag isEqualToString:@"og:image"]){
            NSArray *components = [text componentsSeparatedByString:@" "];// other attributes
            text=[components objectAtIndex:0];
        }
        
        if([text characterAtIndex:text.length-1]=='/') {
            text = [text substringWithRange:NSMakeRange(0, text.length-1)];
        }
        text= [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        int trimLength=2;//quotes
        text = [text substringWithRange:NSMakeRange(1, text.length-trimLength)];
    }
    NSString* toreturn= [text stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    return toreturn;
}

@end
