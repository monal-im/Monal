//
//  MLDNSLookup.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/4/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <stdint.h>
#import <monalxmpp/MLConstants.h>
#import "MLDNSLookup.h"
#import <monalxmpp/HelperTools.h>
@import Darwin.POSIX.sys.time; 

#import <nameser.h>
#import <dns_sd.h>
#import <unistd.h>
#import <sys/types.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

#ifndef T_SRV
#define T_SRV kDNSServiceType_SRV
#endif

#ifndef T_PTR
#define T_PTR kDNSServiceType_PTR
#endif

#ifndef T_A
#define T_A kDNSServiceType_A
#endif

#ifndef T_TXT
#define T_TXT kDNSServiceType_TXT
#endif

#define MAX_DOMAIN_LABEL 63
#define MAX_DOMAIN_NAME 255
#define MAX_CSTRING 2044


typedef union { unsigned char b[2]; unsigned short NotAnInteger; } Opaque16;

typedef struct { u_char c[MAX_DOMAIN_LABEL]; } domainLabel;
typedef struct { u_char c[MAX_DOMAIN_NAME]; } domainName;


typedef struct __attribute__((packed))
{
    uint16_t priority;
    uint16_t weight;
    uint16_t port;
    domainName target;
} srv_rdata;


@interface MLDNSLookup()
@property (atomic, strong) NSMutableArray* discoveredStartTLSServers;
@property (atomic, strong) NSMutableArray* discoveredDirectTLSServers;
@end

static NSMutableDictionary* _RRCache;

@implementation MLDNSLookup

+(void) initialize
{
    _RRCache = [NSMutableDictionary new];
}

-(id) init
{
    self = [super init];
    self.discoveredStartTLSServers = [NSMutableArray new];
    self.discoveredDirectTLSServers = [NSMutableArray new];
    return self;
}

-(void) doDiscoveryWithSecure:(BOOL) secure andDomain:(NSString*) domain withTimeout:(NSTimeInterval) query_timeout
{
	DNSServiceRef sdRef;
    DNSServiceErrorType res;
    
    NSTimeInterval remainingTime = query_timeout;
    NSDate* startTime = [NSDate date];
    NSDictionary* context = @{
        @"isSecure": secure ? @YES : @NO,
        @"caller": self,
    };
    NSString* serviceDiscoveryString = [NSString stringWithFormat:@"_xmpp%@-client._tcp.%@", secure ? @"s" : @"", domain];
    res = DNSServiceQueryRecord(
        &sdRef,
        kDNSServiceFlagsReturnIntermediates,    // | kDNSServiceFlagsValidate,
        0,
        [serviceDiscoveryString UTF8String],
        kDNSServiceType_SRV,
        kDNSServiceClass_IN,
        query_cb,
        (__bridge void*)(context)
    );
    if(res == kDNSServiceErr_NoError)
    {
        int sock = DNSServiceRefSockFD(sdRef);
        while (remainingTime > 0)
        {
            fd_set set;
            FD_ZERO(&set);
            FD_SET(sock, &set);

            struct timeval tv;
            tv.tv_sec  = (time_t)remainingTime;
            tv.tv_usec = (int32_t)((remainingTime - (double)tv.tv_sec) * 1000000);

            int result = select(FD_SETSIZE, &set, NULL, NULL, &tv);
            DDLogVerbose(@"DNS select() returned %d", result);
            if(result == 1)
            {
                if(FD_ISSET(sock, &set))
                {
                    res = DNSServiceProcessResult(sdRef);
                    if(res != kDNSServiceErr_NoError)
                        DDLogError(@"Error %d reading the DNS SRV records for: %@", res, serviceDiscoveryString);
                    break;
                }
            }
            else if(result == 0)
            {
                DDLogError(@"DNS SRV select() timed out for: %@", serviceDiscoveryString);
                break;
            }
            else
            {
                if(errno == EINTR)
                {
                    DDLogInfo(@"DNS SRV select() interrupted, retry for: %@", serviceDiscoveryString);
                }
                else
                {
                    DDLogError(@"DNS SRV select() returned %d errno %d %s for %@", result, errno, strerror(errno), serviceDiscoveryString);
                    break;
                }
            }

            NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:startTime];
            remainingTime -= elapsed;
        }
        DNSServiceRefDeallocate(sdRef);
    }
    else
        DDLogError(@"DNS SRV query returned error %d for: %@", res, serviceDiscoveryString);
}

-(NSArray*) filterForDot:(NSArray*) foundEntries
{
    //filter out everything but the dot entry if a dot entry has been found
    @synchronized(foundEntries) {
        NSDictionary* dotEntry = nil;
        for(NSDictionary* row in foundEntries)
            if(![row[@"isEnabled"] boolValue])
            {
                dotEntry = row;
                break;
            }
        if(dotEntry != nil)
            return @[dotEntry];
        return foundEntries;
    }
}

-(NSArray*) doRealDnsDiscoverOnDomain:(NSString*) domain withTimeout:(NSTimeInterval) timeout
{
    //the whole function is blocking, this synchronized block makes sure we resolve one query at a time (scoped to this class instance)
    @synchronized(self) {
        NSMutableArray* allEntries = [NSMutableArray new];
        
        //request xmpps and xmpp records, xmpps will be preferred (use a dispatch queue to fetch xmpp and xmpps concurrently)
        DDLogVerbose(@"Querying DNS for xmpps AND xmpp records...");
        dispatch_queue_t queue = dispatch_queue_create("im.monal.dnsqueue", DISPATCH_QUEUE_CONCURRENT);
        dispatch_async(queue, ^{
            @synchronized(self.discoveredDirectTLSServers) {
                [self.discoveredDirectTLSServers removeAllObjects];
            }
            [self doDiscoveryWithSecure:YES andDomain:domain withTimeout:timeout];
            @synchronized(self.discoveredDirectTLSServers) {
                @synchronized(allEntries) {
                    [allEntries addObjectsFromArray:[self filterForDot:self.discoveredDirectTLSServers]];
                }
            }
        });
        dispatch_async(queue, ^{
            @synchronized(self.discoveredStartTLSServers) {
                [self.discoveredStartTLSServers removeAllObjects];
            }
            [self doDiscoveryWithSecure:NO andDomain:domain withTimeout:timeout];
            @synchronized(self.discoveredStartTLSServers) {
                @synchronized(allEntries) {
                    [allEntries addObjectsFromArray:[self filterForDot:self.discoveredStartTLSServers]];
                }
            }
        });
        //wait for both dns queries to complete
        dispatch_barrier_sync(queue, ^{
            DDLogVerbose(@"SRV DNS queries completed (xmpps AND xmpp)...");
        });
        
        @synchronized(allEntries) {
            //early return
            if([allEntries count] == 0)
            {
                DDLogInfo(@"No SRV records could be found, returning empty NSArray...");
                return @[];
            }
            
            //we ignore weights here for simplicity
            [allEntries sortUsingDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"priority" ascending:YES]]];
        
            //calculate lowest timeout
            u_int32_t lowest_ttl = UINT32_MAX;
            for(NSDictionary* entry in allEntries)
            {
#ifdef DEBUG
                MLAssert([entry isKindOfClass:[NSDictionary class]], @"allEntries has an entry that is NOT of type NSDictionary", (@{
                    @"entry": entry,
                    @"allEntries": allEntries,
                }));
#endif
                if([entry isKindOfClass:[NSDictionary class]])
                    lowest_ttl = MIN(lowest_ttl, [entry[@"ttl"] unsignedIntValue]);
            }
            DDLogVerbose(@"Lowest ttl for SRV records: %u", lowest_ttl);
        
            //update resource record cache with discovered servers list
            DDLogVerbose(@"Updating RRCache with: %@", allEntries);
            @synchronized(_RRCache) {
                _RRCache[domain] = @{
                    @"timeout": [NSDate dateWithTimeIntervalSinceNow:lowest_ttl],
                    @"records": [allEntries copy],
                };
            }
            
            //return discovered servers list
            return [allEntries copy];
        }
    }
}

-(NSArray*) dnsDiscoverOnDomain:(NSString*) domain
{
    /*
    @synchronized(_RRCache) {
        if(_RRCache[domain] != nil && [_RRCache[domain][@"timeout"] timeIntervalSinceNow] > 0)
        {
            //update our cache in background
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                [self doRealDnsDiscoverOnDomain:domain withTimeout:16ul];     //long query timeout (this is a background query)
            });
            return [_RRCache[domain][@"records"] copy];
        }
    }
    */
    return [self doRealDnsDiscoverOnDomain:domain withTimeout:8ul];     //short query timeout (we are waiting for this query)
}


// ********************************************** C code below **********************************************


char* ConvertDomainLabelToCString_withescape(const domainLabel* label, char* ptr, char esc)
{
    const u_char *      src = label->c;                         // Domain label we're reading
    const u_char        len = *src++;                           // Read length of this (non-null) label
    const u_char *const end = src + len;                        // Work out where the label ends
    if (len > MAX_DOMAIN_LABEL) return(NULL);           // If illegal label, abort
    while (src < end)                                           // While we have characters in the label
    {
        u_char c = *src++;
        if (esc)
        {
            if (c == '.')                                       // If character is a dot,
                *ptr++ = esc;                                   // Output escape character
            else if (c <= ' ')                                  // If non-printing ascii,
            {                                                   // Output decimal escape sequence
                *ptr++ = esc;
                *ptr++ = (char)  ('0' + (c / 100)     );
                *ptr++ = (char)  ('0' + (c /  10) % 10);
                c      = (u_char)('0' + (c      ) % 10);
            }
        }
        *ptr++ = (char)c;                                       // Copy the character
    }
    *ptr = 0;                                                   // Null-terminate the string
    return(ptr);                                                // and return
}

char* ConvertDomainNameToCString_withescape(const domainName* name, int len, char* ptr, char esc)
{
    const u_char *src         = name->c;                        // Domain name we're reading
    const u_char *const max   = name->c + MIN(MAX_DOMAIN_NAME, len);      // Maximum that's valid
    
    if (*src == 0) *ptr++ = '.';                                // Special case: For root, just write a dot
    
    while (*src)                                                // While more characters in the domain name
    {
        if (src + 1 + *src >= max) return(NULL);
        ptr = ConvertDomainLabelToCString_withescape((const domainLabel *)src, ptr, esc);
        if (!ptr) return(NULL);
        src += 1 + *src;
        *ptr++ = '.';                                           // Write the dot after the label
    }
    
    *ptr++ = 0;                                                 // Null-terminate the string
    return(ptr);                                                // and return
}

void query_cb(const DNSServiceRef DNSServiceRef, const DNSServiceFlags flags, const u_int32_t interfaceIndex, const DNSServiceErrorType errorCode, const char* name __unused, const u_int16_t rrtype, const u_int16_t rrclass, const u_int16_t rdlen, const void* rdata, const u_int32_t ttl, void* _context)
{
    //make sure the compiler doesn't cry because of unused arguments
    (void)DNSServiceRef;
    (void)interfaceIndex;
    (void)rrclass;
    
    //just ignore errors (don't fill anything into the discoveredDirectTLSServers/discoveredStartTLSServers array)
    if(errorCode)
    {
        DDLogVerbose(@"query callback: error==%d\n", errorCode);
        return;
    }
    
    NSDictionary* context = (__bridge NSDictionary*)_context;
    BOOL isSecure = [context[@"isSecure"] boolValue];
    MLDNSLookup* caller = (MLDNSLookup*)context[@"caller"];

    if(rrtype == T_SRV)
    {
        srv_rdata* srv = (srv_rdata*)rdata;
        char targetStr[MAX_CSTRING];
        int srvDomainLen = rdlen - sizeof(srv->priority) - sizeof(srv->weight) - sizeof(srv->port);
        if(srvDomainLen > MAX_DOMAIN_NAME)
            return;
        ConvertDomainNameToCString_withescape(&srv->target, srvDomainLen, targetStr, 0);
        DDLogVerbose(@"pri=%d, w=%d, port=%d, target=%s, ttl=%u, flags=%u\n", ntohs(srv->priority), ntohs(srv->weight), ntohs(srv->port), targetStr, ttl, (u_int32_t)flags);
        
        NSString* theServer = [NSString stringWithUTF8String:targetStr];
        NSNumber* prio = [NSNumber numberWithUnsignedInt:(ntohs(srv->priority) + (isSecure == YES ? 0 : UINT16_MAX))]; // prefer TLS over STARTTLS
        NSNumber* weight = [NSNumber numberWithInt:ntohs(srv->weight)];
        NSNumber* thePort = [NSNumber numberWithInt:ntohs(srv->port)];
        if(theServer && prio && weight && thePort) {
            // Check if service is not provided
            bool serviceEnabled = ![theServer isEqualToString:@"."];
            // Validate that the domain ends with at dot (and ignore this entry, if not)
            if([theServer hasSuffix:@"."] == NO)
                return;
            //add result to the appropriate discovered severs list
            if(isSecure)
                @synchronized(caller.discoveredDirectTLSServers) {
                    [caller.discoveredDirectTLSServers addObject:@{
                        @"priority": prio,
                        @"server": theServer,
                        @"port": thePort,
                        @"isSecure": @YES,
                        @"weight": weight,
                        @"isEnabled": [NSNumber numberWithBool:serviceEnabled],
                        @"ttl": [NSNumber numberWithUnsignedInt:ttl],
                    }];
                }
            else
                @synchronized(caller.discoveredStartTLSServers) {
                    [caller.discoveredStartTLSServers addObject:@{
                        @"priority": prio,
                        @"server": theServer,
                        @"port": thePort,
                        @"isSecure": @NO,
                        @"weight": weight,
                        @"isEnabled": [NSNumber numberWithBool:serviceEnabled],
                        @"ttl": [NSNumber numberWithUnsignedInt:ttl],
                    }];
                }
        }
    }
}


@end
