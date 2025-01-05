//
//  XMPPDataForm.h
//  monalxmpp
//
//  Created by Thilo Molitor on 12.10.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#ifndef XMPPDataForm_h
#define XMPPDataForm_h

#import <Foundation/Foundation.h>
#import <monalxmpp/MLXMLNode.h>

NS_ASSUME_NONNULL_BEGIN

@interface XMPPDataForm : MLXMLNode

-(id) initWithType:(NSString*) type andFormType:(NSString*) formType;
-(id) initWithType:(NSString*) type formType:(NSString*) formType andDictionary:(NSDictionary*) vars;

@property (atomic, strong) NSString* type;
@property (atomic, strong) NSString* formType;
@property (atomic, strong) NSString* _Nullable title;
@property (atomic, strong) NSString* _Nullable instructions;
-(MLXMLNode*) setFieldWithDictionary:(NSDictionary*) field;
-(MLXMLNode*) setFieldWithDictionary:(NSDictionary*) field atIndex:(NSNumber* _Nullable) index;
-(MLXMLNode*) setField:(NSString*) name withValue:(NSString*) value;
-(MLXMLNode*) setField:(NSString* _Nonnull) name withValue:(NSString* _Nonnull) value atIndex:(NSNumber* _Nullable) index;
-(MLXMLNode*) setField:(NSString*) name withType:(NSString* _Nullable) type andValue:(NSString*) value;
-(MLXMLNode*) setField:(NSString* _Nonnull) name withType:(NSString* _Nullable) type andValue:(NSString* _Nonnull) value atIndex:(NSNumber* _Nullable) index;
-(NSDictionary* _Nullable) getField:(NSString*) name;
-(NSDictionary* _Nullable) getField:(NSString* _Nonnull) name atIndex:(NSNumber* _Nullable) index;
-(void) removeField:(NSString*) name;
-(void) removeField:(NSString* _Nonnull) name atIndex:(NSNumber* _Nullable) index;
@property (strong, readonly) NSString* description;

//*** NSMutableArray interface (not complete, only indexed subscript access methods supported)

-(id) objectAtIndexedSubscript:(NSInteger) idx;
-(void) setObject:(id _Nullable) obj atIndexedSubscript:(NSInteger) idx;

//*** NSMutableDictionary interface (not complete, but nearly complete)
//for multi-item forms all of these methods will operate on the first item only, with one exception:
//count will return the count of items for multi-item forms

//will return the count of items for a multi-item form
@property(readonly) NSUInteger count;
@property(readonly, copy) NSArray* allKeys;
@property(readonly, copy) NSArray* allValues;
-(id _Nullable) objectForKeyedSubscript:(NSString*) key;
-(void) setObject:(id _Nullable) obj forKeyedSubscript:(NSString*) key;
//for multi-item forms it will only return the list of var names of the first item
//(as according to XEP-0004 all items should have the same set of field nodes --> this should contain all var names possible in any item)
-(NSArray*) allKeys;
-(NSArray*) allValues;
-(NSArray*) allKeysForObject:(id) anObject;
-(id) valueForKey:(NSString*) key;
-(id) objectForKey:(NSString*) key;
-(void) removeObjectForKey:(NSString*) key;
-(void) removeAllObjects;
-(void) removeObjectsForKeys:(NSArray*) keyArray;
-(void) setObject:(NSString*) value forKey:(NSString*) key;
-(void) setValue:(NSString* _Nullable) value forKey:(NSString*) key;
-(void) addEntriesFromDictionary:(NSDictionary*) vars;
-(void) setDictionary:(NSDictionary*) vars;

@end

NS_ASSUME_NONNULL_END

#endif /* XMPPDataForm_h */
