//
//  MLContactOMEMOKeys.h
//  monalxmpp
//
//  Created by Thilo Molitor on 12.12.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#ifndef MLContactOMEMOKeys_h
#define MLContactOMEMOKeys_h

NS_ASSUME_NONNULL_BEGIN

@class MLContact;

@interface MLContactOMEMOKeys : NSObject

-(instancetype) initWithContact:(MLContact*) contact;
@property(nonatomic) NSArray<NSNumber*>* devices;

@end

NS_ASSUME_NONNULL_END

#endif /* MLContactOMEMOKeys_h */
