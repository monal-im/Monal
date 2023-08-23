//
//  MLStreamRedirect.m
//  monalxmpp
//
//  Created by Thilo Molitor on 18.08.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

#import "MLConstants.h"
#import "HelperTools.h"
#import "MLStreamRedirect.h"

@interface MLStreamRedirect () {
    FILE* _stream;
    BOOL _valid;
    NSPipe* _pipe;
    NSCondition* _threadCondition;
    int _origStreamFileno;
    NSThread* _readingThread;
    NSString* _eofMarkerUUID;
    BOOL _flushCompleted;
}
@end

@implementation MLStreamRedirect

//see https://stackoverflow.com/a/16395493 and https://stackoverflow.com/q/53978091
//and https://medium.com/@thesaadismail/eavesdropping-on-swifts-print-statements-57f0215efb42
-(instancetype) initWithStream:(FILE*) stream
{
    self = [super init];
    self->_stream = stream;
    self->_eofMarkerUUID = [[NSUUID UUID] UUIDString];
    self->_valid = NO;          //will be set to yes if everything worked out

    _pipe = [NSPipe pipe];
    if(_pipe == nil)
        [NSException raise:@"NSError" format:@"Failed to create pipe for outfd %d!", fileno(stream)];
    
    //reassign stream
    DDLogDebug(@"Redirecting outfd %d...", fileno(stream));
    _origStreamFileno = dup(fileno(stream));
    dup2([[_pipe fileHandleForWriting] fileDescriptor], fileno(stream));
    setvbuf(stream, nil, _IONBF, 0);
    
    _threadCondition = [NSCondition new];
    self->_flushCompleted = NO;
    
    //make sure we run as fast as possible using a dedicated thread with very high priority to finish stderr logging during a crash
    _readingThread = [[NSThread alloc] initWithTarget:self selector:@selector(readingThreadMain) object:nil];
    //_readingThread.threadPriority = 1.0;
    _readingThread.qualityOfService = NSQualityOfServiceUserInteractive;
    [_readingThread setName:[NSString stringWithFormat:@"StreamRedirectorThreadForFD:%d", fileno(_stream)]];
    [_readingThread start];
    self->_valid = YES;
    
    return self;
}

-(void) readingThreadMain
{
    //read other end of pipe and copy data into cocoa lumberjack
    DDLogDebug(@"Starting outfd %d reading loop...", fileno(self->_stream));
    while(![[NSThread currentThread] isCancelled])
    {
        NSData* data = [self->_pipe fileHandleForReading].availableData;
        if([data length] == 0)
        {
            DDLogWarn(@"EOF reached");
            break;
        }
        
        NSString* logstr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSArray* parts = [logstr componentsSeparatedByString:self->_eofMarkerUUID];
        for(NSString* logpart in parts)
        {
            //don't separate by \n, this will often stuff normal logmessages in between our lines even if they belong together
            //for(NSString* line in [logpart componentsSeparatedByString:@"\n"])
            NSString* line = logpart;
            {
                //ignore empty parts (e.g. eof marker or \n at end of string)
                if([line length] == 0)
                    continue;
                if(self->_stream == stdout) 
                    DDLogStdout(@"%@", line);
                else if(self->_stream == stderr) 
                    DDLogStderr(@"%@", line);
                else
                    DDLogVerbose(@"UNKNOWN_STREAM: %@", line);
            }
        }
        //a flush token was detected, signal we received it
        if([parts count] > 1)
            [self signalFlushCompleted];
    }
    self->_valid = NO;
    DDLogDebug(@"Stopped outfd %d reading loop...", fileno(self->_stream));
    [self signalFlushCompleted];
    
    //recover original file descriptor for good measure (leaving stdout and stderr in closed state can exhibit unexpected behavour)
    dup2(self->_origStreamFileno, fileno(self->_stream));
}

-(void) flush
{
    return [self flushWithWaitBlock:^{
        [self waitForFlushCompleted];
    }];
}

-(void) flushWithTimeout:(NSTimeInterval) timeout
{
    return [self flushWithWaitBlock:^{
        [self waitForFlushCompletedWithTimeout:timeout];
    }];
}

-(void) flushAndClose
{
    return [self flushAndCloseWithWaitBlock:^{
        [self waitForFlushCompleted];
    }];
}

-(void) flushAndCloseWithTimeout:(NSTimeInterval) timeout
{
    return [self flushAndCloseWithWaitBlock:^{
        [self waitForFlushCompletedWithTimeout:timeout];
    }];
}

-(void) flushWithWaitBlock:(monal_void_block_t) waitBlock
{
    if(!self->_valid)
        [NSException raise:@"NSError" format:@"Stream redirector for outfd %d already invalidated!", fileno(self->_stream)];
    
    //send our own eof marker through the pipe, this allows us to keep the pipe open
    fprintf(self->_stream, "%s", [self->_eofMarkerUUID UTF8String]);
    fflush(self->_stream);
    
    //wait for this flush to complete and flush our DDLog afterwards to make sure everything reached the log sinks
    DDLogVerbose(@"Waiting for flush of fd %d to complete...", fileno(self->_stream));
    waitBlock();
    DDLogVerbose(@"Flush on fd %d completed...", fileno(self->_stream));
    [DDLog flushLog];
}

-(void) flushAndCloseWithWaitBlock:(monal_void_block_t) waitBlock
{
    if(!self->_valid)
        [NSException raise:@"NSError" format:@"Stream redirector for outfd %d already invalidated!", fileno(self->_stream)];
    
    //send our own eof marker through the pipe to counter buffering issues (especially on stdout)
    [self flush];
    
    //according to apple's developer docs closing the pipe's fileHandleForWriting will send an eof signal to the reader (zero length NSData)
    NSError* error = nil;
    [[_pipe fileHandleForWriting] closeAndReturnError:&error];
    if(error != nil)
        [NSException raise:@"NSError" format:@"Error closing outfd %d pipe: %@", fileno(self->_stream), error];
    fflush(self->_stream);      //needed for stdio because of buffering
    [_readingThread cancel];
    
    //wait for this eof signal and flush our DDLog afterwards to make sure everything reached the log sinks
    waitBlock();
    [DDLog flushLog];
}

-(void) signalFlushCompleted
{
    [self->_threadCondition lock];
    self->_flushCompleted = YES;
    [self->_threadCondition signal];
    [self->_threadCondition unlock];
}

-(void) waitForFlushCompleted
{
    [self->_threadCondition lock];
    [self->_threadCondition wait];
    [self->_threadCondition unlock];
}

-(void) waitForFlushCompletedWithTimeout:(NSTimeInterval) timeout
{
    [self->_threadCondition lock];
    if(![self->_threadCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:timeout]])
        DDLogError(@"Timeout waiting for UUID EOF marker at outfd %d!", fileno(self->_stream));
    [self->_threadCondition unlock];
}

@end
