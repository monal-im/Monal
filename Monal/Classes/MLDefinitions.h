//
//  MLDefinitions.h
//  Monal
//
//  Created by Friedrich Altheide on 06.03.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#ifndef MLDefinitions_h
#define MLDefinitions_h

#if defined(IS_ALPHA) || defined(DEBUG)
    #define unreachable() { \
        DDLogWarn(@"unreachable: %s %d %s", __FILE__, __LINE__, __func__); \
        NSAssert(NO, @"unreachable"); \
    }
#else
    #define unreachable() { \
        DDLogWarn(@"unreachable: %s %d %s", __FILE__, __LINE__, __func__); \
    }
#endif


#endif /* MLDefinitions_h */
