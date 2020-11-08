//
//  MLPipe.m
//  Monal
//
//  Created by Thilo Molitor on 03.05.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLPipe.h"

#define kPipeBufferSize 4096

@interface MLPipe()
{
    //buffer for writes to the output stream that can not be completed
    uint8_t * _outputBuffer;
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
    [_input scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    return self;
}

-(void) dealloc
{
    DDLogInfo(@"Deallocating pipe");
    [self close];
}

-(void) close
{
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
            [_input removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
            [_input close];
            _input = nil;
        }
        if(_output)
        {
            DDLogInfo(@"Closing pipe: output end");
            [_output setDelegate:nil];
            [_output removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
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

-(NSInputStream*) getNewEnd
{
    //make current output stream orphan
    if(_output)
    {
        DDLogInfo(@"Pipe making output stream orphan");
        [_output setDelegate:nil];
        [_output removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
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
    [_output scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [_output open];
    [inputStream open];
    return inputStream;
}

-(NSNumber*) drainInputStream
{
    NSInteger drainedBytes = 0;
    uint8_t* buf=malloc(kPipeBufferSize+1);
    NSInteger len = 0;
    do
    {
        if(![_input hasBytesAvailable])
            break;
        len = [_input read:buf maxLength:kPipeBufferSize];
        DDLogVerbose(@"Pipe drained %ld bytes", (long)len);
        if(len>0) {
            drainedBytes += len;
            buf[len]='\0';      //null termination for log output of raw string
            DDLogVerbose(@"Pipe got raw drained string '%s'", buf);
        }
    } while(len>0 && [_input hasBytesAvailable]);
    free(buf);
    DDLogVerbose(@"Pipe done draining %ld bytes", (long)drainedBytes);
    return @(drainedBytes);
}

-(void) cleanupOutputBuffer
{
    if(_outputBuffer)
    {
        DDLogVerbose(@"Pipe throwing away data in output buffer: %ld bytes", (long)_outputBufferByteCount);
        free(_outputBuffer);
    }
    _outputBuffer = nil;
    _outputBufferByteCount = 0;
}

-(void) process
{
    //only start processing if piping is possible
    if(!_output || ![_output hasSpaceAvailable])
    {
        //DDLogVerbose(@"not starting pipe processing, _output = %@", _output);
        return;
    }
    
    //DDLogVerbose(@"starting pipe processing");
    
    //try to send remaining buffered data first
    if(_outputBufferByteCount>0)
    {
        NSInteger writtenLen=[_output write:_outputBuffer maxLength:_outputBufferByteCount];
        if(writtenLen!=-1)
        {
            if(writtenLen!=_outputBufferByteCount)        //some bytes remaining to send
            {
                memmove(_outputBuffer, _outputBuffer+(size_t)writtenLen, _outputBufferByteCount-(size_t)writtenLen);
                _outputBufferByteCount-=writtenLen;
                DDLogVerbose(@"pipe processing sent part of buffered data");
                return;
            }
            else
            {
                //dealloc empty buffer
                free(_outputBuffer);
                _outputBuffer=nil;
                _outputBufferByteCount=0;        //everything sent
                DDLogVerbose(@"pipe processing sent all buffered data");
            }
        }
        else
        {
            NSError* error=[_output streamError];
            DDLogError(@"pipe sending failed with error %ld domain %@ message %@", (long)error.code, error.domain, error.userInfo);
            return;
        }
    }
    
    //return here if we have nothing to read
    if(![_input hasBytesAvailable])
    {
        //DDLogVerbose(@"stopped pipe processing: nothing to read");
        return;
    }
    
    uint8_t* buf=malloc(kPipeBufferSize+1);
    NSInteger readLen = 0;
    NSInteger writtenLen = 0;
    do
    {
        readLen = [_input read:buf maxLength:kPipeBufferSize];
        DDLogVerbose(@"pipe read %ld bytes", (long)readLen);
        if(readLen>0) {
            buf[readLen]='\0';      //null termination for log output of raw string
            DDLogVerbose(@"RECV: %s", buf);
            writtenLen = [_output write:buf maxLength:readLen];
            if(writtenLen == -1)
            {
                NSError* error=[_output streamError];
                DDLogError(@"pipe sending failed with error %ld domain %@ message %@", (long)error.code, error.domain, error.userInfo);
                return;
            }
            else if(writtenLen < readLen)
            {
                DDLogVerbose(@"pipe could only write %ld of %ld bytes, buffering", (long)writtenLen, (long)readLen);
                //allocate new _outputBuffer
                _outputBuffer=malloc(sizeof(uint8_t) * (readLen-writtenLen));
                //copy the remaining data into the buffer and set the buffer pointer accordingly
                memcpy(_outputBuffer, buf+(size_t)writtenLen, (size_t)(readLen-writtenLen));
                _outputBufferByteCount=(size_t)(readLen-writtenLen);
                break;
            }
        }
    } while(readLen>0 && [_input hasBytesAvailable] && [_output hasSpaceAvailable]);
    free(buf);
    //DDLogVerbose(@"pipe processing done");
}

-(void) stream:(NSStream*) stream handleEvent:(NSStreamEvent) eventCode
{
    //DDLogVerbose(@"Pipe stream %@ has event", stream);
    
    //ignore events from stale streams
    if(stream!=_input && stream!=_output)
        return;
    
    switch(eventCode)
    {
        //only log open and none events
        case NSStreamEventOpenCompleted:
        {
            DDLogVerbose(@"Pipe stream %@ completed open", stream);
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
