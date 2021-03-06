//
//  NSManagedObjectContext+MagicalRecord.m
//
//  Created by Saul Mora on 11/23/09.
//  Copyright 2010 Magical Panda Software, LLC All rights reserved.
//

#import "CoreData+MagicalRecord.h"
#import <objc/runtime.h>

static NSManagedObjectContext *defaultManageObjectContext = nil;
static NSString const * kMagicalRecordManagedObjectContextKey = @"MagicalRecord_NSManagedObjectContextForThreadKey";

@implementation NSManagedObjectContext (MagicalRecord)

+ (NSManagedObjectContext *)defaultContext
{
//    NSAssert([NSThread isMainThread], @"The defaultContext must only be accessed on the **Main Thread**");
	@synchronized (self)
	{
		if (defaultManageObjectContext)
		{
			return defaultManageObjectContext;
		}
	}
	return nil;
}

+ (void) setDefaultContext:(NSManagedObjectContext *)moc
{
	if (defaultManageObjectContext != moc) 
	{
		defaultManageObjectContext = moc;
	}
}

+ (void) resetDefaultContext
{
    void (^resetBlock)(void) = ^{
        [[NSManagedObjectContext defaultContext] reset];        
    };
    
    dispatch_async(dispatch_get_current_queue(), resetBlock);
}

+ (void) resetContextForCurrentThread 
{
    [[NSManagedObjectContext contextForCurrentThread] reset];
}

+ (NSManagedObjectContext *) contextForCurrentThread
{
	if ([NSThread isMainThread])
	{
		return [self defaultContext];
	}
	else
	{
		NSMutableDictionary *threadDict = [[NSThread currentThread] threadDictionary];
		NSManagedObjectContext *threadContext = [threadDict objectForKey:kMagicalRecordManagedObjectContextKey];
		if (threadContext == nil)
		{
			threadContext = [self contextThatNotifiesDefaultContextOnMainThread];
			[threadDict setObject:threadContext forKey:kMagicalRecordManagedObjectContextKey];
		}
		return threadContext;
	}
}

- (void) observeContext:(NSManagedObjectContext *)otherContext
{
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(mergeChangesFromNotification:)
												 name:NSManagedObjectContextDidSaveNotification
											   object:otherContext];
}

- (void) observeContextOnMainThread:(NSManagedObjectContext *)otherContext
{
    //	ARLog(@"Start Observing on Main Thread");
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(mergeChangesOnMainThread:)
												 name:NSManagedObjectContextDidSaveNotification
											   object:otherContext];
}

- (void) stopObservingContext:(NSManagedObjectContext *)otherContext
{
    //	ARLog(@"Stop Observing Context");
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:NSManagedObjectContextDidSaveNotification
												  object:otherContext];
}

- (void) mergeChangesFromNotification:(NSNotification *)notification
{
	ARLog(@"Merging changes to %@context%@", 
          self == [NSManagedObjectContext defaultContext] ? @"*** DEFAULT *** " : @"",
          ([NSThread isMainThread] ? @" *** on Main Thread ***" : @""));
    
	[self mergeChangesFromContextDidSaveNotification:notification];
}

- (void) mergeChangesOnMainThread:(NSNotification *)notification
{
	if ([NSThread isMainThread])
	{
		[self mergeChangesFromNotification:notification];
	}
	else
	{
		[self performSelectorOnMainThread:@selector(mergeChangesFromNotification:) withObject:notification waitUntilDone:YES];
	}
}

- (BOOL) save
{
	NSError *error = nil;
	BOOL saved = NO;
	@try
	{
		ARLog(@"Saving %@Context%@", 
              self == [[self class] defaultContext] ? @" *** Default *** ": @"", 
              ([NSThread isMainThread] ? @" *** on Main Thread ***" : @""));
        
		saved = [self save:&error];
	}
	@catch (NSException *exception)
	{
		ARLog(@"Problem saving: %@", (id)[exception userInfo] ?: (id)[exception reason]);
	}

	[MagicalRecordHelpers handleErrors:error];

	return saved && error == nil;
}

#ifdef NS_BLOCKS_AVAILABLE
- (BOOL) saveWithErrorHandler:(void(^)(NSError *))errorCallback
{
	NSError *error = nil;
	BOOL saved = NO;
	
	@try
	{
		saved = [self save:&error];
	}
	@catch (NSException *exception)
	{
		ARLog(@"Problem saving: %@", (id)[exception userInfo] ?: (id)[exception reason]);	
	}
	
	if (!saved && errorCallback)
	{
		errorCallback(error);
	}
	else
	{
		[MagicalRecordHelpers handleErrors:error];
	}
	return saved && error == nil;
}
#endif

- (void) saveWrapper
{
#ifndef __has_feature
#define __has_feature(x) 0  // Compatibility with non-clang compilers.
#endif
#if __has_feature(objc_arc)
    @autoreleasepool
    {
        [self save];
    }
#else
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [self save];
    [pool drain];
#endif
}

- (BOOL) saveOnBackgroundThread
{
	[self performSelectorInBackground:@selector(saveWrapper) withObject:nil];

	return YES;
}

- (BOOL) saveOnMainThread
{
	@synchronized(self)
	{
		[self performSelectorOnMainThread:@selector(saveWrapper) withObject:nil waitUntilDone:YES];
	}

	return YES;
}

- (BOOL) notifiesMainContextOnSave
{
    NSNumber *notifies = objc_getAssociatedObject(self, @"notifiesMainContext");
    return notifies ? [notifies boolValue] : NO;
}

- (void) setNotifiesMainContextOnSave:(BOOL)enabled
{
    NSManagedObjectContext *mainContext = [[self class] defaultContext];
    if (self != mainContext) 
    {
        SEL selector = enabled ? @selector(observeContextOnMainThread:) : @selector(stopObservingContext:);
        objc_setAssociatedObject(self, @"notifiesMainContext", [NSNumber numberWithBool:enabled], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [mainContext performSelector:selector withObject:self];
    }
}

+ (NSManagedObjectContext *) contextWithStoreCoordinator:(NSPersistentStoreCoordinator *)coordinator
{
	NSManagedObjectContext *context = nil;
    if (coordinator != nil)
	{
        ARLog(@"Creating MOContext %@", [NSThread isMainThread] ? @" *** On Main Thread ***" : @"");
        context = [[NSManagedObjectContext alloc] init];
        [context setPersistentStoreCoordinator:coordinator];
    }
    return context;
}

+ (NSManagedObjectContext *) contextThatNotifiesDefaultContextOnMainThreadWithCoordinator:(NSPersistentStoreCoordinator *)coordinator;
{
    NSManagedObjectContext *context = [self contextWithStoreCoordinator:coordinator];
    context.notifiesMainContextOnSave = YES;
    return context;
}

+ (NSManagedObjectContext *) context
{
	return [self contextWithStoreCoordinator:[NSPersistentStoreCoordinator MR_defaultStoreCoordinator]];
}

+ (NSManagedObjectContext *) contextThatNotifiesDefaultContextOnMainThread
{
    NSManagedObjectContext *context = [self context];
    context.notifiesMainContextOnSave = YES;
    return context;
}

@end
