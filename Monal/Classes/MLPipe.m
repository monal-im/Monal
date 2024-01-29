//
//  MLPipe.m
//  Monal
//
//  Created by Thilo Molitor on 03.05.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLPipe.h"
#import "HelperTools.h"

#define kPipeBufferSize 4096
static uint8_t _staticOutputBuffer[kPipeBufferSize+1];      //+1 for '\0' needed for logging the received raw bytes

@interface MLPipe()
{
    //buffer for writes to the output stream that can not be completed
    uint8_t* _outputBuffer;
    size_t _outputBufferByteCount;
}

@property (atomic, strong) NSInputStream* input;
@property (atomic, strong) NSOutputStream* output;
@property (assign) id<NSStreamDelegate> delegate;

@end

@implementation MLPipe

-(id) initWithInputStream:(NSInputStream*) inputStream andOuterDelegate:(id<NSStreamDelegate>) outerDelegate
{
    _input = inputStream;
    _delegate = outerDelegate;
    _outputBufferByteCount = 0;
    [_input setDelegate:self];
    [_input scheduleInRunLoop:[HelperTools getExtraRunloopWithIdentifier:MLRunLoopIdentifierNetwork] forMode:NSDefaultRunLoopMode];
    return self;
}

-(void) dealloc
{
    DDLogInfo(@"Deallocating pipe");
    [self close];
}

-(void) close
{
    @synchronized(self) {
        //check if the streams are already closed
        if(!_input && !_output)
            return;
        DDLogInfo(@"Closing pipe");
        [self cleanupOutputBuffer];
        @try
        {
            if(_input)
            {
                DDLogInfo(@"Closing pipe: input end");
                [_input setDelegate:nil];
                [_input removeFromRunLoop:[HelperTools getExtraRunloopWithIdentifier:MLRunLoopIdentifierNetwork] forMode:NSDefaultRunLoopMode];
                [_input close];
                _input = nil;
            }
            if(_output)
            {
                DDLogInfo(@"Closing pipe: output end");
                [_output setDelegate:nil];
                [_output removeFromRunLoop:[HelperTools getExtraRunloopWithIdentifier:MLRunLoopIdentifierNetwork] forMode:NSDefaultRunLoopMode];
                [_output close];
                _output = nil;
            }
            DDLogInfo(@"Pipe closed");
        }
        @catch(id theException)
        {
            DDLogError(@"Exception while closing pipe: %@", theException);
        }
    }
}

-(NSInputStream*) getNewOutputStream
{
    @synchronized(self) {
        //make current output stream orphan
        if(_output)
        {
            DDLogInfo(@"Pipe making output stream orphan");
            [_output setDelegate:nil];
            [_output removeFromRunLoop:[HelperTools getExtraRunloopWithIdentifier:MLRunLoopIdentifierNetwork] forMode:NSDefaultRunLoopMode];
            [_output close];
            _output = nil;
        }
        [self cleanupOutputBuffer];
        
        //create new stream pair and schedule it properly, see: https://stackoverflow.com/a/31961573/3528174
        DDLogInfo(@"Pipe creating new stream pair");
        CFReadStreamRef readStream = NULL;
        CFWriteStreamRef writeStream = NULL;
        CFStreamCreateBoundPair(NULL, &readStream, &writeStream, kPipeBufferSize);
        NSInputStream* inputStream = (__bridge_transfer NSInputStream *)readStream;
        _output = (__bridge_transfer NSOutputStream *)writeStream;
        [_output setDelegate:self];
        [_output scheduleInRunLoop:[HelperTools getExtraRunloopWithIdentifier:MLRunLoopIdentifierNetwork] forMode:NSDefaultRunLoopMode];
        [_output open];
        [inputStream open];
        return inputStream;
    }
}

-(NSNumber*) drainInputStreamAndCloseOutputStream
{
    @synchronized(self) {
        //make current output stream orphan
        if(_output)
        {
            DDLogInfo(@"Pipe making output stream orphan");
            [_output setDelegate:nil];
            [_output removeFromRunLoop:[HelperTools getExtraRunloopWithIdentifier:MLRunLoopIdentifierNetwork] forMode:NSDefaultRunLoopMode];
            [_output close];
            _output = nil;
        }
        [self cleanupOutputBuffer];
        
        NSInteger drainedBytes = 0;
        NSInteger len = 0;
        do
        {
            if(![_input hasBytesAvailable])
                break;
            //read bytes but don't increment _outputBufferByteCount (e.g. ignore these bytes)
            len = [_input read:_staticOutputBuffer maxLength:kPipeBufferSize];
            DDLogDebug(@"Pipe drained %ld bytes", (long)len);
            if(len > 0)
            {
                drainedBytes += len;
                _staticOutputBuffer[len] = '\0';      //null termination for log output of raw string
                DDLogDebug(@"Pipe got raw drained string '%s'", _staticOutputBuffer);
            }
        } while(len > 0 && [_input hasBytesAvailable]);
        DDLogDebug(@"Pipe done draining %ld bytes", (long)drainedBytes);
        return @(drainedBytes);
    }
}

-(void) cleanupOutputBuffer
{
    @synchronized(self) {
        if(_outputBufferByteCount > 0)
            DDLogDebug(@"Pipe throwing away data in output buffer: %ld bytes", (long)_outputBufferByteCount);
        _outputBuffer = _staticOutputBuffer;
        _outputBufferByteCount = 0;
    }
}

-(void) process
{
    @synchronized(self) {
        //only start processing if piping is possible
        if(!_output)
        {
            DDLogDebug(@"not starting pipe processing: no output stream available");
            return;
        }
        if(![_output hasSpaceAvailable])
        {
            DDLogDebug(@"not starting pipe processing: no space to write");
            return;
        }
        
        //DDLogVerbose(@"starting pipe processing");
        
        //try to send remaining buffered data first
        if(_outputBufferByteCount > 0)
        {
            DDLogDebug(@"trying to send buffered data: %lu bytes", (unsigned long)_outputBufferByteCount);
            NSInteger writtenLen = [_output write:_outputBuffer maxLength:_outputBufferByteCount];
            if(writtenLen > 0)
            {
                if((NSUInteger) writtenLen != _outputBufferByteCount)        //some bytes remaining to send
                {
                    _outputBuffer += writtenLen;
                    _outputBufferByteCount -= writtenLen;
                    DDLogDebug(@"pipe processing sent part of buffered data: %ld", (long)writtenLen);
                    return;
                }
                else
                {
                    //reset empty buffer
                    _outputBuffer = _staticOutputBuffer;
                    _outputBufferByteCount = 0;        //everything sent
                    DDLogDebug(@"pipe processing sent all remaining buffered data");
                }
            }
            else
            {
                NSError* error = [_output streamError];
                DDLogError(@"pipe sending failed with error %ld domain %@ message %@", (long)error.code, error.domain, error.userInfo);
                return;
            }
        }
        
        //return here if we have nothing to read
        if(![_input hasBytesAvailable])
        {
            DDLogVerbose(@"stopped pipe processing: nothing to read");
            return;
        }
        
        NSInteger readLen = 0;
        NSInteger writtenLen = 0;
        do {
            readLen = [_input read:_outputBuffer maxLength:kPipeBufferSize];
            if(readLen > 0)
            {
                _outputBuffer[readLen] = '\0';      //null termination for log output of raw string
                DDLogVerbose(@"RECV(%ld): %s", (long)readLen, _outputBuffer);
                writtenLen = [_output write:_outputBuffer maxLength:readLen];
                if(writtenLen == -1)
                {
                    NSError* error = [_output streamError];
                    DDLogError(@"pipe sending failed with error %ld domain %@ message %@", (long)error.code, error.domain, error.userInfo);
                    break;
                }
                else if(writtenLen < readLen)
                {
                    DDLogDebug(@"pipe could only write %ld of %ld bytes, buffering", (long)writtenLen, (long)readLen);
                    //set the buffer pointer to the remaining data and leave our copy loop
                    _outputBuffer += (size_t)writtenLen;
                    _outputBufferByteCount = (size_t)(readLen-writtenLen);
                    break;
                }
            }
            else
                DDLogDebug(@"pipe read %ld <= 0 bytes", (long)readLen);
        } while(readLen > 0 && [_input hasBytesAvailable] && [_output hasSpaceAvailable]);
        //DDLogVerbose(@"pipe processing done");
    }
}

-(void) stream:(NSStream*) stream handleEvent:(NSStreamEvent) eventCode
{
    //DDLogVerbose(@"Pipe stream %@ has event", stream);
    
    //ignore events from stale streams
    if(stream != _input && stream != _output)
        return;
    
    switch(eventCode)
    {
        //only log open and none events
        case NSStreamEventOpenCompleted:
        {
            DDLogDebug(@"Pipe stream %@ completed open", stream);
            break;
        }
        
        case NSStreamEventNone:
        {
            //DDLogVerbose(@"Pipe stream %@ event none", stream);
            break;
        }
        
        //handle read and write events
        case NSStreamEventHasSpaceAvailable:
        {
            //DDLogVerbose(@"Pipe stream %@ has space available to write", stream);
            [self process];
            break;
        }
        case NSStreamEventHasBytesAvailable:
        {
            //DDLogVerbose(@"Pipe stream %@ has bytes available to read", stream);
            [self process];
            break;
        }
        
        //handle all other events in outer stream delegate
        default:
        {
            //DDLogVerbose(@"Pipe stream %@ delegates event to outer delegate", stream);
            [_delegate stream:stream handleEvent:eventCode];
            break;
        }
    }
}

@end
