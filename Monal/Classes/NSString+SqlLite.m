//
//  NSString+SqlLIte.m
//  Monal
//
//  Created by Anurodh Pokharel on 9/4/14.
//  Copyright (c) 2014 Monal.im. All rights reserved.
//

#import "NSString+SqlLite.h"

@implementation NSString (SqlLite)

-(NSString *) escapeForSql
{
    NSMutableString *mutable =[self mutableCopy];
    [mutable replaceOccurrencesOfString:@"'" withString:@"''" options:(NSCaseInsensitiveSearch) range:NSMakeRange(0, self.length)];
    return [mutable copy];
    
}

@end
