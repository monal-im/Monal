//
//  protocol.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/18/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "protocol.h"




@implementation protocol

@synthesize loggedin; 
@synthesize  accountNumber; 

@synthesize account; 
@synthesize domain; 
@synthesize ownName; 

@synthesize  presenceFlag;
@synthesize messagesFlag;
@synthesize streamError; 
@synthesize  statusMessage; 

-(id)init:(NSString*) theserver:(unsigned short) theport:(NSString*) theaccount: (NSString*) theresource:(NSString*) thedomain: (BOOL) SSLsetting : (DataLayer*) thedb:(NSString*) accountNo:(NSString*) tempPass 
{}
-(bool) connect{}
-(void) disconnect{}

#pragma mark  communication
//threads
-(void) listener{}
-(bool) keepAlive{}

-(bool) talk: (NSString*) xmpprequest{}

-(NSMutableData*) readData{}

#pragma mark  actions
-(bool) login{}

-(NSInteger) getBuddies{}
-(bool) message:(NSString*) to:(NSString*) content:(BOOL) group{}


//presence functions
-(NSInteger) setStatus:(NSString*) status{}
-(NSInteger) setAway{}
-(NSInteger) setAvailable{}
-(NSInteger) setInvisible{}

//buddy list management commands
-(bool) removeBuddy:(NSString*) buddy{} 
-(bool) addBuddy:(NSString*) buddy{} 
-(void) getVcard:(NSString*) buddy{}

-(bool)sendAuthorized:(NSString*) buddy{}
-(bool)sendDenied:(NSString*) buddy{} 



#pragma mark Muc
-(void) joinMuc:(NSString*) to :(NSString*) password
{

}

-(bool) closeMuc:(NSString*) buddy
{

}

#pragma mark  Access fns


-(NSString*) getAccount{
	//NSLog([NSString stringWithFormat:@"%@@%@",account, domain]); 
	return	account;
}
-(NSString*) getServer
{
	return server;
}
-(NSString*) getResource
{
	return resource;
}

-(NSArray*) getBuddyListArray
{
	return [db onlineBuddies:accountNumber]; 
}

-(NSArray*) getBuddyListAdded
{
	return [db newBuddies:accountNumber]; 
}

-(NSArray*) getBuddyListRemoved
{
	return [db removedBuddies:accountNumber]; 
}

-(NSArray*) getBuddyListUpdated
{
	return [db updatedBuddies:accountNumber]; 
}

-(NSArray*) getMessagesIn
{
	return [db unreadMessages:accountNumber];
}


-(NSArray*) getRoster
{
	//[self getBuddies];
	//return roster;
}

-(void) setPriority:(int) val
{
}

-(void) buddyListUpdateRead
{
	[db markBuddiesRead:accountNumber];

}




-(BOOL) isInRemove:(NSString*) name
{

	
	
	return [db isBuddyRemoved:name :accountNumber ]; 
}


-(BOOL) isInAdd:(NSString*) name
{
	
	return [db isBuddyAdded:name :accountNumber ]; 
}





#pragma mark  Bae64


- (NSString *)base64Encoding:(NSString*) string
{
	char encodingTable[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	
	
	if ([string length] == 0)
		return @"";
	
    char *characters = malloc((([string length] + 2) / 3) * 4);
	if (characters == NULL)
		return nil;
	NSUInteger length = 0;
	
	NSUInteger i = 0;
	while (i < [string length])
	{
		char buffer[3] = {0,0,0};
		short bufferLength = 0;
		while (bufferLength < 3 && i < [string length])
			buffer[bufferLength++] = ((char *)[string cStringUsingEncoding: NSASCIIStringEncoding])[i++];
		
		//  Encode the bytes in the buffer to four characters, including padding "=" characters if necessary.
		characters[length++] = encodingTable[(buffer[0] & 0xFC) >> 2];
		characters[length++] = encodingTable[((buffer[0] & 0x03) << 4) | ((buffer[1] & 0xF0) >> 4)];
		if (bufferLength > 1)
			characters[length++] = encodingTable[((buffer[1] & 0x0F) << 2) | ((buffer[2] & 0xC0) >> 6)];
		else characters[length++] = '=';
		if (bufferLength > 2)
			characters[length++] = encodingTable[buffer[2] & 0x3F];
		else characters[length++] = '=';	
	}
	
	return [[NSString alloc] initWithBytesNoCopy:characters length:length encoding:NSASCIIStringEncoding freeWhenDone:YES];
}		



- (NSData*) dataWithBase64EncodedString:(NSString *)string
{
	char encodingTable[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	
	if (string == nil)
		[NSException raise:NSInvalidArgumentException format:nil];
	if ([string length] == 0)
		return [NSData data];
	
	static char *decodingTable = NULL;
	if (decodingTable == NULL)
	{
		decodingTable = malloc(256);
		if (decodingTable == NULL)
			return nil;
		memset(decodingTable, CHAR_MAX, 256);
		NSUInteger i;
		for (i = 0; i < 64; i++)
			decodingTable[(short)encodingTable[i]] = i;
	}
	
	const char *characters = [string cStringUsingEncoding:NSASCIIStringEncoding];
	if (characters == NULL)     //  Not an ASCII string!
		return nil;
	char *bytes = malloc((([string length] + 3) / 4) * 3);
	if (bytes == NULL)
		return nil;
	NSUInteger length = 0;
	
	NSUInteger i = 0;
	while (YES)
	{
		char buffer[4];
		short bufferLength;
		for (bufferLength = 0; bufferLength < 4; i++)
		{
			if (characters[i] == '\0')
				break;
			if (isspace(characters[i]) || characters[i] == '=')
				continue;
			buffer[bufferLength] = decodingTable[(short)characters[i]];
			if (buffer[bufferLength++] == CHAR_MAX)      //  Illegal character!
			{
				free(bytes);
				return nil;
			}
		}
		
		if (bufferLength == 0)
			break;
		if (bufferLength == 1)      //  At least two characters are needed to produce one byte!
		{
			free(bytes);
			return nil;
		}
		
		//  Decode the characters in the buffer to bytes.
		bytes[length++] = (buffer[0] << 2) | (buffer[1] >> 4);
		if (bufferLength > 2)
			bytes[length++] = (buffer[1] << 4) | (buffer[2] >> 2);
		if (bufferLength > 3)
			bytes[length++] = (buffer[2] << 6) | buffer[3];
	}
	
	realloc(bytes, length);
	return [NSData dataWithBytesNoCopy:bytes length:length];
}


#pragma mark MD5

- (NSData *) MD5:(NSString*)string {

    const char *cStr = [string UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, strlen(cStr), result);
   /* NSString* toreturn= [NSString stringWithFormat: @"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
            result[0], result[1], result[2], result[3],
            result[4], result[5], result[6], result[7],
            result[8], result[9], result[10], result[11],
            result[12], result[13], result[14], result[15]];
    
     debug_NSLog(@" hash: %@ => %@",string, toreturn );
    */
    
    int size=sizeof(unsigned char)*CC_MD5_DIGEST_LENGTH; 
    debug_NSLog(@" hash: %s size:%d", result,size);
    
    NSData* data =[[NSData  alloc ] initWithBytes: (const void *)result length:size];
    
    
    return data;
}

- (NSData *) DataMD5:(NSData*)datain {
    
    const char *cStr = [datain bytes];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, strlen(cStr), result);
    /* NSString* toreturn= [NSString stringWithFormat: @"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
     result[0], result[1], result[2], result[3],
     result[4], result[5], result[6], result[7],
     result[8], result[9], result[10], result[11],
     result[12], result[13], result[14], result[15]];
     
     debug_NSLog(@" hash: %@ => %@",string, toreturn );
     */
    
    NSData* data =[NSData dataWithBytes:result length:16];
    
    
    return data;
}



- (NSString *) MD5_16:(NSString*)string {
	const char *concat_str = [string UTF8String];
	unsigned char result[CC_MD5_DIGEST_LENGTH];
	CC_MD5(concat_str, strlen(concat_str), result);
	
	NSMutableString *hash = [NSMutableString string];
	for (int i = 0; i < 16; i++)
		[hash appendFormat:@"%c", result[i]];
	
      debug_NSLog(@" hash: %@ => %@",string, hash );

	return hash;
}



- (NSString *)hexadecimalString:(NSData*) data
{
    /* Returns hexadecimal string of NSData. Empty string if data is empty.   */
    
    const unsigned char *dataBuffer = (const unsigned char *)[data bytes];
    
    if (!dataBuffer)
        return [NSString string];
    
    NSUInteger          dataLength  = [data length];
    NSMutableString     *hexString  = [NSMutableString stringWithCapacity:(dataLength * 2)];
    
    for (int i = 0; i < dataLength; ++i)
        [hexString appendString:[NSString stringWithFormat:@"%02x", (unsigned long)dataBuffer[i]]];
    
    return [NSString stringWithString:hexString];
}


@end
 
