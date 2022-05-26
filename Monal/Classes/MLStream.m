//
//  MLStream.m
//  monalxmpp
//
//  Created by Thilo Molitor on 11.04.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#include <Network/Network.h>
#import "MLConstants.h"
#import "MLStream.h"
#import "HelperTools.h"

#define BUFFER_SIZE 4096

@interface MLSharedStreamState : NSObject
@property (atomic, strong) id<NSStreamDelegate> delegate;
@property (atomic, strong) NSRunLoop* runLoop;
@property (atomic) NSRunLoopMode runLoopMode;
@property (atomic, strong) NSError* error;
@property (atomic) nw_connection_t connection;
@property (atomic) BOOL opening;
@property (atomic) BOOL open;
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
    NSData* _buf;
    BOOL _reading;
}
@end

@interface MLOutputStream()
{
    unsigned long _writing;
}
@end

@implementation MLSharedStreamState

-(instancetype) initWithConnection:(nw_connection_t) connection
{
    self = [super init];
    self.connection = connection;
    self.error = nil;
    self.opening = NO;
    self.open = NO;
    return self;
}

@end


@implementation MLInputStream

-(instancetype) initWithSharedState:(MLSharedStreamState*) shared
{
    self = [super initWithSharedState:shared];
    _buf = [[NSData alloc] init];
    _reading = YES;
    return self;
}

-(NSInteger) read:(uint8_t*) buffer maxLength:(NSUInteger) len
{
    @synchronized(self.shared_state) {
        if(self.closed || !self.open_called || !self.shared_state.open)
            return -1;
    }
    if(len > [_buf length])
        len = [_buf length];
    [_buf getBytes:buffer length:len];
    if(len < [_buf length])
    {
        _buf = [_buf subdataWithRange:NSMakeRange(len, [_buf length]-len)];
        [self generateEvent:NSStreamEventHasBytesAvailable];
    }
    else
    {
        _buf = [[NSData alloc] init];
        [self schedule_read];
    }
    return len;
}

-(BOOL) getBuffer:(uint8_t* _Nullable *) buffer length:(NSUInteger*) len
{
    *len = [_buf length];
    *buffer = (uint8_t* _Nullable)[_buf bytes];
    return YES;
}

-(BOOL) hasBytesAvailable
{
    return _buf && [_buf length];
}

-(NSStreamStatus) streamStatus
{
    if(self.open_called && self.shared_state.open && _reading)
        return NSStreamStatusReading;
    return [super streamStatus];
}

-(void) schedule_read
{
    if(self.closed || !self.open_called || !self.shared_state.open)
    {
        DDLogVerbose(@"ignoring nw_connection_receive call because connection is closed: %@", self);
    }
    
    _reading = YES;
    DDLogVerbose(@"calling nw_connection_receive");
    nw_connection_receive(self.shared_state.connection, 1, BUFFER_SIZE, ^(dispatch_data_t content, nw_content_context_t context __unused, bool is_complete, nw_error_t receive_error) {
        DDLogVerbose(@"nw_connection_receive got callback with is_complete:%@, receive_error=%@", is_complete ? @"YES" : @"NO", receive_error);
        self->_reading = NO;
        
        //handle content received
        if(content != NULL)
        {
            if([(NSData*)content length] > 0)
            {
                self->_buf = (NSData*)content;
                [self generateEvent:NSStreamEventHasBytesAvailable];
            }
        }
        
        //handle errors
        if(receive_error)
        {
            NSError* st_error = (NSError*)CFBridgingRelease(nw_error_copy_cf_error(receive_error));
            @synchronized(self.shared_state) {
                self.shared_state.error = st_error;
            }
            [self generateEvent:NSStreamEventErrorOccurred];
        }
        
        //check if we're read-closed and stop our loop if true
        //this has to be done *after* processing content
        if(is_complete)
            [self generateEvent:NSStreamEventEndEncountered];
    });
}

-(void) generateEvent:(NSStreamEvent) event
{
    @synchronized(self.shared_state) {
        [super generateEvent:event];
        if(event == NSStreamEventOpenCompleted && self.open_called && self.shared_state.open)
            [self schedule_read];
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
    //the call to dispatch_get_main_queue() is a dummy because we are using DISPATCH_DATA_DESTRUCTOR_DEFAULT which is performed inline
    dispatch_data_t data = dispatch_data_create(buffer, len, dispatch_get_main_queue(), DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    
    //support tcp fast open for all data sent before the connection got opened
    /*if(!self.open_called)
    {
        DDLogInfo(@"Sending TCP fast open early data: %@", data);
        nw_connection_send(self.shared_state.connection, data, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, NO, NW_CONNECTION_SEND_IDEMPOTENT_CONTENT);
        return len;
    }*/
    
    @synchronized(self.shared_state) {
        if(self.closed || !self.open_called || !self.shared_state.open)
            return -1;
    }
    @synchronized(self) {
        _writing++;
    }
    nw_connection_send(self.shared_state.connection, data, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, NO, ^(nw_error_t  _Nullable error) {
        @synchronized(self) {
            self->_writing--;
        }
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
    });
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

+(void) connectWithSNIDomain:(NSString*) SNIDomain connectHost:(NSString*) host connectPort:(NSNumber*) port inputStream:(NSInputStream* _Nullable * _Nonnull) inputStream  outputStream:(NSOutputStream* _Nullable * _Nonnull) outputStream
{
    nw_endpoint_t endpoint = nw_endpoint_create_host([host cStringUsingEncoding:NSUTF8StringEncoding], [[port stringValue] cStringUsingEncoding:NSUTF8StringEncoding]);
    
    //always configure tls
    nw_parameters_t parameters = nw_parameters_create_secure_tcp(^(nw_protocol_options_t tls_options) {
        sec_protocol_options_t options = nw_tls_copy_sec_protocol_options(tls_options);
        sec_protocol_options_set_tls_server_name(options, [SNIDomain cStringUsingEncoding:NSUTF8StringEncoding]);
        sec_protocol_options_add_tls_application_protocol(options, "xmpp-client");
        sec_protocol_options_set_tls_resumption_enabled(options, 1);
        sec_protocol_options_set_tls_tickets_enabled(options, 1);
        sec_protocol_options_set_tls_ocsp_enabled(options, 1);
        sec_protocol_options_set_tls_false_start_enabled(options, 1);
        sec_protocol_options_set_min_tls_protocol_version(options, tls_protocol_version_TLSv12);
    }, ^(nw_protocol_options_t tcp_options) {
        nw_tcp_options_set_enable_fast_open(tcp_options, YES);      //enable tcp fast open
        //nw_tcp_options_set_no_delay(tcp_options, YES);              //disable nagle's algorithm
    });
    //not needed, will be done by apple's tls implementation automatically (only needed for plain tcp and manual sending of idempotent data)
    //nw_parameters_set_fast_open_enabled(parameters, YES);
    
    //create and configure connection object
    nw_connection_t connection = nw_connection_create(endpoint, parameters);
    nw_connection_set_queue(connection, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
    
    //create and configure public stream instances returned later
    MLSharedStreamState* shared_state = [[MLSharedStreamState alloc] initWithConnection:connection];
    MLInputStream* input = [[MLInputStream alloc] initWithSharedState:shared_state];
    MLOutputStream* output = [[MLOutputStream alloc] initWithSharedState:shared_state];
    
    //configure state change handler proxying state changes to our public stream instances
    __block BOOL wasOpenOnce = NO;
    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
        @synchronized(shared_state) {
            //connection was opened once (e.g. opening=YES) and closed later on (e.g. open=NO)
            if(wasOpenOnce && !shared_state.open)
            {
                DDLogVerbose(@"ignoring call to nw_connection state_changed_handler, connection already closed: %@ --> %du, %@", self, state, error);
                return;
            }
        }
        if(state == nw_connection_state_waiting)
        {
            //do nothing here, documentation says the connection will be automatically retried "when conditions are favourable"
            //which seems to mean: if the network path changed (for example connectivity regained)
            //if this happens inside the connection timeout all is ok
            //if not, the connection will be cancelled already and everything will be ok, too
            DDLogVerbose(@"got nw_connection_state_waiting and ignoring it, see comments in code...");
        }
        else if(state == nw_connection_state_failed)
        {
            DDLogError(@"Connection failed");
            NSError* st_error = (NSError*)CFBridgingRelease(nw_error_copy_cf_error(error));
            @synchronized(shared_state) {
                shared_state.error = st_error;
            }
            [input generateEvent:NSStreamEventErrorOccurred];
            [output generateEvent:NSStreamEventErrorOccurred];
        }
        else if(state == nw_connection_state_ready)
        {
            DDLogInfo(@"Connection established");
            wasOpenOnce = YES;
            @synchronized(shared_state) {
                shared_state.open = YES;
            }
            [input generateEvent:NSStreamEventOpenCompleted];
            [output generateEvent:NSStreamEventOpenCompleted];
        }
        else if(state == nw_connection_state_cancelled)
        {
            //ignore this (we use reference counting)
            DDLogVerbose(@"ignoring call to nw_connection state_changed_handler with state nw_connection_state_cancelled: %@ (%@)", self, error);
        }
        else if(state == nw_connection_state_invalid)
        {
            //ignore all other states (preparing, invalid)
            DDLogVerbose(@"ignoring call to nw_connection state_changed_handler with state nw_connection_state_invalid: %@ (%@)", self, error);
        }
        else if(state == nw_connection_state_preparing)
        {
            //ignore all other states (preparing, invalid)
            DDLogVerbose(@"ignoring call to nw_connection state_changed_handler with state nw_connection_state_preparing: %@ (%@)", self, error);
        }
        else
            unreachable();
    });
    
    *inputStream = (NSInputStream*)input;
    *outputStream = (NSOutputStream*)output;
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
            nw_connection_start(self.shared_state.connection);
        self.shared_state.opening = YES;
        //already opened by stream for other direction? --> directly trigger open event
        if(self.shared_state.open)
            [self generateEvent:NSStreamEventOpenCompleted];
    }
}

-(void) close
{
    nw_connection_send(self.shared_state.connection, NULL, NW_CONNECTION_FINAL_MESSAGE_CONTEXT, YES, ^(nw_error_t  _Nullable error) {
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

-(void) stream:(NSStream*) stream handleEvent:(NSStreamEvent) event
{
    //ignore event in this dummy delegate
    DDLogVerbose(@"ignoring event in dummy delegate: %@ --> %ld", stream, (long)event);
}

@end
