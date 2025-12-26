//
//  HandlerTest.m
//  MonalXMPPUnitTests
//
//  Created by admin on 10.02.25.
//  Copyright © 2025 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "MLConstants.h"
#import "MLHandler.h"

#define expressify(...)    ({ __VA_ARGS__ ;})

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wprotocol"

@interface HandlerTest : XCTestCase
@end

@implementation HandlerTest

-(void) setUp
{
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

-(void) tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

-(void) testVoidBlockIsNSObject
{
    XCTAssert([^{} isKindOfClass:[NSObject class]], "void block should be kind of NSObject");
}

$$class_handler(handlerTestStringObject, $$ID(NSObject*, dummyObj))
    XCTAssertEqualObjects(dummyObj, @"dummy string", "handler01 should have gotten 'dummy string'");
$$

-(void) testHandlerStringObject
{
    MLHandler* handler = $newHandler([self class], handlerTestStringObject);
    $call(handler, $ID(dummyObj, @"dummy string"));
}

$$class_handler(handlerTestBlockArgument, $$ID(monal_void_block_t, dummyCallback))
    dummyCallback();
$$

-(void) testHandlerBlockArgument
{
    XCTestExpectation* expectation = [self expectationWithDescription:@"handlerTestBlockArgument should call callback block"];
    expectation.expectedFulfillmentCount = 1;
    expectation.assertForOverFulfill = YES;
    
    MLHandler* handler = $newHandler([self class], handlerTestBlockArgument);
    $call(handler, $ID(dummyCallback, (^{
        [expectation fulfill];
    })));
    
    [self waitForExpectations:@[expectation] timeout:1.0];
}

$$instance_handler(handlerTestInstanceHandler, testcase, $$ID(HandlerTest*, testcase), $$ID(XCTestExpectation*, expectation), $$ID(monal_void_block_t, someCallback), $$ID(NSString*, dummyObj))
    XCTAssertEqualObjects(dummyObj, @"dummy string", "handler03 should have gotten 'dummy string'");
    [self handlerTestInstanceHandlerSubcall:expectation];
    someCallback();
$$

-(void) handlerTestInstanceHandlerSubcall:(XCTestExpectation*) expectation
{
    [expectation fulfill];
}

-(void) testHandlerInstanceHandler
{
    XCTestExpectation* expectation = [self expectationWithDescription:@"handlerTestInstanceHandler should fulfill this twice"];
    expectation.expectedFulfillmentCount = 2;
    expectation.assertForOverFulfill = YES;
    
    MLHandler* handler = $newHandler(self, handlerTestInstanceHandler, $ID(dummyObj, @"dummy string"));
    $call(handler, $ID(testcase, self), $ID(expectation), $ID(someCallback, (^{
        [expectation fulfill];
    })));
    
    [self waitForExpectations:@[expectation] timeout:1.0];
}

$$class_handler(handlerTestMandatoryArgument, $$ID(monal_void_block_t, dummyCallback))
    dummyCallback();
$$

-(void) testHandlerMandatoryArgument
{
    MLHandler* handler = $newHandler([self class], handlerTestMandatoryArgument);
    XCTAssertThrows(expressify($call(handler, $ID(something, @"something"))), "missing mandatory dummyCallback should trigger an exception");
}

$$class_handler(handlerTestMissingOptionalArgument, $_ID(NSString*, dummy))
    XCTAssertNil(dummy, "missing optional argument should be nil");
$$

-(void) testHandlerMissingOptionalArgument
{
    MLHandler* handler = $newHandler([self class], handlerTestMissingOptionalArgument, $ID(dummy2, @"dummy2"));
    XCTAssertNoThrow(expressify($call(handler, $ID(something, @"something"))), "missing optional dummy argument should not trigger an exception");
}

$$class_handler(handlerTestGivenOptionalArgument, $_ID(NSString*, dummy))
    XCTAssertNotNil(dummy, "given optional argument should not be nil");
$$

-(void) testHandlerGivenOptionalArgument
{
    MLHandler* handler = $newHandler([self class], handlerTestGivenOptionalArgument, $ID(dummy, @"dummy"));
    XCTAssertNoThrow(expressify($call(handler, $ID(something, @"something"))), "giving optional dummy argument should not trigger an exception");
}

$$class_handler(handlerTestWithInvalidation01, $_ID(NSString*, dummy))
    XCTAssertTrue(NO, "this handler should never be called");
$$
$$class_handler(handlerTestWithInvalidationInvalidation01, $_ID(NSString*, something))
    XCTAssertEqualObjects(something, @"something01", "handlerTestWithInvalidationInvalidation01 should have gotten 'something01'");
$$

-(void) testHandlerWithInvalidation01
{
    MLHandler* handler = $newHandlerWithInvalidation([self class], handlerTestWithInvalidation01, handlerTestWithInvalidationInvalidation01, $ID(dummy2, @"dummy2"));
    XCTAssertNoThrow(expressify($invalidate(handler, $ID(something, @"something01"))), "calling an invalidation should not trigger an exception");
    XCTAssertThrows(expressify($call(handler, $ID(something, @"something02"))), "calling a handler after its invaidation should trigger an exception");
    XCTAssertThrows(expressify($invalidate(handler, $ID(something, @"something03"))), "calling an invalidation twice should trigger an exception");
}

$$class_handler(handlerTestWithInvalidation02, $$ID(NSString*, dummy2))
    XCTAssertEqualObjects(dummy2, @"dummy2", "handlerTestWithInvalidation02 should have gotten 'dummy2'");
$$
$$class_handler(handlerTestWithInvalidationInvalidation02, $_ID(NSString*, something))
    XCTAssertEqualObjects(something, @"something02", "invalidation for handlerTestWithInvalidation02 should have gotten 'something02'");
$$

-(void) testHandlerWithInvalidation02
{
    MLHandler* handler = $newHandlerWithInvalidation([self class], handlerTestWithInvalidation02, handlerTestWithInvalidationInvalidation02, $ID(dummy2, @"dummy2"));
    XCTAssertNoThrow(expressify($call(handler, $ID(something, @"something01"))), "calling a handler should not trigger an exception");
    XCTAssertNoThrow(expressify($invalidate(handler, $ID(something, @"something02"))), "calling an invalidation after its handler should not trigger an exception");
    XCTAssertThrows(expressify($invalidate(handler, $ID(something, @"something03"))), "calling an invalidation twice should trigger an exception");
}

@end

#pragma clang diagnostic pop
