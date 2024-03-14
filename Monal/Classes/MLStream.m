//
//  MLStream.m
//  monalxmpp
//
//  Created by Thilo Molitor on 11.04.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import <Network/Network.h>
#import "MLConstants.h"
#import "MLStream.h"
#import "HelperTools.h"
#import <monalxmpp/monalxmpp-Swift.h>

@class MLCrypto;

#define BUFFER_SIZE 4096

@interface MLSharedStreamState : NSObject
@property (atomic, strong) id<NSStreamDelegate> delegate;
@property (atomic, strong) NSRunLoop* runLoop;
@property (atomic) NSRunLoopMode runLoopMode;
@property (atomic, strong) NSError* error;
@property (atomic) nw_connection_t connection;
@property (atomic) BOOL opening;
@property (atomic) BOOL open;
@property (atomic) BOOL hasTLS;
@property (atomic) nw_parameters_configure_protocol_block_t configure_tls_block;
@property (atomic) nw_framer_t _Nullable framer;
@property (atomic) NSCondition* tlsHandshakeCompleteCondition;
@end

@interface MLStream()
{
    id<NSStreamDelegate> _delegate;
}
@property (atomic, strong) MLSharedStreamState* shared_state;
@property (atomic) BOOL open_called;
@property (atomic) BOOL closed;
-(instancetype) initWithSharedState:(MLSharedStreamState*) shared;
-(void) generateEvent:(NSStreamEvent) event;
@end

@interface MLInputStream()
{
    NSMutableData* _buf;
    volatile __block BOOL _reading;
    //this semaphore will make sure that at most only one call to nw_connection_receive() or nw_framer_parse_input() is in flight
    //we use it as mutex: be careful to never increase it beyond 1!!
    //(mutexes can not be unlocked in a thread different from the one it got locked in and NSLock internally uses mutext --> both can not be used)
    dispatch_semaphore_t _read_sem;
}
@property (atomic, readonly) void (^incoming_data_handler)(NSData* _Nullable, BOOL, NSError* _Nullable, BOOL allow_next_read);
@end

@interface MLOutputStream()
{
    volatile __block unsigned long _writing;
}
@end

@implementation MLSharedStreamState

-(instancetype) init
{
    self = [super init];
    self.error = nil;
    self.opening = NO;
    self.open = NO;
    self.hasTLS = NO;
    self.framer = nil;
    self.tlsHandshakeCompleteCondition = [NSCondition new];
    return self;
}

@end


@implementation MLInputStream

-(instancetype) initWithSharedState:(MLSharedStreamState*) shared
{
    self = [super initWithSharedState:shared];
    _buf = [NSMutableData new];
    _reading = NO;
    //(see the comments added to the declaration of this member var)
    _read_sem = dispatch_semaphore_create(1);       //the first schedule_read call is always allowed
    
    //this handler will be called by the schedule_read method
    //since the framer swallows all data, nw_connection_receive() and the framer cannot race against each other and deliver reordered data
    weakify(self);
    _incoming_data_handler = ^(NSData* _Nullable content, BOOL is_complete, NSError* _Nullable st_error, BOOL allow_next_read) {
        strongify(self);
        if(self == nil)
            return;
        
        DDLogVerbose(@"Incoming data handler called with is_complete=%@, st_error=%@, content=%@", bool2str(is_complete), st_error, content);
        @synchronized(self.shared_state) {
            self->_reading = NO;
        }
        BOOL generate_bytes_available_event = NO;
        BOOL generate_error_event = NO;
        
        //handle content received
        if(content != NULL)
        {
            if([content length] > 0)
            {
                @synchronized(self->_buf) {
                    [self->_buf appendData:content];
                }
                generate_bytes_available_event = YES;
            }
        }
        
        //handle errors
        if(st_error)
        {
            //ignore enodata and eagain errors
            if([st_error.domain isEqualToString:(__bridge NSString *)kNWErrorDomainPOSIX] && (st_error.code == ENODATA || st_error.code == EAGAIN))
                DDLogWarn(@"Ignoring transient receive error: %@", st_error);
            else
            {
                @synchronized(self.shared_state) {
                    self.shared_state.error = st_error;
                }
                generate_error_event = YES;
            }
        }
        
        //allow new call to schedule_read
        //(see the comments added to the declaration of this member var)
        dispatch_semaphore_signal(self->_read_sem);
        
        //emit events
        if(generate_bytes_available_event)
            [self generateEvent:NSStreamEventHasBytesAvailable];
        if(generate_error_event)
            [self generateEvent:NSStreamEventErrorOccurred];
        //check if we're read-closed and stop our loop if true (this has to be done *after* processing content)
        if(is_complete)
            [self generateEvent:NSStreamEventEndEncountered];
        
        //try to read again
        if(!is_complete && !generate_bytes_available_event && allow_next_read)
            [self schedule_read];
    };
    return self;
}

-(NSInteger) read:(uint8_t*) buffer maxLength:(NSUInteger) len
{
    @synchronized(self.shared_state) {
        if(self.closed || !self.open_called || !self.shared_state.open)
            return -1;
    }
    BOOL was_smaller = NO;
    @synchronized(self->_buf) {
        if(len > [_buf length])
            len = [_buf length];
        [_buf getBytes:buffer length:len];
        if(len < [_buf length])
        {
            NSData* to_append = [_buf subdataWithRange:NSMakeRange(len, [_buf length]-len)];
            [_buf setLength:0];
            [_buf appendData:to_append];
            was_smaller = YES;
        }
        else
        {
            [_buf setLength:0];
            was_smaller = NO;
        }
    }
    //this has to be done outside of our @synchronized block
    if(was_smaller)
        [self generateEvent:NSStreamEventHasBytesAvailable];
    else if(len > 0)        //only do this if we really provided some data to the reader
    {
        //buffered data got retrieved completely --> schedule new read
        [self schedule_read];
    }
    return len;
}

-(BOOL) getBuffer:(uint8_t* _Nullable *) buffer length:(NSUInteger*) len
{
    return NO;      //this method is not available in this implementation
    /*
    @synchronized(_buf) {
        *len = [_buf length];
        *buffer = (uint8_t* _Nullable)[_buf bytes];
        return YES;
    }*/
}

-(BOOL) hasBytesAvailable
{
    @synchronized(_buf) {
        return _buf && [_buf length];
    }
}

-(NSStreamStatus) streamStatus
{
    @synchronized(self.shared_state) {
        if(self.open_called && self.shared_state.open && _reading)
            return NSStreamStatusReading;
    }
    return [super streamStatus];
}

-(void) schedule_read
{
    @synchronized(self.shared_state) {
        if(self.closed || !self.open_called || !self.shared_state.open)
        {
            DDLogVerbose(@"ignoring schedule_read call because connection is closed: %@", self);
            return;
        }
        
        //don't call nw_connection_receive() or nw_framer_parse_input() multiple times in parallel: this will introduce race conditions
        //(see the comments added to the declaration of this member var)
        if(dispatch_semaphore_wait(_read_sem, DISPATCH_TIME_NOW) != 0)
        {
            DDLogWarn(@"Ignoring call to schedule_read, reading already in progress...");
            return;
        }
        _reading = YES;
        
        if(self.shared_state.framer != nil)
        {
            DDLogDebug(@"dispatching async call to nw_framer_parse_input into framer queue");
            nw_framer_async(self.shared_state.framer, ^{
                DDLogDebug(@"now calling nw_framer_parse_input inside framer queue");
                nw_framer_parse_input(self.shared_state.framer, 1, BUFFER_SIZE, nil, ^size_t(uint8_t* buffer, size_t buffer_length, bool is_complete) {
                    DDLogDebug(@"nw_framer_parse_input got callback with is_complete:%@, length=%zu", bool2str(is_complete), (unsigned long)buffer_length);
                    //we only want to allow new calls to schedule_read if we received some data --> set last arg accordingly
                    self.incoming_data_handler([NSData dataWithBytes:buffer length:buffer_length], is_complete, nil, buffer_length > 0);
                    return buffer_length;
                });
            });
        }
        else
        {
            DDLogVerbose(@"calling nw_connection_receive");
            nw_connection_receive(self.shared_state.connection, 1, BUFFER_SIZE, ^(dispatch_data_t content, nw_content_context_t context __unused, bool is_complete, nw_error_t receive_error) {
                DDLogVerbose(@"nw_connection_receive got callback with is_complete:%@, receive_error=%@, length=%zu", bool2str(is_complete), receive_error, (unsigned long)((NSData*)content).length);
                NSError* st_error = nil;
                if(receive_error)
                    st_error = (NSError*)CFBridgingRelease(nw_error_copy_cf_error(receive_error));
                //we always want to allow new calls to schedule_read --> set last arg to YES
                self.incoming_data_handler((NSData*)content, is_complete, st_error, YES);
            });
        }
    }
}

-(void) generateEvent:(NSStreamEvent) event
{
    @synchronized(self.shared_state) {
        [super generateEvent:event];
        //in contrast to the normal nw_receive, the framer receive will not block until we receive any data
        //--> don't call schedule_read if a framer is active, the framer will call it itself once it gets signalled that data is available
        if(event == NSStreamEventOpenCompleted && self.open_called && self.shared_state.open && self.shared_state.framer == nil)
        {
            //we are open now --> allow reading (this will block until we receive any data)
            [self schedule_read];
        }
    }
}

@end

@implementation MLOutputStream

-(instancetype) initWithSharedState:(MLSharedStreamState*) shared
{
    self = [super initWithSharedState:shared];
    _writing = 0;
    return self;
}

-(NSInteger) write:(const uint8_t*) buffer maxLength:(NSUInteger) len
{
    @synchronized(self.shared_state) {
        if(self.closed)
            return -1;
    }
    
    NSCondition* condition = [NSCondition new];
    void (^write_completion)(nw_error_t) = ^(nw_error_t  _Nullable error) {
        DDLogVerbose(@"Write completed...");
        
        @synchronized(self) {
            self->_writing--;
        }
        
        [condition lock];
        [condition signal];
        [condition unlock];
        
        if(error)
        {
            NSError* st_error = (NSError*)CFBridgingRelease(nw_error_copy_cf_error(error));
            @synchronized(self.shared_state) {
                self.shared_state.error = st_error;
            }
            [self generateEvent:NSStreamEventErrorOccurred];
        }
        else
        {
            @synchronized(self) {
                if([self hasSpaceAvailable])
                    [self generateEvent:NSStreamEventHasSpaceAvailable];
            }
        }
    };
    
    //the call to dispatch_get_main_queue() is a dummy because we are using DISPATCH_DATA_DESTRUCTOR_DEFAULT which is performed inline
    dispatch_data_t data = dispatch_data_create(buffer, len, dispatch_get_main_queue(), DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    
    //support tcp fast open for all data sent before the connection got opened, but only usable for connections NOT using a framer
    /*if(!self.open_called)
    {
        DDLogInfo(@"Sending TCP fast open early data: %@", data);
        nw_connection_send(self.shared_state.connection, data, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, NO, NW_CONNECTION_SEND_IDEMPOTENT_CONTENT);
        return len;
    }*/
    
    @synchronized(self.shared_state) {
        if(!self.open_called || !self.shared_state.open)
            return -1;
    }
    @synchronized(self) {
        _writing++;
    }
    
    //decide if we should use our framer or normal nw_connection_send()
    //framer being nil is the hot path --> make it fast (we'll check if it's still != nil in an @synchronized block below --> still threadsafe
    //for the record: wrapping this into an @synchronized block would create a deadlock with our condition wait inside this
    //block and the second @synchronized block inside nw_framer_async()
    [condition lock];
    if(self.shared_state.framer != nil)
    {
        DDLogDebug(@"Switching async to framer thread in COLD path...");
        //framer methods must be called inside the framer thread
        nw_framer_async(self.shared_state.framer, ^{
            //make sure that self.shared_state.framer still isn't nil, if it is, we fall back to nw_connection_send()
            @synchronized(self.shared_state) {
                if(self.shared_state.framer != nil)
                {
                    DDLogDebug(@"Calling nw_framer_write_output_data() in COLD path...");
                    nw_framer_write_output_data(self.shared_state.framer, data);
                    //make sure to not call the write_completion inside this @synchronized block
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        write_completion(nil);      //TODO: can we detect write errors like in nw_connection_send() somehow?
                    });
                }
                else
                {
                    //make sure to not call nw_connection_send() and the following write_completion inside this @synchronized block
                    //we don't know if calling nw_connection_send() from the framer thread is safe --> just don't do this to be on the safe side
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        DDLogDebug(@"Calling nw_connection_send() in COLD path...");
                        nw_connection_send(self.shared_state.connection, data, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, NO, write_completion);
                    });
                }
            }
        });
        //wait for write complete signal
        [condition wait];
        [condition unlock];
        DDLogDebug(@"Returning from write in COLD path: %zu", (unsigned long)len);
        return len;     //return instead of else to leave @synchronized block early
    }
    DDLogVerbose(@"Calling nw_connection_send() in hot path...");
    nw_connection_send(self.shared_state.connection, data, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, NO, write_completion);
    //wait for write complete signal
    [condition wait];
    [condition unlock];
    DDLogVerbose(@"Returning from write in hot path: %zu", (unsigned long)len);
    return len;
}

-(BOOL) hasSpaceAvailable
{
    @synchronized(self) {
        return self.open_called && self.shared_state.open && !self.closed && _writing == 0;
    }
}

-(NSStreamStatus) streamStatus
{
    @synchronized(self) {
        if(self.open_called && self.shared_state.open && !self.closed && _writing > 0)
            return NSStreamStatusWriting;
    }
    return [super streamStatus];
}

-(void) generateEvent:(NSStreamEvent) event
{
    @synchronized(self.shared_state) {
        [super generateEvent:event];
        //generate the first NSStreamEventHasSpaceAvailable event directly after our NSStreamEventOpenCompleted event
        //(the network framework buffers outgoing data itself, e.g. it is always writable)
        if(event == NSStreamEventOpenCompleted && [self hasSpaceAvailable])
            [super generateEvent:NSStreamEventHasSpaceAvailable];
    }
}

@end

@implementation MLStream

+(void) connectWithSNIDomain:(NSString*) SNIDomain connectHost:(NSString*) host connectPort:(NSNumber*) port tls:(BOOL) tls inputStream:(NSInputStream* _Nullable * _Nonnull) inputStream  outputStream:(NSOutputStream* _Nullable * _Nonnull) outputStream logtag:(id _Nullable) logtag
{
    //create state
    volatile __block BOOL wasOpenOnce = NO;
    MLSharedStreamState* shared_state = [[MLSharedStreamState alloc] init];
    
    //create and configure public stream instances returned later
    MLInputStream* input = [[MLInputStream alloc] initWithSharedState:shared_state];
    MLOutputStream* output = [[MLOutputStream alloc] initWithSharedState:shared_state];
    
    nw_parameters_configure_protocol_block_t tcp_options = ^(nw_protocol_options_t tcp_options) {
        nw_tcp_options_set_enable_fast_open(tcp_options, YES);      //enable tcp fast open
        //nw_tcp_options_set_no_delay(tcp_options, YES);            //disable nagle's algorithm
        //nw_tcp_options_set_connection_timeout(tcp_options, 4);
    };
    nw_parameters_configure_protocol_block_t configure_tls_block = ^(nw_protocol_options_t tls_options) {
        sec_protocol_options_t options = nw_tls_copy_sec_protocol_options(tls_options);
        sec_protocol_options_set_tls_server_name(options, [SNIDomain cStringUsingEncoding:NSUTF8StringEncoding]);
        sec_protocol_options_add_tls_application_protocol(options, "xmpp-client");
        sec_protocol_options_set_tls_ocsp_enabled(options, 1);
        sec_protocol_options_set_tls_false_start_enabled(options, 1);
        sec_protocol_options_set_min_tls_protocol_version(options, tls_protocol_version_TLSv12);
        //sec_protocol_options_set_max_tls_protocol_version(options, tls_protocol_version_TLSv12);
        sec_protocol_options_set_tls_resumption_enabled(options, 1);
        sec_protocol_options_set_tls_tickets_enabled(options, 1);
        sec_protocol_options_set_tls_renegotiation_enabled(options, 0);
        //tls-exporter channel-binding is only usable for TLSv1.2 if ECDHE is used instead of RSA key exchange
        //(see https://mitls.org/pages/attacks/3SHAKE)
        //see also https://developer.apple.com/documentation/security/preventing_insecure_network_connections?language=objc
        sec_protocol_options_append_tls_ciphersuite_group(options, tls_ciphersuite_group_ats);
    };
    
    //configure tcp connection parameters
    nw_parameters_t parameters;
    if(tls)
    {
        parameters = nw_parameters_create_secure_tcp(configure_tls_block, tcp_options);
        shared_state.hasTLS = YES;
    }
    else
    {
        parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, tcp_options);
        shared_state.hasTLS = NO;
        
        //create simple framer and append it to our stack
        //first framer initialization is allowed to send tcp early data
        volatile __block int startupCounter = 0;     //workaround for some weird apple stuff, see below
        nw_protocol_definition_t starttls_framer_definition = nw_framer_create_definition([[[NSUUID UUID] UUIDString] UTF8String], NW_FRAMER_CREATE_FLAGS_DEFAULT, ^(nw_framer_t framer) {
            //we don't need any locking for our counter because all framers will be started in the same internal network queue
            int framerId = startupCounter++;
            DDLogInfo(@"%@: Framer(%d) %@ start called with wasOpenOnce=%@...", logtag, framerId, framer, bool2str(wasOpenOnce));
            nw_framer_set_stop_handler(framer, (nw_framer_stop_handler_t)^(nw_framer_t _Nullable framer) {
                DDLogInfo(@"%@, Framer(%d) stop called: %@", logtag, framerId, framer);
                return YES;
            });
            
            /*
            //some weird apple stuff creates the framer twice: once directly when starting the tcp handshake
            //and again later after the tcp connection was established successfully --> ignore the first one
            if(framerId < 1)
            {
                nw_framer_set_input_handler(framer, ^size_t(nw_framer_t framer) {
                    nw_framer_parse_input(framer, 1, BUFFER_SIZE, nil, ^size_t(uint8_t* buffer, size_t buffer_length, bool is_complete) {
                        MLAssert(NO, @"Unexpected incoming bytes in first framer!", (@{
                            @"logtag": nilWrapper(logtag),
                            @"framer": framer,
                            @"buffer": [NSData dataWithBytes:buffer length:buffer_length],
                            @"buffer_length": @(buffer_length),
                            @"is_complete": bool2str(is_complete),
                        }));
                        return buffer_length;
                    });
                    return 0;       //why that?
                });
                nw_framer_set_output_handler(framer, ^(nw_framer_t framer, nw_framer_message_t message, size_t message_length, bool is_complete) {
                    MLAssert(NO, @"Unexpected outgoing bytes in first framer!", (@{
                        @"logtag": nilWrapper(logtag),
                        @"framer": framer,
                        @"message": message,
                        @"message_length": @(message_length),
                        @"is_complete": bool2str(is_complete),
                    }));
                });
                return nw_framer_start_result_will_mark_ready;
            }
            */
            
            //we have to simulate nw_connection_state_ready because the connection state will not reflect that while our framer is active
            //--> use framer start as "connection active" signal
            //first framer start is allowed to directly send data which will be used as tcp early data
            if(!wasOpenOnce)
            {
                wasOpenOnce = YES;
                @synchronized(shared_state) {
                    shared_state.open = YES;
                }
                //make sure to not do this inside the framer thread to not cause any deadlocks
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    [input generateEvent:NSStreamEventOpenCompleted];
                    [output generateEvent:NSStreamEventOpenCompleted];
                });
            }
            
            nw_framer_set_input_handler(framer, ^size_t(nw_framer_t framer) {
                [input schedule_read];
                return 0;       //why that??
            });
            
            shared_state.framer = framer;
            return nw_framer_start_result_will_mark_ready;
        });
        DDLogInfo(@"%@: Not doing direct TLS: appending framer to protocol stack...", logtag);
        nw_protocol_stack_prepend_application_protocol(nw_parameters_copy_default_protocol_stack(parameters), nw_framer_create_options(starttls_framer_definition));
    }
    //needed to activate tcp fast open with apple's internal tls framer
    nw_parameters_set_fast_open_enabled(parameters, YES);
    
    //create and configure connection object
    nw_endpoint_t endpoint = nw_endpoint_create_host([host cStringUsingEncoding:NSUTF8StringEncoding], [[port stringValue] cStringUsingEncoding:NSUTF8StringEncoding]);
    nw_connection_t connection = nw_connection_create(endpoint, parameters);
    nw_connection_set_queue(connection, dispatch_queue_create_with_target([NSString stringWithFormat:@"im.monal.networking:%@", logtag].UTF8String, DISPATCH_QUEUE_SERIAL, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)));
    
    //configure shared state
    shared_state.connection = connection;
    shared_state.configure_tls_block = configure_tls_block;
        
    //configure state change handler proxying state changes to our public stream instances
    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
        @synchronized(shared_state) {
            //connection was opened once (e.g. opening=YES) and closed later on (e.g. open=NO)
            if(wasOpenOnce && !shared_state.open)
            {
                DDLogVerbose(@"%@: ignoring call to nw_connection state_changed_handler, connection already closed: %@ --> %du, %@", logtag, self, state, error);
                return;
            }
        }
        if(state == nw_connection_state_waiting)
        {
            //do nothing here, documentation says the connection will be automatically retried "when conditions are favourable"
            //which seems to mean: if the network path changed (for example connectivity regained)
            //if this happens inside the connection timeout all is ok
            //if not, the connection will be cancelled already and everything will be ok, too
            DDLogVerbose(@"%@: got nw_connection_state_waiting and ignoring it, see comments in code: %@ (%@)", logtag, self, error);
        }
        else if(state == nw_connection_state_failed)
        {
            DDLogError(@"%@: Connection failed", logtag);
            NSError* st_error = (NSError*)CFBridgingRelease(nw_error_copy_cf_error(error));
            @synchronized(shared_state) {
                shared_state.error = st_error;
            }
            [input generateEvent:NSStreamEventErrorOccurred];
            [output generateEvent:NSStreamEventErrorOccurred];
        }
        else if(state == nw_connection_state_ready)
        {
            DDLogInfo(@"%@: Connection established, wasOpenOnce: %@", bool2str(wasOpenOnce), logtag);
            if(!wasOpenOnce)
            {
                wasOpenOnce = YES;
                @synchronized(shared_state) {
                    shared_state.open = YES;
                }
                [input generateEvent:NSStreamEventOpenCompleted];
                [output generateEvent:NSStreamEventOpenCompleted];
            }
            else
            {
                //the nw_connection_state_ready state while already wasOpenOnce comes from our framer set to ready
                //this informs the upper layer that the connection is in ready state now, but we already treat the framer start
                //as connection ready event
                
                @synchronized(shared_state) {
                    //tls handshake completed now
                    shared_state.hasTLS = YES;
                    
                    //unlock thread waiting on tls handshake completion (starttls)
                    [shared_state.tlsHandshakeCompleteCondition lock];
                    [shared_state.tlsHandshakeCompleteCondition signal];
                    [shared_state.tlsHandshakeCompleteCondition unlock];
                }
                
                //we still want to inform our stream users that they can write data now and schedule a read operation
                [output generateEvent:NSStreamEventHasSpaceAvailable];
                [input schedule_read];
            }
        }
        else if(state == nw_connection_state_cancelled)
        {
            //ignore this (we use reference counting)
            DDLogVerbose(@"%@: ignoring call to nw_connection state_changed_handler with state nw_connection_state_cancelled: %@ (%@)", logtag, self, error);
        }
        else if(state == nw_connection_state_invalid)
        {
            //ignore all other states (preparing, invalid)
            DDLogVerbose(@"%@: ignoring call to nw_connection state_changed_handler with state nw_connection_state_invalid: %@ (%@)", logtag, self, error);
        }
        else if(state == nw_connection_state_preparing)
        {
            //ignore all other states (preparing, invalid)
            DDLogVerbose(@"%@: ignoring call to nw_connection state_changed_handler with state nw_connection_state_preparing: %@ (%@)", logtag, self, error);
        }
        else
            unreachable();
    });
    
    *inputStream = (NSInputStream*)input;
    *outputStream = (NSOutputStream*)output;
}

-(void) startTLS
{
    [self.shared_state.tlsHandshakeCompleteCondition lock];
    @synchronized(self.shared_state) {
        MLAssert(!self.shared_state.hasTLS, @"We already have TLS on this connection!");
        MLAssert(self.shared_state.framer != nil, @"Trying to start tls handshake without having a running framer!");
        DDLogInfo(@"Starting TLS handshake on framer: %@", self.shared_state.framer);
        nw_framer_async(self.shared_state.framer, ^{
            @synchronized(self.shared_state) {
                DDLogVerbose(@"Prepending tls to framer: %@", self.shared_state.framer);
                nw_framer_t framer = self.shared_state.framer;
                self.shared_state.framer = nil;
                nw_protocol_options_t tls_options = nw_tls_create_options();
                self.shared_state.configure_tls_block(tls_options);
                nw_framer_prepend_application_protocol(framer, tls_options);
                nw_framer_pass_through_input(framer);
                nw_framer_pass_through_output(framer);
                nw_framer_mark_ready(framer);
                DDLogVerbose(@"Framer deactivated and TLS prepended now...");
            }
        });
    }
    [self.shared_state.tlsHandshakeCompleteCondition wait];
    [self.shared_state.tlsHandshakeCompleteCondition unlock];
    DDLogInfo(@"TLS handshake completed: %@...", bool2str(self.shared_state.hasTLS));
}

-(BOOL) hasTLS
{
    @synchronized(self.shared_state) {
        return self.shared_state.hasTLS;
    }
}

-(instancetype) initWithSharedState:(MLSharedStreamState*) shared
{
    self = [super init];
    self.shared_state = shared;
    @synchronized(self.shared_state) {
        self.open_called = NO;
        self.closed = NO;
        self.delegate = self;
    }
    return self;
}

-(void) generateEvent:(NSStreamEvent) event
{
    @synchronized(self.shared_state) {
        //don't schedule delegate calls if no runloop was specified
        if(self.shared_state.runLoop == nil)
            return;
        //schedule the delegate calls in the runloop that was registered
        CFRunLoopPerformBlock([self.shared_state.runLoop getCFRunLoop], (__bridge CFStringRef)self.shared_state.runLoopMode, ^{
            @synchronized(self.shared_state) {
                if(event == NSStreamEventOpenCompleted && self.open_called && self.shared_state.open)
                    [self->_delegate stream:self handleEvent:event];
                else if(event == NSStreamEventHasBytesAvailable && self.open_called && self.shared_state.open)
                    [self->_delegate stream:self handleEvent:event];
                else if(event == NSStreamEventHasSpaceAvailable && self.open_called && self.shared_state.open)
                    [self->_delegate stream:self handleEvent:event];
                else if(event == NSStreamEventErrorOccurred)
                    [self->_delegate stream:self handleEvent:event];
                else if(event == NSStreamEventEndEncountered && self.open_called && self.shared_state.open)
                    [self->_delegate stream:self handleEvent:event];
                else
                    DDLogVerbose(@"Ignored event %ld", (long)event);
            }
        });
        //trigger wakeup of runloop to execute the block as soon as possible
        CFRunLoopWakeUp([self.shared_state.runLoop getCFRunLoop]);
    }
}

-(void) open
{
    @synchronized(self.shared_state) {
        MLAssert(!self.closed, @"streams can not be reopened!");
        self.open_called = YES;
        if(!self.shared_state.opening)
        {
            DDLogVerbose(@"Calling nw_connection_start()...");
            nw_connection_start(self.shared_state.connection);
        }
        self.shared_state.opening = YES;
        //already opened by stream for other direction? --> directly trigger open event
        if(self.shared_state.open)
            [self generateEvent:NSStreamEventOpenCompleted];
    }
}

-(void) close
{
    nw_connection_t connection;
    @synchronized(self.shared_state) {
        connection = self.shared_state.connection;
    }
    DDLogVerbose(@"Closing connection via nw_connection_send()...");
    nw_connection_send(connection, NULL, NW_CONNECTION_FINAL_MESSAGE_CONTEXT, YES, ^(nw_error_t  _Nullable error) {
        if(error)
        {
            NSError* st_error = (NSError*)CFBridgingRelease(nw_error_copy_cf_error(error));
            @synchronized(self.shared_state) {
                self.shared_state.error = st_error;
            }
            [self generateEvent:NSStreamEventErrorOccurred];
        }
    });
    @synchronized(self.shared_state) {
        self.closed = YES;
        self.shared_state.open = NO;
        
        //unlock thread waiting on tls handshake
        [self.shared_state.tlsHandshakeCompleteCondition lock];
        [self.shared_state.tlsHandshakeCompleteCondition signal];
        [self.shared_state.tlsHandshakeCompleteCondition unlock];
    }
}

-(void) setDelegate:(id<NSStreamDelegate>) delegate
{
    _delegate = delegate;
    if(_delegate == nil)
        _delegate = self;
}

-(void) scheduleInRunLoop:(NSRunLoop*) loop forMode:(NSRunLoopMode) mode
{
    @synchronized(self.shared_state) {
        self.shared_state.runLoop = loop;
        self.shared_state.runLoopMode = mode;
    }
}

-(void) removeFromRunLoop:(NSRunLoop*) loop forMode:(NSRunLoopMode) mode
{
    @synchronized(self.shared_state) {
        self.shared_state.runLoop = nil;
        self.shared_state.runLoopMode = mode;
    }
}

-(id) propertyForKey:(NSStreamPropertyKey) key
{
    return [super propertyForKey:key];
}

-(BOOL) setProperty:(id) property forKey:(NSStreamPropertyKey) key
{
    return [super setProperty:property forKey:key];
}

-(NSStreamStatus) streamStatus
{
    @synchronized(self.shared_state) {
        if(self.shared_state.error)
            return NSStreamStatusError;
        else if(!self.open_called && self.closed)
            return NSStreamStatusNotOpen;
        else if(self.open_called && self.shared_state.open)
            return NSStreamStatusOpen;
        else if(self.open_called)
            return NSStreamStatusOpening;
        else if(self.closed)
            return NSStreamStatusClosed;
    }
    unreachable();
    return 0;
}

-(NSError*) streamError
{
    NSError* error = nil;
    @synchronized(self.shared_state) {
        error = self.shared_state.error;
    }
    return error;
}

//list supported channel-binding types (highest security first!)
-(NSArray*) supportedChannelBindingTypes
{
    //we made sure we only use PFS based ciphers for which tls-exporter can safely be used even with TLS1.2
    //(see https://mitls.org/pages/attacks/3SHAKE)
    return @[@"tls-exporter", @"tls-server-end-point"];
    
    /*
    //BUT: other implementations simply don't support tls-exporter on non-tls1.3 connections --> do the same for compatibility
    if(self.isTLS13)
        return @[@"tls-exporter", @"tls-server-end-point"];
    return @[@"tls-server-end-point"];
    */
}

-(NSData* _Nullable) channelBindingDataForType:(NSString* _Nullable) type
{
    //don't log a warning in this special case
    if(type == nil)
        return nil;
    
    if([@"tls-exporter" isEqualToString:type])
        return [self channelBindingData_TLSExporter];
    else if([@"tls-server-end-point" isEqualToString:type])
        return [self channelBindingData_TLSServerEndPoint];
    else if([kServerDoesNotFollowXep0440Error isEqualToString:type])
        return [kServerDoesNotFollowXep0440Error dataUsingEncoding:NSUTF8StringEncoding];
    
    unreachable(@"Trying to use unknown channel-binding type!", (@{@"type":type}));
}

-(BOOL) isTLS13
{
    @synchronized(self.shared_state) {
        MLAssert([self streamStatus] >= NSStreamStatusOpen && [self streamStatus] < NSStreamStatusClosed, @"Stream must be open to call this method!", (@{@"streamStatus": @([self streamStatus])}));
        MLAssert(self.shared_state.hasTLS, @"Stream must have TLS negotiated to call this method!");
        nw_protocol_metadata_t p_metadata = nw_connection_copy_protocol_metadata(self.shared_state.connection, nw_protocol_copy_tls_definition());
        MLAssert(nw_protocol_metadata_is_tls(p_metadata), @"Protocol metadata is not TLS!");
        sec_protocol_metadata_t s_metadata = nw_tls_copy_sec_protocol_metadata(p_metadata);
        return sec_protocol_metadata_get_negotiated_tls_protocol_version(s_metadata) == tls_protocol_version_TLSv13;
    }
}

-(NSData*) channelBindingData_TLSExporter
{
    @synchronized(self.shared_state) {
        MLAssert([self streamStatus] >= NSStreamStatusOpen && [self streamStatus] < NSStreamStatusClosed, @"Stream must be open to call this method!", (@{@"streamStatus": @([self streamStatus])}));
        MLAssert(self.shared_state.hasTLS, @"Stream must have TLS negotiated to call this method!");
        nw_protocol_metadata_t p_metadata = nw_connection_copy_protocol_metadata(self.shared_state.connection, nw_protocol_copy_tls_definition());
        MLAssert(nw_protocol_metadata_is_tls(p_metadata), @"Protocol metadata is not TLS!");
        sec_protocol_metadata_t s_metadata = nw_tls_copy_sec_protocol_metadata(p_metadata);
        //see https://www.rfc-editor.org/rfc/rfc9266.html
        return (NSData*)sec_protocol_metadata_create_secret(s_metadata, 24, "EXPORTER-Channel-Binding", 32);
    }
}

-(NSData*) channelBindingData_TLSServerEndPoint
{
    @synchronized(self.shared_state) {
        MLAssert([self streamStatus] >= NSStreamStatusOpen && [self streamStatus] < NSStreamStatusClosed, @"Stream must be open to call this method!", (@{@"streamStatus": @([self streamStatus])}));
        MLAssert(self.shared_state.hasTLS, @"Stream must have TLS negotiated to call this method!");
        nw_protocol_metadata_t p_metadata = nw_connection_copy_protocol_metadata(self.shared_state.connection, nw_protocol_copy_tls_definition());
        MLAssert(nw_protocol_metadata_is_tls(p_metadata), @"Protocol metadata is not TLS!");
        sec_protocol_metadata_t s_metadata = nw_tls_copy_sec_protocol_metadata(p_metadata);
        __block NSData* cert = nil;
        sec_protocol_metadata_access_peer_certificate_chain(s_metadata, ^(sec_certificate_t certificate) {
            if(cert == nil)
                cert = (__bridge_transfer NSData*)SecCertificateCopyData(sec_certificate_copy_ref(certificate));
        });
        MLCrypto* crypto = [MLCrypto new];
        NSString* signatureAlgo = [crypto getSignatureAlgoOfCert:cert];
        DDLogDebug(@"Signature algo OID: %@", signatureAlgo);
        //OIDs taken from https://www.rfc-editor.org/rfc/rfc3279#section-2.2.3 and "Updated by" RFCs
        if([@"1.2.840.113549.2.5" isEqualToString:signatureAlgo])               //md5WithRSAEncryption
            return [HelperTools sha256:cert];       //use sha256 as per RFC 5929
        else if([@"1.3.14.3.2.26" isEqualToString:signatureAlgo])               //sha1WithRSAEncryption
            return [HelperTools sha256:cert];       //use sha256 as per RFC 5929
        else if([@"1.2.840.113549.1.1.11" isEqualToString:signatureAlgo])       //sha256WithRSAEncryption
            return [HelperTools sha256:cert];
        else if([@"1.2.840.113549.1.1.12" isEqualToString:signatureAlgo])       //sha384WithRSAEncryption (not supported, return sha256, will fail cb)
        {
            DDLogError(@"Using sha256 for unsupported OID %@ (sha384WithRSAEncryption)", signatureAlgo);
            return [HelperTools sha256:cert];
        }
        else if([@"1.2.840.113549.1.1.13" isEqualToString:signatureAlgo])       //sha512WithRSAEncryption
            return [HelperTools sha512:cert];
        else if([@"1.2.840.113549.1.1.14" isEqualToString:signatureAlgo])       //sha224WithRSAEncryption (not supported, return sha256, will fail cb)
        {
            DDLogError(@"Using sha256 for unsupported OID %@ (sha224WithRSAEncryption)", signatureAlgo);
            return [HelperTools sha256:cert];
        }
        else if([@"1.2.840.10045.4.1" isEqualToString:signatureAlgo])           //ecdsa-with-SHA1
            return [HelperTools sha256:cert];
        else if([@"1.2.840.10045.4.3.1" isEqualToString:signatureAlgo])         //ecdsa-with-SHA224  (not supported, return sha256, will fail cb)
        {
            DDLogError(@"Using sha256 for unsupported OID %@ (ecdsa-with-SHA224)", signatureAlgo);
            return [HelperTools sha256:cert];
        }
        else if([@"1.2.840.10045.4.3.2" isEqualToString:signatureAlgo])         //ecdsa-with-SHA256
            return [HelperTools sha256:cert];
        else if([@"1.2.840.10045.4.3.3" isEqualToString:signatureAlgo])         //ecdsa-with-SHA384  (not supported, return sha256, will fail cb)
        {
            DDLogError(@"Using sha256 for unsupported OID %@ (ecdsa-with-SHA384)", signatureAlgo);
            return [HelperTools sha256:cert];
        }
        else if([@"1.2.840.10045.4.3.4" isEqualToString:signatureAlgo])         //ecdsa-with-SHA512
            return [HelperTools sha256:cert];
        else if([@"1.3.6.1.5.5.7.6.32" isEqualToString:signatureAlgo])          //id-ecdsa-with-shake128  (not supported, return sha256, will fail cb)
        {
            DDLogError(@"Using sha256 for unsupported OID %@ (id-ecdsa-with-shake128)", signatureAlgo);
            return [HelperTools sha256:cert];
        }
        else if([@"1.3.6.1.5.5.7.6.33" isEqualToString:signatureAlgo])          //id-ecdsa-with-shake256  (not supported, return sha256, will fail cb)
        {
            DDLogError(@"Using sha256 for unsupported OID %@ (id-ecdsa-with-shake256)", signatureAlgo);
            return [HelperTools sha256:cert];
        }
        else        //all other algos use sha256 (that most probably will fail cb)
        {
            DDLogError(@"Using sha256 for unknown/unsupported OID: %@", signatureAlgo);
            return [HelperTools sha256:cert];
        }
    }
}

-(void) stream:(NSStream*) stream handleEvent:(NSStreamEvent) event
{
    //ignore event in this dummy delegate
    DDLogVerbose(@"ignoring event in dummy delegate: %@ --> %ld", stream, (long)event);
}

@end
