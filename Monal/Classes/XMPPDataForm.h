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

@property (atomic, strong) NSString* _Nonnull type;
@property (atomic, strong) NSString* _Nonnull formType;
-(void) setFieldWithDictionary:(NSDictionary* _Nonnull) field;
-(void) setField:(NSString* _Nonnull) name withValue:(NSString* _Nonnull) value;
-(void) setField:(NSString* _Nonnull) name withType:(NSString* _Nonnull) type andValue:(NSString* _Nonnull) value;
-(NSDictionary* _Nullable) getField:(NSString* _Nonnull) name;
-(void) removeField:(NSString* _Nonnull) name;

//NSMutableDictionary interface (not complete, but nearly complete)
@property(readonly) NSUInteger count;
@property(readonly, copy) NSArray* allKeys;
@property(readonly, copy) NSArray* allValues;
-(id _Nullable) objectForKeyedSubscript:(NSString* _Nonnull) key;
-(void) setObject:(id _Nullable) obj forKeyedSubscript:(NSString* _Nonnull) key;
-(NSArray*) allKeys;
-(NSArray*) allValues;
-(NSArray*) allKeysForObject:(id) anObject;
-(id) valueForKey:(NSString*) key;
-(id) objectForKey:(NSString*) key;
-(void) removeObjectForKey:(NSString*) key;
-(void) removeAllObjects;
-(void) removeObjectsForKeys:(NSArray*) keyArray;
-(void) setObject:(NSString*) value forKey:(NSString*) key;
-(void) setValue:(NSString*) value forKey:(NSString*) key;
-(void) addEntriesFromDictionary:(NSDictionary*) vars;
-(void) setDictionary:(NSDictionary*) vars;

@end

#endif /* XMPPDataForm_h */
