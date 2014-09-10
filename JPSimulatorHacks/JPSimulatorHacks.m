//
//  JPSimulatorHacks.m
//  JPSimulatorHacks
//
//  Created by Johannes Plunien on 04/06/14.
//  Copyright (C) 2014 Johannes Plunien
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import <AssetsLibrary/AssetsLibrary.h>
#import <FMDB/FMDB.h>
#import "JPSimulatorHacks.h"

@implementation JPSimulatorHacks

static NSString * const JPSimulatorHacksServiceAddressBook = @"kTCCServiceAddressBook";
static NSString * const JPSimulatorHacksServicePhotos = @"kTCCServicePhotos";
static NSTimeInterval JPSimulatorHacksTimeout = 15.0f;

#pragma mark - Public

+ (ALAsset *)addAssetWithURL:(NSURL *)imageURL
{
    __block ALAsset *asset;
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    NSData *imageData = [NSData dataWithContentsOfURL:imageURL];

    NSTimeInterval timeout = JPSimulatorHacksTimeout;
    NSDate *expiryDate = [NSDate dateWithTimeIntervalSinceNow:timeout];

    while (!asset) {
        if(([(NSDate *)[NSDate date] compare:expiryDate] == NSOrderedDescending)) {
            break;
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];

        [library writeImageDataToSavedPhotosAlbum:imageData metadata:nil completionBlock:^(NSURL *assetURL, NSError *error) {
            [library assetForURL:assetURL resultBlock:^(ALAsset *inAsset) {
                asset = inAsset;
            } failureBlock:nil];
        }];
    }

    return asset;
}

+ (void)editGlobalPreferences:(void (^)(NSMutableDictionary *preferences))block
{
    [self editPlist:[self pathToGlobalPreferences] block:block];
}

+ (void)editPreferences:(void (^)(NSMutableDictionary *preferences))block
{
    [self editPlist:[self pathToPreferences] block:block];
}

+ (BOOL)grantAccessToAddressBook
{
    return [self changeAccessToService:JPSimulatorHacksServiceAddressBook
                      bundleIdentifier:[NSBundle mainBundle].bundleIdentifier
                               allowed:YES];
}

+ (BOOL)grantAccessToAddressBookForBundleIdentifier:(NSString *)bundleIdentifier
{
    return [self changeAccessToService:JPSimulatorHacksServiceAddressBook
                      bundleIdentifier:bundleIdentifier
                               allowed:YES];
}

+ (BOOL)grantAccessToPhotos
{
    return [self changeAccessToService:JPSimulatorHacksServicePhotos
                      bundleIdentifier:[NSBundle mainBundle].bundleIdentifier
                               allowed:YES];
}

+ (BOOL)grantAccessToPhotosForBundleIdentifier:(NSString *)bundleIdentifier
{
    return [self changeAccessToService:JPSimulatorHacksServicePhotos
                      bundleIdentifier:bundleIdentifier
                               allowed:YES];
}

+ (void)setTimeout:(NSTimeInterval)timeout
{
    JPSimulatorHacksTimeout = timeout;
}

+ (void)disableKeyboardHelpers
{
    [self editPreferences:^(NSMutableDictionary *preferences) {
        [preferences setValue:@NO forKey:@"KeyboardAutocapitalization"];
        [preferences setValue:@NO forKey:@"KeyboardAutocorrection"];
        [preferences setValue:@NO forKey:@"KeyboardCapsLock"];
        [preferences setValue:@NO forKey:@"KeyboardCheckSpelling"];
        [preferences setValue:@NO forKey:@"KeyboardPeriodShortcut"];
        [preferences setValue:@YES forKey:@"UIKeyboardDidShowInternationalInfoAlert"];
    }];
}

+ (void)setDefaultKeyboard:(NSString *)keyboard
{
    [self editPreferences:^(NSMutableDictionary *preferences) {
        preferences[@"KeyboardLastUsed"] = keyboard;
        preferences[@"KeyboardLastChosen"] = keyboard;
        preferences[@"KeyboardsCurrentAndNext"] = @[keyboard];
    }];

    [self editGlobalPreferences:^(NSMutableDictionary *preferences) {
        NSArray *keyboards = preferences[@"AppleKeyboards"];
        preferences[@"AppleKeyboards"] = [keyboards arrayByAddingObject:keyboard];
    }];
}

#pragma mark - Private

+ (BOOL)changeAccessToService:(NSString *)service
             bundleIdentifier:(NSString *)bundleIdentifier
                      allowed:(BOOL)allowed
{
#if !(TARGET_IPHONE_SIMULATOR)
    return NO;
#endif

    BOOL success = NO;
    NSDate *start = [NSDate date];

    while (!success) {
        NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:start];
        if (elapsed > JPSimulatorHacksTimeout) break;

        if (![[NSFileManager defaultManager] fileExistsAtPath:[self pathToTCCDB] isDirectory:nil]) continue;

        FMDatabase *db = [FMDatabase databaseWithPath:[self pathToTCCDB]];
        if (![db open]) continue;
        if (![db goodConnection]) continue;

        NSString *query = @"REPLACE INTO access (service, client, client_type, allowed, prompt_count) VALUES (?, ?, ?, ?, ?)";
        NSArray *parameters = @[service, bundleIdentifier, @"0", [@(allowed) stringValue], @"0"];
        if ([db executeUpdate:query withArgumentsInArray:parameters]) {
            success = YES;
        }
        else {
            NSLog(@"JPSimulatorHacks ERROR: %@", [db lastErrorMessage]);
        }

        [db close];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }

    return success;
}

+ (void)editPlist:(NSString *)plistPath block:(void (^)(NSMutableDictionary *))block
{
#if !(TARGET_IPHONE_SIMULATOR)
    return;
#endif

    [self waitForFile:plistPath];

    NSMutableDictionary *preferences = [[NSDictionary dictionaryWithContentsOfFile:plistPath] mutableCopy];
    block(preferences);

    NSData *data = [NSPropertyListSerialization dataWithPropertyList:preferences
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:nil];
    [data writeToFile:plistPath atomically:YES];
}

+ (NSString *)pathToPreferences
{
    NSURL *mainBundleURL = [NSBundle mainBundle].bundleURL;
    NSURL *relativePreferencesURL = [mainBundleURL URLByAppendingPathComponent:@"../../../Library/Preferences/com.apple.Preferences.plist"];
    return [[relativePreferencesURL URLByStandardizingPath] path];
}

+ (NSString *)pathToGlobalPreferences
{
    NSURL *mainBundleURL = [NSBundle mainBundle].bundleURL;
    NSURL *relativePreferencesURL = [mainBundleURL URLByAppendingPathComponent:@"../../../Library/Preferences/.GlobalPreferences.plist"];
    return [[relativePreferencesURL URLByStandardizingPath] path];
}

+ (NSString *)pathToTCCDB
{
    NSURL *mainBundleURL = [NSBundle mainBundle].bundleURL;
    NSURL *relativeTCCDBURL = [mainBundleURL URLByAppendingPathComponent:@"../../../Library/TCC/TCC.db"];
    return [[relativeTCCDBURL URLByStandardizingPath] path];
}

+ (BOOL)waitForFile:(NSString *)filePath
{
    BOOL success = NO;
    NSDate *start = [NSDate date];

    while (!success) {
        NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:start];
        if (elapsed > JPSimulatorHacksTimeout) break;
        if (![[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:nil]) continue;

        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
        if ([attributes valueForKey:NSFileSize] == 0) continue;

        success = YES;
    }

    return success;
}

@end
