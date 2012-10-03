//
//  PasswordManager.h
//  Monal
//
//  Created by Anurodh Pokharel on 2/28/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Security/Security.h>



@interface PasswordManager : NSObject {
  __strong   NSMutableDictionary        *keychainData;
  __strong  NSMutableDictionary        *genericPasswordQuery;
	

	
}

@property (nonatomic,strong) NSMutableDictionary *keychainData;
@property (nonatomic,strong) NSMutableDictionary *genericPasswordQuery;

- (void)mySetObject:(id)inObject forKey:(id)key;
- (id)myObjectForKey:(id)key; 
- (void)resetKeychainItem;


//mine 
- (void) setPassword:(NSString*)pass; 
- (NSString*) getPassword; 
- (id)init:(NSString*) accountno; 
@end


@interface PasswordManager (PrivateMethods)


//The following two methods translate dictionaries between the format used by
// the view controller (NSString *) and the Keychain Services API:
- (NSMutableDictionary *)secItemFormatToDictionary:(NSDictionary *)dictionaryToConvert;
- (NSMutableDictionary *)dictionaryToSecItemFormat:(NSDictionary *)dictionaryToConvert;
// Method used to write data to the keychain:
- (void)writeToKeychain;

@end


