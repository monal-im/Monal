//
//  MLCrashReporter.h
//  Monal
//
//  Created by admin on 21.06.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

#ifndef MLCrashReporter_h
#define MLCrashReporter_h

@class UIViewController;

@interface MLCrashReporter : NSObject
+(void) reportPendingCrashesWithViewController:(UIViewController*) viewController;
@end

#endif /* MLCrashReporter_h */
