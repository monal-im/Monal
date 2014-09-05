//
//  NSString+SqlLIte.h
//  Monal
//
//  Created by Anurodh Pokharel on 9/4/14.
//  Copyright (c) 2014 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (SqlLite)

/**
 escapes single quotes for sqlilite
 */
-(NSString *) escapeForSql;
@end
