//
//  MLDNSLookup.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/4/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
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


NS_ASSUME_NONNULL_BEGIN

@interface MLDNSLookup : NSObject
@property (nonatomic, strong) NSMutableArray* discoveredServers;
-(NSArray*) dnsDiscoverOnDomain:(NSString*) domain;
@end

NS_ASSUME_NONNULL_END
