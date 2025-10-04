//
//  SCRAM.m
//  monalxmpp
//
//  Created by Thilo Molitor on 05.08.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

#include <arpa/inet.h>

#import <Foundation/Foundation.h>
#import <monalxmpp/HelperTools.h>
#import "SCRAM.h"

@interface SCRAM ()
{
    BOOL _usingChannelBinding;
    NSString* _method;
    NSString* _username;
    NSString* _password;
    NSString* _nonce;
    NSString* _ssdpString;
    
    NSString* _clientFirstMessageBare;
    NSString* _gssHeader;
    
    NSString* _serverFirstMessage;
    uint32_t _iterationCount;
    NSData* _salt;
    
    NSString* _expectedServerSignature;
}
@end

//see these for intermediate test values:
//https://stackoverflow.com/a/32470299/3528174
//https://stackoverflow.com/a/29299946/3528174
@implementation SCRAM

//list supported mechanisms (highest security first!)
+(NSArray*) supportedMechanismsIncludingChannelBinding:(BOOL) include
{
    if(include)
        return @[@"SCRAM-SHA-512-PLUS", @"SCRAM-SHA-256-PLUS", @"SCRAM-SHA-1-PLUS", @"SCRAM-SHA-512", @"SCRAM-SHA-256", @"SCRAM-SHA-1"];
    return @[@"SCRAM-SHA-512", @"SCRAM-SHA-256", @"SCRAM-SHA-1"];
}

-(instancetype) initWithUsername:(NSString*) username password:(NSString*) password andMethod:(NSString*) method
{
    self = [super init];
    MLAssert([[[self class] supportedMechanismsIncludingChannelBinding:YES] containsObject:method], @"Unsupported SCRAM hash method!", (@{@"method": nilWrapper(method)}));
    _usingChannelBinding = [@"-PLUS" isEqualToString:[method substringFromIndex:method.length-5]];
    if(_usingChannelBinding)
        _method = [method substringWithRange:NSMakeRange(0, method.length-5)];
    else
        _method = method;
    _username = username;
    _password = [self SASLPrep:password isQuery:NO];
    if(password.length>0 && _password.length==0)
        DDLogError(@"SASLPrep failed for password, using empty password!");
    _nonce = [NSUUID UUID].UUIDString;
    _ssdpString = nil;
    _serverFirstMessageParsed = NO;
    _finishedSuccessfully = NO;
    _ssdpSupported = NO;
    return self;
}

-(void) setSSDPMechanisms:(NSArray<NSString*>*) mechanisms andChannelBindingTypes:(NSArray<NSString*>* _Nullable) cbTypes
{
    MLAssert(!_finishedSuccessfully, @"SCRAM handler finished already!");
    MLAssert(!_serverFirstMessageParsed, @"SCRAM handler already parsed server-first-message!");
    DDLogVerbose(@"Creating SDDP string: %@\n%@", mechanisms, cbTypes);
    NSMutableString* ssdpString = [NSMutableString new];
    [ssdpString appendString:[[mechanisms sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"\x1e"]];
    if(cbTypes != nil)
    {
        [ssdpString appendString:@"\x1f"];
        [ssdpString appendString:[[cbTypes sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"\x1e"]];
    }
    _ssdpString = [ssdpString copy];
    DDLogVerbose(@"SDDP string is now: %@", _ssdpString);
}

-(NSString*) clientFirstMessageWithNoMatchingChannelBindingFound:(BOOL) noMatchingChannelBindingFound andChannelBinding:(NSString* _Nullable) channelBindingType
{
    MLAssert(!_finishedSuccessfully, @"SCRAM handler finished already!");
    MLAssert(!_serverFirstMessageParsed, @"SCRAM handler already parsed server-first-message!");
    //no matching channel binding could be found, but server advertised channel-binding capability
    //--> tell the server we DON'T support channel-binding and abort the authentication later on,
    //    if the server doesn't support SSDP to sign this fact
    //NOTE: XEP-0440 makes tls-server-end-point mandatory and we support this
    //NOTE: ==> not having a match almost always means a MITM attacker tampered with the XEP-0440 list
    if(noMatchingChannelBindingFound)
        _gssHeader = @"n,,";
    //supported by us BUT NOT advertised by the server
    //--> mark this fact so that the server can abort authentication, if this isn't true
    else if(channelBindingType == nil)
        _gssHeader = @"y,,";
    //supported by us AND advertised by the server
    else
        _gssHeader = [NSString stringWithFormat:@"p=%@,,", channelBindingType];
    //the g attribute is a random grease to check if servers are rfc compliant (e.g. accept optional attributes)
    _clientFirstMessageBare = [NSString stringWithFormat:@"n=%@,r=%@,g=%@", [self quote:_username], _nonce, [NSUUID UUID].UUIDString];
    return [NSString stringWithFormat:@"%@%@", _gssHeader, _clientFirstMessageBare];
}

-(MLScramStatus) parseServerFirstMessage:(NSString*) str
{
    MLAssert(!_finishedSuccessfully, @"SCRAM handler finished already!");
    MLAssert(!_serverFirstMessageParsed, @"SCRAM handler already parsed server-first-message!");
    NSDictionary* msg = [self parseScramString:str];
    _serverFirstMessageParsed = YES;
    //server nonce MUST start with our client nonce
    if(![msg[@"r"] hasPrefix:_nonce])
        return MLScramStatusNonceError;
    //check for attributes not allowed per RFC
    for(NSString* key in msg)
        if([@"m" isEqualToString:key])
            return MLScramStatusUnsupportedMAttribute;
    _serverFirstMessage = str;
    _nonce = msg[@"r"];     //from now on use the full nonce
    _salt = [HelperTools dataWithBase64EncodedString:msg[@"s"]];
    _iterationCount = (uint32_t)[msg[@"i"] integerValue];
    //check if SSDP downgrade protection triggered, if provided
    if(msg[@"h"] != nil && _ssdpString != nil)
    {
        _ssdpSupported = YES;
        //calculate base64 encoded SSDP hash and compare it to server sent value
        NSString* ssdpHash =[HelperTools encodeBase64WithData:[self hash:[_ssdpString dataUsingEncoding:NSUTF8StringEncoding]]];
        if(![HelperTools constantTimeCompareAttackerString:msg[@"h"] withKnownString:ssdpHash])
            return MLScramStatusSSDPTriggered;
    }
    if(_iterationCount < 4096)
        return MLScramStatusIterationCountInsecure;
    return MLScramStatusServerFirstOK;
}

//see https://stackoverflow.com/a/29299946/3528174
-(NSString*) clientFinalMessageWithChannelBindingData:(NSData* _Nullable) channelBindingData
{
    MLAssert(!_finishedSuccessfully, @"SCRAM handler finished already!");
    MLAssert(_serverFirstMessageParsed, @"SCRAM handler did not parsed server-first-message yet!");
    //calculate gss header with optional channel binding data
    NSMutableData* gssHeaderWithChannelBindingData = [NSMutableData new];
    [gssHeaderWithChannelBindingData appendData:[_gssHeader dataUsingEncoding:NSUTF8StringEncoding]];
    if(_usingChannelBinding && channelBindingData != nil)
        [gssHeaderWithChannelBindingData appendData:channelBindingData];
    
    NSData* saltedPassword = [self hashPasswordWithSalt:_salt andIterationCount:_iterationCount];
    
    //calculate clientKey (e.g. HMAC(SaltedPassword, "Client Key"))
    NSData* clientKey = [self hmacForKey:saltedPassword andData:[@"Client Key" dataUsingEncoding:NSUTF8StringEncoding]];
    
    //calculate storedKey (e.g. H(ClientKey))
    NSData* storedKey = [self hash:clientKey];
    
    //calculate authMessage (e.g. client-first-message-bare + "," + server-first-message + "," + client-final-message-without-proof)
    //the x attribute is a random grease to check if servers are rfc compliant (e.g. accept optional attributes)
    NSString* clientFinalMessageWithoutProof = [NSString stringWithFormat:@"c=%@,r=%@,x=%@", [HelperTools encodeBase64WithData:gssHeaderWithChannelBindingData], _nonce, [NSUUID UUID].UUIDString];
    NSString* authMessage = [NSString stringWithFormat:@"%@,%@,%@", _clientFirstMessageBare, _serverFirstMessage, clientFinalMessageWithoutProof];
    
    //calculate clientSignature (e.g. HMAC(StoredKey, AuthMessage))
    NSData* clientSignature = [self hmacForKey:storedKey andData:[authMessage dataUsingEncoding:NSUTF8StringEncoding]];
    
    //calculate clientProof (e.g. ClientKey XOR ClientSignature)
    NSData* clientProof = [HelperTools XORData:clientKey withData:clientSignature];
    
    //calculate serverKey (e.g. HMAC(SaltedPassword, "Server Key"))
    NSData* serverKey = [self hmacForKey:saltedPassword andData:[@"Server Key" dataUsingEncoding:NSUTF8StringEncoding]];
    
    //calculate _expectedServerSignature (e.g. HMAC(ServerKey, AuthMessage))
    _expectedServerSignature = [HelperTools encodeBase64WithData:[self hmacForKey:serverKey andData:[authMessage dataUsingEncoding:NSUTF8StringEncoding]]];
    
    //return client final message
    return [NSString stringWithFormat:@"%@,p=%@", clientFinalMessageWithoutProof, [HelperTools encodeBase64WithData:clientProof]];
}

-(MLScramStatus) parseServerFinalMessage:(NSString*) str
{
    MLAssert(!_finishedSuccessfully, @"SCRAM handler finished already!");
    MLAssert(_serverFirstMessageParsed, @"SCRAM handler did not parsed server-first-message yet!");
    NSDictionary* msg = [self parseScramString:str];
    //wrong v-value
    if(![HelperTools constantTimeCompareAttackerString:msg[@"v"] withKnownString:_expectedServerSignature])
        return MLScramStatusWrongServerProof;
    //server sent a SCRAM error
    if(msg[@"e"] != nil)
    {
        DDLogError(@"SCRAM error: '%@'", msg[@"e"]);
        return MLScramStatusServerError;
    }
    //everything was successful
    _finishedSuccessfully = YES;
    return MLScramStatusServerFinalOK;
}

-(NSData*) hashPasswordWithSalt:(NSData*) salt andIterationCount:(uint32_t) iterationCount
{
    //calculate saltedPassword (e.g. Hi(Normalize(password), salt, i))
    uint32_t i = htonl(1);
    NSMutableData* salti = [NSMutableData dataWithData:salt];
    [salti appendData:[NSData dataWithBytes:&i length:sizeof(i)]];
    
    NSData* passwordData = [_password dataUsingEncoding:NSUTF8StringEncoding];
    NSData* saltedPasswordIntermediate = [self hmacForKey:passwordData andData:salti];
    NSData* saltedPassword = saltedPasswordIntermediate;
    for(long i = 1; i < iterationCount; i++)
    {
        saltedPasswordIntermediate = [self hmacForKey:passwordData andData:saltedPasswordIntermediate];
        saltedPassword = [HelperTools XORData:saltedPassword withData:saltedPasswordIntermediate];
    }
    return saltedPassword;
}

-(NSString*) method
{
    if(_usingChannelBinding)
        return [NSString stringWithFormat:@"%@-PLUS", _method];
    return _method;
}


-(NSData*) hmacForKey:(NSData*) key andData:(NSData*) data
{
    if([_method isEqualToString:@"SCRAM-SHA-1"])
        return [HelperTools sha1HmacForKey:key andData:data];
    if([_method isEqualToString:@"SCRAM-SHA-256"])
        return [HelperTools sha256HmacForKey:key andData:data];
    if([_method isEqualToString:@"SCRAM-SHA-512"])
        return [HelperTools sha512HmacForKey:key andData:data];
    NSAssert(NO, @"Unexpected error: unsupported SCRAM hash method!", (@{@"method": nilWrapper(_method)}));
    return nil;
}

-(NSData*) hash:(NSData*) data
{
    if([_method isEqualToString:@"SCRAM-SHA-1"])
        return [HelperTools sha1:data];
    if([_method isEqualToString:@"SCRAM-SHA-256"])
        return [HelperTools sha256:data];
    if([_method isEqualToString:@"SCRAM-SHA-512"])
        return [HelperTools sha512:data];
    NSAssert(NO, @"Unexpected error: unsupported SCRAM hash method!", (@{@"method": nilWrapper(_method)}));
    return nil;
}

-(NSDictionary* _Nullable) parseScramString:(NSString*) str
{
    NSMutableDictionary* retval = [NSMutableDictionary new];
    for(NSString* component in [str componentsSeparatedByString:@","])
    {
        NSString* attribute = [component substringToIndex:1];
        NSString* value = [component substringFromIndex:2];
        retval[attribute] = [self unquote:value];
    }
    return retval;
}

-(NSString*) mapCharacter:(unichar) ch
{
    switch(ch)
    {
        //chars mapping to space (table C.1.2)
        case 0x00A0:    //Non-breaking space
        case 0x1680:    //Ogham space mark
        case 0x2000:    //En quad
        case 0x2001:    //Em quad
        case 0x2002:    //En space
        case 0x2003:    //Em space
        case 0x2004:    //Three-per-em space
        case 0x2005:    //Four-per-em space
        case 0x2006:    //Six-per-em space
        case 0x2007:    //Figure space
        case 0x2008:    //Punctuation space
        case 0x2009:    //Thin space
        case 0x200A:    //Hair space
        case 0x202F:    //Narrow no-break space
        case 0x205F:    //Medium mathematical space
        case 0x3000:    //Ideographic space
            return @" ";    //All mapped to regular space (U+0020)
        
        //chars mapping to nothing (table B.1)
        case 0x0000:    //NULL
        case 0x0001:    //Start of Heading
        case 0x0002:    //Start of Text
        case 0x0003:    //End of Text
        case 0x0004:    //End of Transmission
        case 0x0005:    //Enquiry
        case 0x0006:    //Acknowledge
        case 0x0007:    //Bell
        case 0x0008:    //Backspace
        case 0x0009:    //Horizontal Tab
        case 0x000A:    //Line Feed
        case 0x000B:    //Vertical Tab
        case 0x000C:    //Form Feed
        case 0x000D:    //Carriage Return
        case 0x000E:    //Shift Out
        case 0x000F:    //Shift In
        case 0x0010:    //Data Link Escape
        case 0x0011:    //Device Control 1
        case 0x0012:    //Device Control 2
        case 0x0013:    //Device Control 3
        case 0x0014:    //Device Control 4
        case 0x0015:    //Negative Acknowledge
        case 0x0016:    //Synchronous Idle
        case 0x0017:    //End of Transmission Block
        case 0x0018:    //Cancel
        case 0x0019:    //End of Medium
        case 0x001A:    //Substitute
        case 0x001B:    //Escape
        case 0x001C:    //File Separator
        case 0x001D:    //Group Separator
        case 0x001E:    //Record Separator
        case 0x001F:    //Unit Separator
        case 0x007F:    //DELETE (DEL)
        //Non-character code points (U+FDD0 to U+FDEF, reserved for internal use)
        case 0xFDD0:
        case 0xFDD1:
        case 0xFDD2:
        case 0xFDD3:
        case 0xFDD4:
        case 0xFDD5:
        case 0xFDD6:
        case 0xFDD7:
        case 0xFDD8:
        case 0xFDD9:
        case 0xFDDA:
        case 0xFDDB:
        case 0xFDDC:
        case 0xFDDD:
        case 0xFDDE:
        case 0xFDDF:
        case 0xFEFF:    //Zero Width No-Break Space (ZWNBS)
            return @""; //These characters are mapped to nothing (removed from the string)

        default:
            return [NSString stringWithCharacters:&ch length:1];    //No mapping, return the character as is
    }
}

-(NSString*) SASLPrep:(NSString*) str isQuery:(BOOL) isQuery
{
    //saslprep/stringprep step 1: map characters
    NSMutableString* mappedString = [NSMutableString stringWithCapacity:str.length];
    for(NSUInteger i=0; i<str.length; i++)
    {
        unichar ch = [str characterAtIndex:i];
        NSString* mappedChar = [self mapCharacter:ch];
        [mappedString appendString:mappedChar];
    }
    str = mappedString;
    
    //saslprep/stringprep step 2: unicode normalization with profile KC
    str = [str precomposedStringWithCompatibilityMapping];
    
    //saslprep/stringprep step 3: prohibited chars check (will return an empty string if any of these are found)
    NSMutableCharacterSet* prohibitedCharset = [NSMutableCharacterSet new];
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x0000, 0x0020)];                  //C.2.1 U+0000 to U+001F
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x007F, 1)];                       //C.2.1 U+007F (DELETE)
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x0080, 0x0020)];                  //C.2.2 U+0080 to U+009F
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x06DD, 1)];                       //C.2.2 U+06DD - ARABIC END OF AYAH
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x070F, 1)];                       //C.2.2 U+070F - SYRIAC ABBREVIATION MARK
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x180E, 1)];                       //C.2.2 U+180E - MONGOLIAN VOWEL SEPARATOR
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x200C, 1)];                       //C.2.2 U+200C - ZERO WIDTH NON-JOINER
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x200D, 1)];                       //C.2.2 U+200D - ZERO WIDTH JOINER
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x2028, 1)];                       //C.2.2 U+2028 - LINE SEPARATOR
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x2029, 1)];                       //C.2.2 U+2029 - PARAGRAPH SEPARATOR
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x2060, 1)];                       //C.2.2 U+2060 - WORD JOINER
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x2061, 1)];                       //C.2.2 U+2061 - FUNCTION APPLICATION
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x2062, 1)];                       //C.2.2 U+2062 - INVISIBLE TIMES
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x2063, 1)];                       //C.2.2 U+2063 - INVISIBLE SEPARATOR
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x206A, 6)];                       //C.2.2 U+206A to U+206F - CONTROL CHARACTERS
    [prohibitedCharset addCharactersInRange:NSMakeRange(0xFEFF, 1)];                       //C.2.2 U+FEFF - ZERO WIDTH NO-BREAK SPACE
    [prohibitedCharset addCharactersInRange:NSMakeRange(0xFFF9, 4)];                       //C.2.2 U+FFF9 to U+FFFC - CONTROL CHARACTERS
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x1D173, 8)];                      //C.2.2 U+1D173 to U+1D17A - MUSICAL CONTROL CHARACTERS
    [prohibitedCharset addCharactersInRange:NSMakeRange(0xE000, 0xF8FF-0xE000+1)];         //C.3 Private use, plane 0
    [prohibitedCharset addCharactersInRange:NSMakeRange(0xF0000, 0xFFFFD-0xF0000+1)];      //C.3 Private use, plane 15
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x100000, 0x10FFFD-0x100000+1)];   //C.3 Private use, plane 0
    [prohibitedCharset addCharactersInRange:NSMakeRange(0xFDD0, 0x20)];                    //C.4 U+FDD0 to U+FDEF - Non-character code points
    [prohibitedCharset addCharactersInRange:NSMakeRange(0xFFFE, 2)];                       //C.4 U+FFFE to U+FFFF - Non-character code points
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x1FFFE, 2)];                      //C.4 U+1FFFE to U+1FFFF - Non-character code points
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x2FFFE, 2)];                      //C.4 U+2FFFE to U+2FFFF - Non-character code points
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x3FFFE, 2)];                      //C.4 U+3FFFE to U+3FFFF - Non-character code points
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x4FFFE, 2)];                      //C.4 U+4FFFE to U+4FFFF - Non-character code points
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x5FFFE, 2)];                      //C.4 U+5FFFE to U+5FFFF - Non-character code points
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x6FFFE, 2)];                      //C.4 U+6FFFE to U+6FFFF - Non-character code points
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x7FFFE, 2)];                      //C.4 U+7FFFE to U+7FFFF - Non-character code points
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x8FFFE, 2)];                      //C.4 U+8FFFE to U+8FFFF - Non-character code points
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x9FFFE, 2)];                      //C.4 U+9FFFE to U+9FFFF - Non-character code points
    [prohibitedCharset addCharactersInRange:NSMakeRange(0xAFFFE, 2)];                      //C.4 U+AFFFE to U+AFFFF - Non-character code points
    [prohibitedCharset addCharactersInRange:NSMakeRange(0xBFFFE, 2)];                      //C.4 U+BFFFE to U+BFFFF - Non-character code points
    [prohibitedCharset addCharactersInRange:NSMakeRange(0xCFFFE, 2)];                      //C.4 U+CFFFE to U+CFFFF - Non-character code points
    [prohibitedCharset addCharactersInRange:NSMakeRange(0xDFFFE, 2)];                      //C.4 U+DFFFE to U+DFFFF - Non-character code points
    [prohibitedCharset addCharactersInRange:NSMakeRange(0xEFFFE, 2)];                      //C.4 U+EFFFE to U+EFFFF - Non-character code points
    [prohibitedCharset addCharactersInRange:NSMakeRange(0xFFFFE, 2)];                      //C.4 U+FFFFE to U+FFFFF - Non-character code points
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x10FFFE, 2)];                     //C.4 U+10FFFE to U+10FFFF - Non-character code points
    [prohibitedCharset addCharactersInRange:NSMakeRange(0xD800, 0x800)];                   //C.5 U+D800 to U+DFFF - Surrogate codes
    [prohibitedCharset addCharactersInRange:NSMakeRange(0xFFF9, 5)];                       //C.6 U+FFF9 to U+FFFD - Inappropriate for plain text
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x2FF0, 0xC)];                     //C.7 U+2FF0 to U+2FFB - Ideographic description characters
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x0340, 2)];                       //C.8 U+0340, U+0341 - Specific characters for text direction and formatting
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x200E, 2)];                       //C.8 U+200E, U+200F - Specific characters for text direction and formatting
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x202A, 5)];                       //C.8 U+202A to U+202E - Specific characters for text direction and formatting
    [prohibitedCharset addCharactersInRange:NSMakeRange(0x206A, 6)];                       //C.8 U+206A to U+206F - Specific characters for text direction and formatting
    [prohibitedCharset addCharactersInRange:NSMakeRange(0xE0001, 1)];                      //C.9 U+E0001 (LANGUAGE TAG) - Tagging characters
    [prohibitedCharset addCharactersInRange:NSMakeRange(0xE0020, 0x60)];                   //C.9 U+E0020 to U+E007F (TAGGING CHARACTERS) - Tagging characters
    NSRange range = [str rangeOfCharacterFromSet:prohibitedCharset];
    if(range.location != NSNotFound)
        return @"";
    
    //saslprep/stringprep step 4: bidirectional characters handling
    //all right-to-left characters
    NSMutableCharacterSet* randALCatSet = [NSMutableCharacterSet new];
    [randALCatSet addCharactersInRange:NSMakeRange(0x0600, 0x06FF - 0x0600 + 1)];      // Arabic block range (U+0600 to U+06FF)
    [randALCatSet addCharactersInRange:NSMakeRange(0x0700, 0x074F - 0x0700 + 1)];      // Syriac block (U+0700 to U+074F)
    [randALCatSet addCharactersInRange:NSMakeRange(0x0780, 0x07BF - 0x0780 + 1)];      // Thaana block (U+0780 to U+07BF)
    [randALCatSet addCharactersInRange:NSMakeRange(0x0590, 0x05FF - 0x0590 + 1)];      // Hebrew block (U+0590 to U+05FF)
    [randALCatSet addCharactersInRange:NSMakeRange(0x07C0, 0x07FF - 0x07C0 + 1)];      // N'Ko block (U+07C0 to U+07FF)
    [randALCatSet addCharactersInRange:NSMakeRange(0x0840, 0x085F - 0x0840 + 1)];      // Mandaic block (U+0840 to U+085F)
    [randALCatSet addCharactersInRange:NSMakeRange(0x0800, 0x083F - 0x0800 + 1)];      // Samaritan block (U+0800 to U+083F)
    [randALCatSet addCharactersInRange:NSMakeRange(0xFB50, 0xFBFF - 0xFB50 + 1)];      // Arabic Presentation Forms-A (U+FB50 to U+FBFF)
    [randALCatSet addCharactersInRange:NSMakeRange(0xFE70, 0xFEFF - 0xFE70 + 1)];      // Arabic Presentation Forms-B (U+FE70 to U+FEFF)
    [randALCatSet addCharactersInRange:NSMakeRange(0xFB1D, 0xFB4F - 0xFB1D + 1)];      // Hebrew Presentation Forms (U+FB1D to U+FB4F)
    [randALCatSet addCharactersInRange:NSMakeRange(0x1EE00, 0x1EEFF - 0x1EE00 + 1)];    // Arabic Mathematical Alphanumeric Symbols (U+1EE00 to U+1EEFF)
    //all left-to-right characters
    NSMutableCharacterSet* LCatSet = [NSMutableCharacterSet new];
    [LCatSet addCharactersInRange:NSMakeRange(0x0041, 0x005A - 0x0041 + 1)];  // Uppercase Latin (A-Z)
    [LCatSet addCharactersInRange:NSMakeRange(0x0061, 0x007A - 0x0061 + 1)];  // Lowercase Latin (a-z)
    [LCatSet addCharactersInRange:NSMakeRange(0x0370, 0x03FF - 0x0370 + 1)];  // Greek block (U+0370 to U+03FF)
    [LCatSet addCharactersInRange:NSMakeRange(0x0400, 0x04FF - 0x0400 + 1)];  // Cyrillic block (U+0400 to U+04FF)
    [LCatSet addCharactersInRange:NSMakeRange(0x0590, 0x05FF - 0x0590 + 1)];  // Hebrew block (U+0590 to U+05FF)
    [LCatSet addCharactersInRange:NSMakeRange(0x0530, 0x058F - 0x0530 + 1)];  // Armenian block (U+0530 to U+058F)
    [LCatSet addCharactersInRange:NSMakeRange(0x0900, 0x097F - 0x0900 + 1)];  // Devanagari block (U+0900 to U+097F)
    [LCatSet addCharactersInRange:NSMakeRange(0x0B80, 0x0BFF - 0x0B80 + 1)];  // Tamil block (U+0B80 to U+0BFF)
    [LCatSet addCharactersInRange:NSMakeRange(0x0A80, 0x0AFF - 0x0A80 + 1)];  // Gujarati block (U+0A80 to U+0AFF)
    [LCatSet addCharactersInRange:NSMakeRange(0x0980, 0x09FF - 0x0980 + 1)];  // Bengali block (U+0980 to U+09FF)
    [LCatSet addCharactersInRange:NSMakeRange(0x0100, 0x024F - 0x0100 + 1)];  // Latin Extended block (U+0100 to U+024F)
    [LCatSet addCharactersInRange:NSMakeRange(0x0250, 0x02AF - 0x0250 + 1)];  // Additional Latin Extended-A and other regions (U+0250 to U+02AF, for example)
    [LCatSet addCharactersInRange:NSMakeRange(0x1F00, 0x1FFF - 0x1F00 + 1)];   // Basic Multilingual Plane (BMP) for other Latin-based characters and others as needed (Greek Extended, additional characters)
    NSRange rangeRandALCat = [str rangeOfCharacterFromSet:randALCatSet];
    NSRange rangeLCat = [str rangeOfCharacterFromSet:LCatSet];
    
    //If a string contains any RandALCat character, the string MUST NOT contain any LCat character.
    if(rangeRandALCat.location != NSNotFound && rangeLCat.location != NSNotFound)
        return @"";
    
    //If a string contains any RandALCat character, a RandALCat character MUST be the first character of the string,
    //and a RandALCat character MUST be the last character of the string.
    if(rangeRandALCat.location != NSNotFound && !([randALCatSet characterIsMember:[str characterAtIndex:0]] && [randALCatSet characterIsMember:[str characterAtIndex:str.length-1]]))
        return @"";
    
    //The following characters can cause changes in display or the order in which characters appear when rendered, or are deprecated in Unicode.
    NSMutableCharacterSet* displayOrderCharacterSet = [NSMutableCharacterSet new];
    [displayOrderCharacterSet addCharactersInRange:NSMakeRange(0x0340, 1)];  //5.8 U+0340 (COMBINING GRAVE TONE MARK)
    [displayOrderCharacterSet addCharactersInRange:NSMakeRange(0x0341, 1)];  //5.8 U+0341 (COMBINING ACUTE TONE MARK)
    [displayOrderCharacterSet addCharactersInRange:NSMakeRange(0x200E, 1)];  //5.8 U+200E (LEFT-TO-RIGHT MARK)
    [displayOrderCharacterSet addCharactersInRange:NSMakeRange(0x200F, 1)];  //5.8 U+200F (RIGHT-TO-LEFT MARK)
    [displayOrderCharacterSet addCharactersInRange:NSMakeRange(0x202A, 1)];  //5.8 U+202A (LEFT-TO-RIGHT EMBEDDING)
    [displayOrderCharacterSet addCharactersInRange:NSMakeRange(0x202B, 1)];  //5.8 U+202B (RIGHT-TO-LEFT EMBEDDING)
    [displayOrderCharacterSet addCharactersInRange:NSMakeRange(0x202C, 1)];  //5.8 U+202C (POP DIRECTIONAL FORMATTING)
    [displayOrderCharacterSet addCharactersInRange:NSMakeRange(0x202D, 1)];  //5.8 U+202D (LEFT-TO-RIGHT OVERRIDE)
    [displayOrderCharacterSet addCharactersInRange:NSMakeRange(0x202E, 1)];  //5.8 U+202E (RIGHT-TO-LEFT OVERRIDE)
    [displayOrderCharacterSet addCharactersInRange:NSMakeRange(0x206A, 1)];  //5.8 U+206A (INHIBIT SYMMETRIC SWAPPING)
    [displayOrderCharacterSet addCharactersInRange:NSMakeRange(0x206B, 1)];  //5.8 U+206B (ACTIVATE SYMMETRIC SWAPPING)
    [displayOrderCharacterSet addCharactersInRange:NSMakeRange(0x206C, 1)];  //5.8 U+206C (INHIBIT ARABIC FORM SHAPING)
    [displayOrderCharacterSet addCharactersInRange:NSMakeRange(0x206D, 1)];  //5.8 U+206D (ACTIVATE ARABIC FORM SHAPING)
    [displayOrderCharacterSet addCharactersInRange:NSMakeRange(0x206E, 1)];  //5.8 U+206E (NATIONAL DIGIT SHAPES)
    [displayOrderCharacterSet addCharactersInRange:NSMakeRange(0x206F, 1)];  //5.8 U+206F (NOMINAL DIGIT SHAPES)
    NSRange restrictedRange = [str rangeOfCharacterFromSet:displayOrderCharacterSet];
    if(restrictedRange.location != NSNotFound)
        return @"";
    
    //saslprep/stringprep step 5: unassigned code points (if isQuery is YES)
    //Table A.1 Unassigned code points in Unicode 3.2
    if(isQuery)
    {
        NSMutableCharacterSet* unassignedCodePointsCharacterSet = [NSMutableCharacterSet new];
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0221, 1)];  // U+0221
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0234, 0x1C)];  // U+0234 to U+024F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x02AE, 0x2)];  // U+02AE to U+02AF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x02EF, 0x11)];  // U+02EF to U+02FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0350, 0x10)];  // U+0350 to U+035F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0370, 0x4)];  // U+0370 to U+0373
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0376, 0x4)];  // U+0376 to U+0379
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x037B, 0x3)];  // U+037B to U+037D
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x037F, 0x5)];  // U+037F to U+0383
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x038B, 1)];  // U+038B
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x038D, 1)];  // U+038D
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x03A2, 1)];  // U+03A2
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x03CF, 1)];  // U+03CF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x03F7, 0x9)];  // U+03F7 to U+03FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0487, 1)];  // U+0487
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x04CF, 1)];  // U+04CF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x04F6, 0x2)];  // U+04F6 to U+04F7
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x04FA, 0x6)];  // U+04FA to U+04FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0510, 0x21)];  // U+0510 to U+0530
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0557, 0x2)];  // U+0557 to U+0558
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0560, 1)];  // U+0560
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0588, 1)];  // U+0588
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x058B, 0x6)];  // U+058B to U+0590
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x05A2, 1)];  // U+05A2
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x05BA, 1)];  // U+05BA
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x05C5, 0xB)];  // U+05C5 to U+05CF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x05EB, 0x5)];  // U+05EB to U+05EF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x05F5, 0x17)];  // U+05F5 to U+060B
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x060D, 0xE)];  // U+060D to U+061A
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x061C, 0x3)];  // U+061C to U+061E
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0620, 1)];  // U+0620
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x063B, 0x5)];  // U+063B to U+063F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0656, 0xA)];  // U+0656 to U+065F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x06EE, 0x2)];  // U+06EE to U+06EF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x06FF, 1)];  // U+06FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x070E, 1)];  // U+070E
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x072D, 0x3)];  // U+072D to U+072F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x074B, 0x35)];  // U+074B to U+077F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x07B2, 0x14F)];  // U+07B2 to U+0900
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0904, 1)];  // U+0904
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x093A, 0x2)];  // U+093A to U+093B
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x094E, 0x2)];  // U+094E to U+094F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0955, 0x3)];  // U+0955 to U+0957
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0971, 0x10)];  // U+0971 to U+0980
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0984, 1)];  // U+0984
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x098D, 0x2)];  // U+098D to U+098E
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0991, 0x2)];  // U+0991 to U+0992
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x09A9, 1)];  // U+09A9
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x09B1, 1)];  // U+09B1
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x09B3, 0x3)];  // U+09B3 to U+09B5
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x09BA, 0x2)];  // U+09BA to U+09BB
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x09BD, 1)];  // U+09BD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x09C5, 0x2)];  // U+09C5 to U+09C6
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x09C9, 0x2)];  // U+09C9 to U+09CA
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x09CE, 0x9)];  // U+09CE to U+09D6
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x09D8, 0x4)];  // U+09D8 to U+09DB
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x09DE, 1)];  // U+09DE
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x09E4, 0x2)];  // U+09E4 to U+09E5
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x09FB, 0x7)];  // U+09FB to U+0A01
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A03, 0x2)];  // U+0A03 to U+0A04
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A0B, 0x4)];  // U+0A0B to U+0A0E
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A11, 0x2)];  // U+0A11 to U+0A12
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A29, 1)];  // U+0A29
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A31, 1)];  // U+0A31
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A34, 1)];  // U+0A34
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A37, 1)];  // U+0A37
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A3A, 0x2)];  // U+0A3A to U+0A3B
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A3D, 1)];  // U+0A3D
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A43, 0x4)];  // U+0A43 to U+0A46
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A49, 0x2)];  // U+0A49 to U+0A4A
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A4E, 0xB)];  // U+0A4E to U+0A58
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A5D, 1)];  // U+0A5D
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A5F, 0x7)];  // U+0A5F to U+0A65
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A75, 0xC)];  // U+0A75 to U+0A80
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A84, 1)];  // U+0A84
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A8C, 1)];  // U+0A8C
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A8E, 1)];  // U+0A8E
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0A92, 1)];  // U+0A92
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0AA9, 1)];  // U+0AA9
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0AB1, 1)];  // U+0AB1
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0AB4, 1)];  // U+0AB4
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0ABA, 0x2)];  // U+0ABA to U+0ABB
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0AC6, 1)];  // U+0AC6
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0ACA, 1)];  // U+0ACA
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0ACE, 0x2)];  // U+0ACE to U+0ACF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0AD1, 0xF)];  // U+0AD1 to U+0ADF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0AE1, 0x5)];  // U+0AE1 to U+0AE5
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0AF0, 0x11)];  // U+0AF0 to U+0B00
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B04, 1)];  // U+0B04
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B0D, 0x2)];  // U+0B0D to U+0B0E
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B11, 0x2)];  // U+0B11 to U+0B12
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B29, 1)];  // U+0B29
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B31, 1)];  // U+0B31
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B34, 0x2)];  // U+0B34 to U+0B35
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B3A, 0x2)];  // U+0B3A to U+0B3B
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B44, 0x3)];  // U+0B44 to U+0B46
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B49, 0x2)];  // U+0B49 to U+0B4A
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B4E, 0x8)];  // U+0B4E to U+0B55
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B58, 0x4)];  // U+0B58 to U+0B5B
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B5E, 1)];  // U+0B5E
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B62, 0x4)];  // U+0B62 to U+0B65
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B71, 0x11)];  // U+0B71 to U+0B81
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B84, 1)];  // U+0B84
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B8B, 0x3)];  // U+0B8B to U+0B8D
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B91, 1)];  // U+0B91
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B96, 0x3)];  // U+0B96 to U+0B98
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B9B, 1)];  // U+0B9B
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0B9D, 1)];  // U+0B9D
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0BA0, 0x3)];  // U+0BA0 to U+0BA2
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0BA5, 0x3)];  // U+0BA5 to U+0BA7
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0BAB, 0x3)];  // U+0BAB to U+0BAD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0BB6, 1)];  // U+0BB6
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0BBA, 0x4)];  // U+0BBA to U+0BBD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0BC3, 0x3)];  // U+0BC3 to U+0BC5
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0BC9, 1)];  // U+0BC9
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0BCE, 0x9)];  // U+0BCE to U+0BD6
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0BD8, 0xF)];  // U+0BD8 to U+0BE6
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0BF3, 0xE)];  // U+0BF3 to U+0C00
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0C04, 1)];  // U+0C04
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0C0D, 1)];  // U+0C0D
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0C11, 1)];  // U+0C11
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0C29, 1)];  // U+0C29
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0C34, 1)];  // U+0C34
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0C3A, 0x4)];  // U+0C3A to U+0C3D
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0C45, 1)];  // U+0C45
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0C49, 1)];  // U+0C49
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0C4E, 0x7)];  // U+0C4E to U+0C54
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0C57, 0x9)];  // U+0C57 to U+0C5F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0C62, 0x4)];  // U+0C62 to U+0C65
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0C70, 0x12)];  // U+0C70 to U+0C81
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0C84, 1)];  // U+0C84
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0C8D, 1)];  // U+0C8D
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0C91, 1)];  // U+0C91
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0CA9, 1)];  // U+0CA9
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0CB4, 1)];  // U+0CB4
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0CBA, 0x4)];  // U+0CBA to U+0CBD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0CC5, 1)];  // U+0CC5
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0CC9, 1)];  // U+0CC9
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0CCE, 0x7)];  // U+0CCE to U+0CD4
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0CD7, 0x7)];  // U+0CD7 to U+0CDD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0CDF, 1)];  // U+0CDF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0CE2, 0x4)];  // U+0CE2 to U+0CE5
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0CF0, 0x12)];  // U+0CF0 to U+0D01
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0D04, 1)];  // U+0D04
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0D0D, 1)];  // U+0D0D
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0D11, 1)];  // U+0D11
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0D29, 1)];  // U+0D29
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0D3A, 0x4)];  // U+0D3A to U+0D3D
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0D44, 0x2)];  // U+0D44 to U+0D45
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0D49, 1)];  // U+0D49
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0D4E, 0x9)];  // U+0D4E to U+0D56
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0D58, 0x8)];  // U+0D58 to U+0D5F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0D62, 0x4)];  // U+0D62 to U+0D65
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0D70, 0x12)];  // U+0D70 to U+0D81
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0D84, 1)];  // U+0D84
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0D97, 0x3)];  // U+0D97 to U+0D99
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0DB2, 1)];  // U+0DB2
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0DBC, 1)];  // U+0DBC
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0DBE, 0x2)];  // U+0DBE to U+0DBF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0DC7, 0x3)];  // U+0DC7 to U+0DC9
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0DCB, 0x4)];  // U+0DCB to U+0DCE
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0DD5, 1)];  // U+0DD5
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0DD7, 1)];  // U+0DD7
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0DE0, 0x12)];  // U+0DE0 to U+0DF1
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0DF5, 0xC)];  // U+0DF5 to U+0E00
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0E3B, 0x4)];  // U+0E3B to U+0E3E
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0E5C, 0x25)];  // U+0E5C to U+0E80
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0E83, 1)];  // U+0E83
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0E85, 0x2)];  // U+0E85 to U+0E86
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0E89, 1)];  // U+0E89
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0E8B, 0x2)];  // U+0E8B to U+0E8C
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0E8E, 0x6)];  // U+0E8E to U+0E93
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0E98, 1)];  // U+0E98
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0EA0, 1)];  // U+0EA0
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0EA4, 1)];  // U+0EA4
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0EA6, 1)];  // U+0EA6
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0EA8, 0x2)];  // U+0EA8 to U+0EA9
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0EAC, 1)];  // U+0EAC
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0EBA, 1)];  // U+0EBA
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0EBE, 0x2)];  // U+0EBE to U+0EBF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0EC5, 1)];  // U+0EC5
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0EC7, 1)];  // U+0EC7
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0ECE, 0x2)];  // U+0ECE to U+0ECF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0EDA, 0x2)];  // U+0EDA to U+0EDB
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0EDE, 0x22)];  // U+0EDE to U+0EFF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0F48, 1)];  // U+0F48
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0F6B, 0x6)];  // U+0F6B to U+0F70
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0F8C, 0x4)];  // U+0F8C to U+0F8F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0F98, 1)];  // U+0F98
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0FBD, 1)];  // U+0FBD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0FCD, 0x2)];  // U+0FCD to U+0FCE
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x0FD0, 0x30)];  // U+0FD0 to U+0FFF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1022, 1)];  // U+1022
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1028, 1)];  // U+1028
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x102B, 1)];  // U+102B
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1033, 0x3)];  // U+1033 to U+1035
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x103A, 0x6)];  // U+103A to U+103F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x105A, 0x46)];  // U+105A to U+109F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x10C6, 0xA)];  // U+10C6 to U+10CF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x10F9, 0x2)];  // U+10F9 to U+10FA
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x10FC, 0x4)];  // U+10FC to U+10FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x115A, 0x5)];  // U+115A to U+115E
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x11A3, 0x5)];  // U+11A3 to U+11A7
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x11FA, 0x6)];  // U+11FA to U+11FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1207, 1)];  // U+1207
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1247, 1)];  // U+1247
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1249, 1)];  // U+1249
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x124E, 0x2)];  // U+124E to U+124F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1257, 1)];  // U+1257
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1259, 1)];  // U+1259
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x125E, 0x2)];  // U+125E to U+125F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1287, 1)];  // U+1287
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1289, 1)];  // U+1289
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x128E, 0x2)];  // U+128E to U+128F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x12AF, 1)];  // U+12AF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x12B1, 1)];  // U+12B1
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x12B6, 0x2)];  // U+12B6 to U+12B7
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x12BF, 1)];  // U+12BF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x12C1, 1)];  // U+12C1
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x12C6, 0x2)];  // U+12C6 to U+12C7
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x12CF, 1)];  // U+12CF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x12D7, 1)];  // U+12D7
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x12EF, 1)];  // U+12EF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x130F, 1)];  // U+130F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1311, 1)];  // U+1311
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1316, 0x2)];  // U+1316 to U+1317
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x131F, 1)];  // U+131F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1347, 1)];  // U+1347
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x135B, 0x6)];  // U+135B to U+1360
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x137D, 0x23)];  // U+137D to U+139F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x13F5, 0xC)];  // U+13F5 to U+1400
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1677, 0x9)];  // U+1677 to U+167F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x169D, 0x3)];  // U+169D to U+169F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x16F1, 0xF)];  // U+16F1 to U+16FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x170D, 1)];  // U+170D
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1715, 0xB)];  // U+1715 to U+171F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1737, 0x9)];  // U+1737 to U+173F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1754, 0xC)];  // U+1754 to U+175F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x176D, 1)];  // U+176D
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1771, 1)];  // U+1771
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1774, 0xC)];  // U+1774 to U+177F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x17DD, 0x3)];  // U+17DD to U+17DF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x17EA, 0x16)];  // U+17EA to U+17FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x180F, 1)];  // U+180F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x181A, 0x6)];  // U+181A to U+181F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1878, 0x8)];  // U+1878 to U+187F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x18AA, 0x556)];  // U+18AA to U+1DFF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1E9C, 0x4)];  // U+1E9C to U+1E9F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1EFA, 0x6)];  // U+1EFA to U+1EFF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1F16, 0x2)];  // U+1F16 to U+1F17
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1F1E, 0x2)];  // U+1F1E to U+1F1F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1F46, 0x2)];  // U+1F46 to U+1F47
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1F4E, 0x2)];  // U+1F4E to U+1F4F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1F58, 1)];  // U+1F58
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1F5A, 1)];  // U+1F5A
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1F5C, 1)];  // U+1F5C
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1F5E, 1)];  // U+1F5E
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1F7E, 0x2)];  // U+1F7E to U+1F7F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1FB5, 1)];  // U+1FB5
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1FC5, 1)];  // U+1FC5
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1FD4, 0x2)];  // U+1FD4 to U+1FD5
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1FDC, 1)];  // U+1FDC
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1FF0, 0x2)];  // U+1FF0 to U+1FF1
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1FF5, 1)];  // U+1FF5
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1FFF, 1)];  // U+1FFF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2053, 0x4)];  // U+2053 to U+2056
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2058, 0x7)];  // U+2058 to U+205E
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2064, 0x6)];  // U+2064 to U+2069
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2072, 0x2)];  // U+2072 to U+2073
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x208F, 0x11)];  // U+208F to U+209F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x20B2, 0x1E)];  // U+20B2 to U+20CF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x20EB, 0x15)];  // U+20EB to U+20FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x213B, 0x2)];  // U+213B to U+213C
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x214C, 0x7)];  // U+214C to U+2152
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2184, 0xC)];  // U+2184 to U+218F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x23CF, 0x31)];  // U+23CF to U+23FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2427, 0x19)];  // U+2427 to U+243F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x244B, 0x15)];  // U+244B to U+245F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x24FF, 1)];  // U+24FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2614, 0x2)];  // U+2614 to U+2615
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2618, 1)];  // U+2618
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x267E, 0x2)];  // U+267E to U+267F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x268A, 0x77)];  // U+268A to U+2700
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2705, 1)];  // U+2705
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x270A, 0x2)];  // U+270A to U+270B
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2728, 1)];  // U+2728
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x274C, 1)];  // U+274C
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x274E, 1)];  // U+274E
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2753, 0x3)];  // U+2753 to U+2755
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2757, 1)];  // U+2757
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x275F, 0x2)];  // U+275F to U+2760
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2795, 0x3)];  // U+2795 to U+2797
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x27B0, 1)];  // U+27B0
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x27BF, 0x11)];  // U+27BF to U+27CF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x27EC, 0x4)];  // U+27EC to U+27EF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2B00, 0x380)];  // U+2B00 to U+2E7F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2E9A, 1)];  // U+2E9A
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2EF4, 0xC)];  // U+2EF4 to U+2EFF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2FD6, 0x1A)];  // U+2FD6 to U+2FEF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2FFC, 0x4)];  // U+2FFC to U+2FFF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x3040, 1)];  // U+3040
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x3097, 0x2)];  // U+3097 to U+3098
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x3100, 0x5)];  // U+3100 to U+3104
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x312D, 0x4)];  // U+312D to U+3130
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x318F, 1)];  // U+318F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x31B8, 0x38)];  // U+31B8 to U+31EF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x321D, 0x3)];  // U+321D to U+321F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x3244, 0xD)];  // U+3244 to U+3250
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x327C, 0x3)];  // U+327C to U+327E
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x32CC, 0x4)];  // U+32CC to U+32CF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x32FF, 1)];  // U+32FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x3377, 0x4)];  // U+3377 to U+337A
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x33DE, 0x2)];  // U+33DE to U+33DF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x33FF, 1)];  // U+33FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x4DB6, 0x4A)];  // U+4DB6 to U+4DFF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x9FA6, 0x5A)];  // U+9FA6 to U+9FFF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xA48D, 0x3)];  // U+A48D to U+A48F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xA4C7, 0x739)];  // U+A4C7 to U+ABFF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xD7A4, 0x5C)];  // U+D7A4 to U+D7FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFA2E, 0x2)];  // U+FA2E to U+FA2F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFA6B, 0x95)];  // U+FA6B to U+FAFF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFB07, 0xC)];  // U+FB07 to U+FB12
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFB18, 0x5)];  // U+FB18 to U+FB1C
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFB37, 1)];  // U+FB37
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFB3D, 1)];  // U+FB3D
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFB3F, 1)];  // U+FB3F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFB42, 1)];  // U+FB42
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFB45, 1)];  // U+FB45
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFBB2, 0x21)];  // U+FBB2 to U+FBD2
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFD40, 0x10)];  // U+FD40 to U+FD4F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFD90, 0x2)];  // U+FD90 to U+FD91
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFDC8, 0x8)];  // U+FDC8 to U+FDCF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFDFD, 0x3)];  // U+FDFD to U+FDFF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFE10, 0x10)];  // U+FE10 to U+FE1F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFE24, 0xC)];  // U+FE24 to U+FE2F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFE47, 0x2)];  // U+FE47 to U+FE48
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFE53, 1)];  // U+FE53
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFE67, 1)];  // U+FE67
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFE6C, 0x4)];  // U+FE6C to U+FE6F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFE75, 1)];  // U+FE75
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFEFD, 0x2)];  // U+FEFD to U+FEFE
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFF00, 1)];  // U+FF00
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFFBF, 0x3)];  // U+FFBF to U+FFC1
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFFC8, 0x2)];  // U+FFC8 to U+FFC9
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFFD0, 0x2)];  // U+FFD0 to U+FFD1
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFFD8, 0x2)];  // U+FFD8 to U+FFD9
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFFDD, 0x3)];  // U+FFDD to U+FFDF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFFE7, 1)];  // U+FFE7
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xFFEF, 0xA)];  // U+FFEF to U+FFF8
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x10000, 0x300)];  // U+10000 to U+102FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1031F, 1)];  // U+1031F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x10324, 0xC)];  // U+10324 to U+1032F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1034B, 0xB5)];  // U+1034B to U+103FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x10426, 0x2)];  // U+10426 to U+10427
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1044E, 0xCBB2)];  // U+1044E to U+1CFFF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D0F6, 0xA)];  // U+1D0F6 to U+1D0FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D127, 0x3)];  // U+1D127 to U+1D129
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D1DE, 0x222)];  // U+1D1DE to U+1D3FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D455, 1)];  // U+1D455
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D49D, 1)];  // U+1D49D
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D4A0, 0x2)];  // U+1D4A0 to U+1D4A1
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D4A3, 0x2)];  // U+1D4A3 to U+1D4A4
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D4A7, 0x2)];  // U+1D4A7 to U+1D4A8
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D4AD, 1)];  // U+1D4AD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D4BA, 1)];  // U+1D4BA
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D4BC, 1)];  // U+1D4BC
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D4C1, 1)];  // U+1D4C1
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D4C4, 1)];  // U+1D4C4
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D506, 1)];  // U+1D506
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D50B, 0x2)];  // U+1D50B to U+1D50C
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D515, 1)];  // U+1D515
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D51D, 1)];  // U+1D51D
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D53A, 1)];  // U+1D53A
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D53F, 1)];  // U+1D53F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D545, 1)];  // U+1D545
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D547, 0x3)];  // U+1D547 to U+1D549
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D551, 1)];  // U+1D551
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D6A4, 0x4)];  // U+1D6A4 to U+1D6A7
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D7CA, 0x4)];  // U+1D7CA to U+1D7CD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x1D800, 0x27FE)];  // U+1D800 to U+1FFFD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2A6D7, 0x5129)];  // U+2A6D7 to U+2F7FF
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x2FA1E, 0x5E0)];  // U+2FA1E to U+2FFFD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x30000, 0xFFFE)];  // U+30000 to U+3FFFD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x40000, 0xFFFE)];  // U+40000 to U+4FFFD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x50000, 0xFFFE)];  // U+50000 to U+5FFFD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x60000, 0xFFFE)];  // U+60000 to U+6FFFD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x70000, 0xFFFE)];  // U+70000 to U+7FFFD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x80000, 0xFFFE)];  // U+80000 to U+8FFFD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0x90000, 0xFFFE)];  // U+90000 to U+9FFFD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xA0000, 0xFFFE)];  // U+A0000 to U+AFFFD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xB0000, 0xFFFE)];  // U+B0000 to U+BFFFD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xC0000, 0xFFFE)];  // U+C0000 to U+CFFFD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xD0000, 0xFFFE)];  // U+D0000 to U+DFFFD
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xE0000, 1)];  // U+E0000
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xE0002, 0x1E)];  // U+E0002 to U+E001F
        [unassignedCodePointsCharacterSet addCharactersInRange:NSMakeRange(0xE0080, 0xFF7E)];  // U+E0080 to U+EFFFD
        NSRange unassignedRange = [str rangeOfCharacterFromSet:displayOrderCharacterSet];
        if(unassignedRange.location != NSNotFound)
            return @"";
    }
    
    return str;
}

-(NSString*) quote:(NSString*) str
{
    str = [str stringByReplacingOccurrencesOfString:@"=" withString:@"=3D"];
    str = [str stringByReplacingOccurrencesOfString:@"," withString:@"=2C"];
    return str;
}

-(NSString*) unquote:(NSString*) str
{
    str = [str stringByReplacingOccurrencesOfString:@"=2C" withString:@","];
    str = [str stringByReplacingOccurrencesOfString:@"=3D" withString:@"="];
    return str;
}

+(void) SSDPXepOutput
{
    SCRAM* s = [[self alloc] initWithUsername:@"user" password:@"pencil" andMethod:@"SCRAM-SHA-1-PLUS"];
    
    s->_clientFirstMessageBare = @"n=user,r=12C4CD5C-E38E-4A98-8F6D-15C38F51CCC6";
    s->_gssHeader = @"p=tls-exporter,,";
    
    s->_serverFirstMessage = @"r=12C4CD5C-E38E-4A98-8F6D-15C38F51CCC6a09117a6-ac50-4f2f-93f1-93799c2bddf6,s=QSXCR+Q6sek8bf92,i=4096,h=G6k/rBLDqgOhRRaCuuatSDFkJ08=";
    s->_nonce = @"12C4CD5C-E38E-4A98-8F6D-15C38F51CCC6a09117a6-ac50-4f2f-93f1-93799c2bddf6";
    s->_salt = [HelperTools dataWithBase64EncodedString:@"QSXCR+Q6sek8bf92"];
    s->_iterationCount = 4096;
    s->_serverFirstMessageParsed = YES;
    
    NSString* client_final_msg = [s clientFinalMessageWithChannelBindingData:[@"THIS IS FAKE CB DATA" dataUsingEncoding:NSUTF8StringEncoding]];
    DDLogError(@"client_final_msg: %@", client_final_msg);
    DDLogError(@"_expectedServerSignature: %@", s->_expectedServerSignature);
    
    [HelperTools flushLogsWithTimeout:0.250];
    exit(0);
}

@end
