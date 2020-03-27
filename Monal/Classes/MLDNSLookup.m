//
//  MLDNSLookup.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/4/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLDNSLookup.h"
@import Darwin.POSIX.sys.time; 

@interface MLDNSLookup()
@end

BOOL isSecure=NO;

@implementation MLDNSLookup

-(void) doDiscoveryWithSecure: (BOOL)secure andDomain: (NSString *) domain
{
	DNSServiceRef sdRef;
    DNSServiceErrorType res;
    
    isSecure = secure;
    NSString* serviceDiscoveryString=[NSString stringWithFormat:@"_xmpp%s-client._tcp.%@", isSecure ? "s" : "", domain];
    res=DNSServiceQueryRecord(
                              &sdRef, 0, 0,
                              [serviceDiscoveryString UTF8String],
                              kDNSServiceType_SRV,
                              kDNSServiceClass_IN,
                              query_cb,
                              ( __bridge void *)(self)
                              );
    if(res==kDNSServiceErr_NoError)
    {
        int sock=DNSServiceRefSockFD(sdRef);
        
        fd_set set;
        struct timeval timeout;
        
        /* Initialize the file descriptor set. */
        FD_ZERO (&set);
        FD_SET (sock, &set);
        
        /* Initialize the timeout data structure. */
        timeout.tv_sec = 2ul;
        timeout.tv_usec = 0;
        
        /* select returns 0 if timeout, 1 if input available, -1 if error. */
        int ready= select (FD_SETSIZE,&set, NULL, NULL,
                           &timeout) ;
        
        if(ready>0)
        {
            
            DNSServiceProcessResult(sdRef);
            DNSServiceRefDeallocate(sdRef);
        }
        else
        {
         //   DDLogVerbose(@"dns call timed out");
        }
        
    }
}

-(NSArray *) dnsDiscoverOnDomain:(NSString *) domain
{
    self.discoveredServers =[[NSMutableArray alloc] init];
    
    //mix xmpps and xmpp records as per XEP-0368
    [self doDiscoveryWithSecure:YES andDomain:domain];
    [self doDiscoveryWithSecure:NO andDomain:domain];
    
    //we ignore weights here for simplicity
    NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:@"priority"  ascending:YES];
    NSArray* sortArray =[NSArray arrayWithObjects:descriptor,nil];
    [self.discoveredServers sortUsingDescriptors:sortArray];
    
    return [self.discoveredServers copy];
}






char *ConvertDomainLabelToCString_withescape(const domainlabel *const label, char *ptr, char esc)
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

char *ConvertDomainNameToCString_withescape(const domainname *const name, char *ptr, char esc)
{
    const u_char *src         = name->c;                        // Domain name we're reading
    const u_char *const max   = name->c + MAX_DOMAIN_NAME;      // Maximum that's valid
    
    if (*src == 0) *ptr++ = '.';                                // Special case: For root, just write a dot
    
    while (*src)                                                                                                        // While more characters in the domain name
    {
        if (src + 1 + *src >= max) return(NULL);
        ptr = ConvertDomainLabelToCString_withescape((const domainlabel *)src, ptr, esc);
        if (!ptr) return(NULL);
        src += 1 + *src;
        *ptr++ = '.';                                           // Write the dot after the label
    }
    
    *ptr++ = 0;                                                 // Null-terminate the string
    return(ptr);                                                // and return
}

// print arbitrary rdata in a readable manned
void print_rdata(int type, int len, const u_char *rdata, void* context)
{
    srv_rdata *srv;
    char targetstr[MAX_CSTRING];

    
    MLDNSLookup *caller = (__bridge MLDNSLookup *) context;
    
    if(type== T_SRV)
    {
        srv = (srv_rdata *)rdata;
        ConvertDomainNameToCString_withescape(&srv->target, targetstr, 0);
        //  DDLogVerbose(@"pri=%d, w=%d, port=%d, target=%s\n", ntohs(srv->priority), ntohs(srv->weight), ntohs(srv->port), targetstr);
        
        int portval=ntohs(srv->port);
        NSString* theserver=[NSString stringWithUTF8String:targetstr];
        NSNumber* num=[NSNumber numberWithInt:ntohs(srv->priority)];
        NSNumber* theport=[NSNumber numberWithInt:portval];
        if(theserver && num && theport) {
            NSDictionary* row=[NSDictionary dictionaryWithObjectsAndKeys:num,@"priority", theserver,@"server", theport,@"port", [NSNumber numberWithBool:isSecure],@"isSecure", nil];
            [caller.discoveredServers addObject:row];
        }
    }
    
}

void query_cb(const DNSServiceRef DNSServiceRef, const DNSServiceFlags flags, const u_int32_t interfaceIndex, const DNSServiceErrorType errorCode, const char *name, const u_int16_t rrtype, const u_int16_t rrclass, const u_int16_t rdlen, const void *rdata, const u_int32_t ttl, void *context)
{
    (void)DNSServiceRef;
    (void)flags;
    (void)interfaceIndex;
    (void)rrclass;
    (void)ttl;
    (void)context;
    
    if (errorCode)
    {
        // DDLogVerbose(@"query callback: error==%d\n", errorCode);
        return;
    }
    // DDLogVerbose(@"query callback - name = %s, rdata=\n", name);
    print_rdata(rrtype, rdlen, rdata, context);
}


@end
