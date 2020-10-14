//
//  XMPPDataForm.h
//  monalxmpp
//
//  Created by tmolitor on 12.10.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#ifndef XMPPDataForm_h
#define XMPPDataForm_h

#import <Foundation/Foundation.h>
#import "MLXMLNode.h"

@interface XMPPDataForm : MLXMLNode

-(id _Nonnull) initWithType:(NSString* _Nonnull) type andFormType:(NSString* _Nonnull) formType;
-(id _Nonnull) initWithType:(NSString* _Nonnull) type formType:(NSString* _Nonnull) formType andDictionary:(NSDictionary* _Nonnull) vars;

-(void) setFieldWithDictionary:(NSDictionary* _Nonnull) field;
-(void) setField:(NSString* _Nonnull) name withValue:(NSString* _Nonnull) value;
-(void) setField:(NSString* _Nonnull) name withType:(NSString* _Nonnull) type andValue:(NSString* _Nonnull) value;
-(NSDictionary* _Nullable) getField:(NSString* _Nonnull) name;
-(void) removeField:(NSString* _Nonnull) name;

-(id _Nullable) objectForKeyedSubscript:(NSString* _Nonnull) key;
-(void) setObject:(id _Nullable) obj forKeyedSubscript:(NSString* _Nonnull) key;

@property (atomic, strong) NSString* _Nonnull type;
@property (atomic, strong) NSString* _Nonnull formType;

@end

#endif /* XMPPDataForm_h */
