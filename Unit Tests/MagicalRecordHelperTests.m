//
//  MagicalRecordHelperTests.m
//  Magical Record
//
//  Created by Saul Mora on 7/15/11.
//  Copyright 2011 Magical Panda Software LLC. All rights reserved.
//

#import "MagicalRecordHelperTests.h"

@implementation MagicalRecordHelperTests

- (void) setUp
{
    [NSManagedObjectModel setDefaultManagedObjectModel:[NSManagedObjectModel managedObjectModelNamed:@"TestModel.momd"]];
}

- (void) tearDown
{
    [MagicalRecordHelpers cleanUp];
    //delete temp store
}

- (void) assertDefaultStack
{
    assertThat([NSManagedObjectContext defaultContext], is(notNilValue()));
    assertThat([NSManagedObjectModel MR_defaultManagedObjectModel], is(notNilValue()));
    assertThat([NSPersistentStoreCoordinator MR_defaultStoreCoordinator], is(notNilValue()));
    assertThat([NSPersistentStore defaultPersistentStore], is(notNilValue()));
}

- (void) testCreateDefaultCoreDataStack
{
    [MagicalRecordHelpers setupCoreDataStack];

    [self assertDefaultStack];

    NSPersistentStore *defaultStore = [NSPersistentStore defaultPersistentStore];
    assertThat([[defaultStore URL] absoluteString], endsWith(kMagicalRecordDefaultStoreFileName));
    assertThat([defaultStore type], is(equalTo(NSSQLiteStoreType)));
}

- (void) testCreateInMemoryCoreDataStack
{
    [MagicalRecordHelpers setupCoreDataStackWithInMemoryStore];

    [self assertDefaultStack];

    NSPersistentStore *defaultStore = [NSPersistentStore defaultPersistentStore];
    assertThat([defaultStore type], is(equalTo(NSInMemoryStoreType)));
}

- (void) testCreateSqliteStackWithCustomName
{
    NSString *testStoreName = @"MyTestDataStore.sqlite";
    [MagicalRecordHelpers setupCoreDataStackWithStoreNamed:testStoreName];

    [self assertDefaultStack];

    NSPersistentStore *defaultStore = [NSPersistentStore defaultPersistentStore];
    assertThat([defaultStore type], is(equalTo(NSSQLiteStoreType)));
    assertThat([[defaultStore URL] absoluteString], endsWith(testStoreName));
}


- (void) testCanSetAUserSpecifiedErrorHandler
{
    [MagicalRecordHelpers setErrorHandlerTarget:self action:@selector(customErrorHandler:)];

    assertThat([MagicalRecordHelpers errorHandlerTarget], is(equalTo(self)));
    assertThat(NSStringFromSelector([MagicalRecordHelpers errorHandlerAction]), is(equalTo(NSStringFromSelector(@selector(customErrorHandler:)))));
}

- (void) magicalRecordErrorHandlerTest:(NSError *)error
{
    assertThat(error, is(notNilValue()));
    assertThat([error domain], is(equalTo(@"MRTests")));
    assertThatInteger([error code], is(equalToInteger(1000)));
    errorHandlerWasCalled_ = YES;
}

- (void) testUserSpecifiedErrorHandlersAreTriggeredOnError
{
    errorHandlerWasCalled_ = NO;
    [MagicalRecordHelpers setErrorHandlerTarget:self action:@selector(magicalRecordErrorHandlerTest:)];

    NSError *testError = [NSError errorWithDomain:@"MRTests" code:1000 userInfo:nil];
    [MagicalRecordHelpers handleErrors:testError];

    assertThatBool(errorHandlerWasCalled_, is(equalToBool(YES)));
}

- (void) testLogsErrorsToLogger
{
    GHFail(@"Test Not Implemented");
}

@end
