//
//  MLLogFileManager.h
//  monalxmpp
//
//  Created by Thilo Molitor on 21.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLLogFileManager : DDLogFileManagerDefault

-(instancetype) initWithLogsDirectory:(NSString* _Nullable) dir;
-(NSString*) newLogFileName;
-(BOOL) isLogFile:(NSString*) fileName;

@end

NS_ASSUME_NONNULL_END
