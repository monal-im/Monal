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
    if([[NSUserDefaults standardUserDefaults] boolForKey:@"SortContacts"]==YES)
	return [db onlineBuddies:accountNumber sortedBy:@"State"];
    else
        return [db onlineBuddies:accountNumber sortedBy:@"Name"];
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


static const char _base64EncodingTable[64] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static const short _base64DecodingTable[256] = {
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -1, -1, -2, -1, -1, -2, -2,
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2,
    -1, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, 62, -2, -2, -2, 63,
    52, 53, 54, 55, 56, 57, 58, 59, 60, 61, -2, -2, -2, -2, -2, -2,
    -2,  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14,
    15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, -2, -2, -2, -2, -2,
    -2, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
    41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, -2, -2, -2, -2, -2,
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2,
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2,
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2,
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2,
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2,
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2,
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2,
    -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -2
};


- (NSString *)encodeBase64WithString:(NSString *)strData {
    return [self encodeBase64WithData:[strData dataUsingEncoding:NSUTF8StringEncoding]];
}

- (NSString *)encodeBase64WithData:(NSData *)objData {
    const unsigned char * objRawData = [objData bytes];
    char * objPointer;
    char * strResult;
    
    // Get the Raw Data length and ensure we actually have data
    int intLength = [objData length];
    if (intLength == 0) return nil;
    
    // Setup the String-based Result placeholder and pointer within that placeholder
    strResult = (char *)calloc((((intLength + 2) / 3) * 4) + 1, sizeof(char));
    objPointer = strResult;
    
    // Iterate through everything
    while (intLength > 2) { // keep going until we have less than 24 bits
        *objPointer++ = _base64EncodingTable[objRawData[0] >> 2];
        *objPointer++ = _base64EncodingTable[((objRawData[0] & 0x03) << 4) + (objRawData[1] >> 4)];
        *objPointer++ = _base64EncodingTable[((objRawData[1] & 0x0f) << 2) + (objRawData[2] >> 6)];
        *objPointer++ = _base64EncodingTable[objRawData[2] & 0x3f];
        
        // we just handled 3 octets (24 bits) of data
        objRawData += 3;
        intLength -= 3;
    }
    
    // now deal with the tail end of things
    if (intLength != 0) {
        *objPointer++ = _base64EncodingTable[objRawData[0] >> 2];
        if (intLength > 1) {
            *objPointer++ = _base64EncodingTable[((objRawData[0] & 0x03) << 4) + (objRawData[1] >> 4)];
            *objPointer++ = _base64EncodingTable[(objRawData[1] & 0x0f) << 2];
            *objPointer++ = '=';
        } else {
            *objPointer++ = _base64EncodingTable[(objRawData[0] & 0x03) << 4];
            *objPointer++ = '=';
            *objPointer++ = '=';
        }
    }
    
    // Terminate the string-based result
    *objPointer = '\0';
    
    // Return the results as an NSString object
    return [NSString stringWithCString:strResult encoding:NSASCIIStringEncoding];
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
  //  debug_NSLog(@" hash: %s size:%d", result,size);
    
    NSData* data =[[NSData  alloc ] initWithBytes: (const void *)result length:size];
    
    
    return data;
}

- (NSData *) DataMD5:(NSData*)datain {
    
    const char *cStr = [datain bytes];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, [datain length], result);
    /* NSString* toreturn= [NSString stringWithFormat: @"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
     result[0], result[1], result[2], result[3],
     result[4], result[5], result[6], result[7],
     result[8], result[9], result[10], result[11],
     result[12], result[13], result[14], result[15]];
     */
  // debug_NSLog(@"data %s hash: %s",cStr, result );
     
      int size=sizeof(unsigned char)*CC_MD5_DIGEST_LENGTH; 
    NSData* data =[NSData dataWithBytes:result length:size];
    
    
    return data;
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
 
