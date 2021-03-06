//
//  Version 1.3.3
//
//  Created by Nick Lockwood on 26/01/2011.
//  Copyright 2011 Charcoal Design
//
//  Distributed under the permissive zlib license
//  Get the latest version from either of these locations:
//
//  http://charcoaldesign.co.uk/source/cocoa#irate
//  https://github.com/nicklockwood/iRate
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//  claim that you wrote the original software. If you use this software
//  in a product, an acknowledgment in the product documentation would be
//  appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//  misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//
#import "iRate.h"
#import <Cordova/CDV.h>


static NSString *const iRateRatedVersionKey = @"iRateRatedVersionChecked";
static NSString *const iRateDeclinedVersionKey = @"iRateDeclinedVersion";
static NSString *const iRateLastRemindedKey = @"iRateLastReminded";
static NSString *const iRateLastVersionUsedKey = @"iRateLastVersionUsed";
static NSString *const iRateFirstUsedKey = @"iRateFirstUsed";
static NSString *const iRateUseCountKey = @"iRateUseCount";
static NSString *const iRateEventCountKey = @"iRateEventCount";

static NSString *const iRateMacAppStoreBundleID = @"com.apple.appstore";
static NSString *const iRateAppLookupURLFormat = @"http://itunes.apple.com/%@/lookup";

static NSString *const iRateiOSAppStoreURLScheme = @"itms-apps";
static NSString *const iRateiOSAppStoreURLFormat = @"itms-apps://itunes.apple.com/WebObjects/MZStore.woa/wa/viewContentsUserReviews?type=Purple+Software&id=%@";
static NSString *const iRateiOS7AppStoreURLFormat = @"itms-apps://itunes.apple.com/app/id%@";
static NSString *const iRateMacAppStoreURLFormat = @"macappstore://itunes.apple.com/app/id%@";
static NSString *const iRateiOS8AppStoreURLFormat = @"itms-apps://itunes.apple.com/WebObjects/MZStore.woa/wa/viewContentsUserReviews?id=%d&onlyLatestVersion=true&pageNumber=0&sortOrdering=1&type=Purple+Software";

#define SECONDS_IN_A_DAY 86400.0
#define MAC_APP_STORE_REFRESH_DELAY 5.0


@interface iRate() <UIAlertViewDelegate>


@property (nonatomic, strong) id visibleAlert;

@end


@implementation iRate

@synthesize appStoreID;
@synthesize applicationName;
@synthesize applicationVersion;
@synthesize daysUntilPrompt;
@synthesize usesUntilPrompt;
@synthesize eventsUntilPrompt;
@synthesize remindPeriod;
@synthesize messageTitle;
@synthesize message;
@synthesize cancelButtonLabel;
@synthesize remindButtonLabel;
@synthesize rateButtonLabel;
@synthesize ratingsURL;
@synthesize promptAtLaunch;
@synthesize debug;
@synthesize delegate;
@synthesize visibleAlert;

#pragma mark -
#pragma mark Lifecycle methods



// phonegap plugin launcher with options

- (void)launch:(CDVInvokedUrlCommand *)command
{
    
    
    NSArray* args = [command arguments];
    
    if (args.count > 0) {
        NSMutableDictionary* options = [[command arguments] objectAtIndex:0];
        
        debug =                     [[options objectForKey:@"debug"] boolValue];
        promptAtLaunch =            [[options objectForKey:@"promptAtLaunch"] boolValue];
        usesUntilPrompt =           [[options objectForKey:@"usesUntilPrompt"] intValue];
        eventsUntilPrompt =         [[options objectForKey:@"eventsUntilPrompt"] intValue];
        daysUntilPrompt =           [[options objectForKey:@"daysUntilPrompt"] floatValue];
        remindPeriod =              [[options objectForKey:@"remindPeriod"] floatValue];
        
        self.appStoreID =           [[options objectForKey:@"appStoreID"] intValue];
        
        
        self.messageTitle = [options objectForKey:@"messageTitle"]; //set lazily so that appname can be included
        self.message = [options objectForKey:@"message"]; //set lazily so that appname can be included
        self.cancelButtonLabel = [options objectForKey:@"cancelButtonLabel"];
        self.remindButtonLabel = [options objectForKey:@"remindButtonLabel"];
        self.rateButtonLabel = [options objectForKey :@"rateButtonLabel"];
        
        NSLog(@"[iRate] LAUNCHING %@", args);
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:command.callbackId];
        
    } else {
        
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Invalid Arguments"] callbackId:command.callbackId];
        
    }
    
    
    
    //localised application name and version
    self.applicationVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey];
    self.applicationName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if ([applicationName length] == 0)
    {
        self.applicationName = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey];
    }
    
    //register for iphone application events
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationLaunched:)
                                                 name:UIApplicationDidFinishLaunchingNotification
                                               object:nil];
    
    if (&UIApplicationWillEnterForegroundNotification)
    {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillEnterForeground:)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
    }
    
    [self applicationLaunched:Nil];
    
}




- (NSString *)messageTitle
{
    if ([messageTitle isEqual:[NSNull null]])
    {
        return [NSString stringWithFormat:@"Rate %@", applicationName];
    } else {
        return messageTitle;
    }
    
}

- (NSString *)message
{
    if ([message isEqual:[NSNull null]])
    {
        return [NSString stringWithFormat:@"If you enjoy using %@, would you mind taking a moment to rate it? It won't take more than a minute. Thanks for your support!", applicationName];
        
    } else {
        return message;
    }
}

- (NSURL *)ratingsURL
{
    if (ratingsURL)
    {
        return ratingsURL;
    }
    
    //return [NSURL URLWithString:[NSString stringWithFormat:([[UIDevice currentDevice].systemVersion floatValue] >= 7.0f)? iRateiOS7AppStoreURLFormat: iRateiOSAppStoreURLFormat, @(self.appStoreID)]];
    float devversion = [[UIDevice currentDevice].systemVersion floatValue];
    NSString *reviewURL = nil;
    
    if (devversion < 7.0) {
        reviewURL = [NSString stringWithFormat:iRateiOSAppStoreURLFormat,self.appStoreID];
        return [NSURL URLWithString:reviewURL];
    }
    else if (devversion >= 7.0 && devversion < 8.0){
        reviewURL = [NSString stringWithFormat:iRateiOS7AppStoreURLFormat,self.appStoreID];
        return [NSURL URLWithString:reviewURL];
    }
    else
    {
        reviewURL = [NSString stringWithFormat:iRateiOS8AppStoreURLFormat,self.appStoreID];
        return [NSURL URLWithString:reviewURL];
    }
}

- (NSDate *)firstUsed
{
    return [[NSUserDefaults standardUserDefaults] objectForKey:iRateFirstUsedKey];
}

- (void)setFirstUsed:(NSDate *)date
{
    [[NSUserDefaults standardUserDefaults] setObject:date forKey:iRateFirstUsedKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSDate *)lastReminded
{
    return [[NSUserDefaults standardUserDefaults] objectForKey:iRateLastRemindedKey];
}

- (void)setLastReminded:(NSDate *)date
{
    [[NSUserDefaults standardUserDefaults] setObject:date forKey:iRateLastRemindedKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSUInteger)usesCount
{
    return [[NSUserDefaults standardUserDefaults] integerForKey:iRateUseCountKey];
}

- (void)setUsesCount:(NSUInteger)count
{
    [[NSUserDefaults standardUserDefaults] setInteger:count forKey:iRateUseCountKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSUInteger)eventCount;
{
    return [[NSUserDefaults standardUserDefaults] integerForKey:iRateEventCountKey];
}

- (void)setEventCount:(NSUInteger)count
{
    [[NSUserDefaults standardUserDefaults] setInteger:count forKey:iRateEventCountKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)declinedThisVersion
{
    return [[[NSUserDefaults standardUserDefaults] objectForKey:iRateDeclinedVersionKey] isEqualToString:applicationVersion];
}

- (void)setDeclinedThisVersion:(BOOL)declined
{
    [[NSUserDefaults standardUserDefaults] setObject:(declined? applicationVersion: nil) forKey:iRateDeclinedVersionKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)ratedThisVersion
{
    return [[[NSUserDefaults standardUserDefaults] objectForKey:iRateRatedVersionKey] isEqualToString:applicationVersion];
}

- (void)setRatedThisVersion:(BOOL)rated
{
    [[NSUserDefaults standardUserDefaults] setObject:(rated? applicationVersion: nil) forKey:iRateRatedVersionKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    AH_RELEASE(applicationName);
    AH_RELEASE(applicationVersion);
    AH_RELEASE(messageTitle);
    AH_RELEASE(message);
    AH_RELEASE(cancelButtonLabel);
    AH_RELEASE(remindButtonLabel);
    AH_RELEASE(rateButtonLabel);
    AH_RELEASE(ratingsURL);
    AH_RELEASE(visibleAlert);
    AH_SUPER_DEALLOC;
}

#pragma mark -
#pragma mark Methods

- (void)incrementUseCount
{
    self.usesCount ++;
    NSLog(@"[iRate] self.usesCount %i", self.usesCount);
}

- (void)incrementEventCount
{
    self.eventCount ++;
}

- (BOOL)shouldPromptForRating
{
    //debug mode?
    if (debug)
    {
        return YES;
    }
    
    //check if we've rated this version
    else if (self.ratedThisVersion)
    {
        NSLog(@"[iRate] ratedThisVersion ");
        return NO;
    }
    
    //check if we've declined to rate this version
    else if (self.declinedThisVersion)
    {
        NSLog(@"[iRate] declinedThisVersion ");
        return NO;
    }
    
    //check how long we've been using this version
    else if (self.firstUsed == nil || [[NSDate date] timeIntervalSinceDate:self.firstUsed] < daysUntilPrompt * SECONDS_IN_A_DAY)
    {
        NSLog(@"[iRate] How long ");
        return NO;
    }
    
    //check how many times we've used it and the number of significant events
    else if (self.usesCount < usesUntilPrompt && self.eventCount < eventsUntilPrompt)
    {
        NSLog(@"[iRate] significant event ");
        return NO;
    }
    
    //check if within the reminder period
    else if (self.lastReminded != nil && [[NSDate date] timeIntervalSinceDate:self.lastReminded] < remindPeriod * SECONDS_IN_A_DAY)
    {
        NSLog(@"[iRate] reminder period ");
        return NO;
    }
    
    //lets prompt!
    return YES;
}

- (void)promptForRating
{
    if (!visibleAlert)
    {
        
        self.visibleAlert = [[UIAlertView alloc] initWithTitle:self.messageTitle
                                                       message:self.message
                                                      delegate:self
                                             cancelButtonTitle:cancelButtonLabel
                                             otherButtonTitles:rateButtonLabel, nil];
        
        if (remindButtonLabel)
        {
            [visibleAlert addButtonWithTitle:remindButtonLabel];
        }
        
        [visibleAlert show];
        AH_RELEASE(visibleAlert);
        
        
    }
}

- (void)promptIfNetworkAvailable
{
    //test for app store connectivity the simplest, most reliable way - by accessing apple.com
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://apple.com"]
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:10.0];
    //send request
    [[NSURLConnection connectionWithRequest:request delegate:self] start];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    //good enough; don't download any more data
    [connection cancel];
    
    //confirm with delegate
    if ([delegate respondsToSelector:@selector(iRateShouldPromptForRating)])
    {
        if (![delegate iRateShouldPromptForRating])
        {
            return;
        }
    }
    
    //prompt user
    [self promptForRating];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    //could not connect
    if ([delegate respondsToSelector:@selector(iRateCouldNotConnectToAppStore:)])
    {
        [delegate iRateCouldNotConnectToAppStore:error];
    }
}

- (void)applicationLaunched:(NSNotification *)notification
{
    //check if this is a new version
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![[defaults objectForKey:iRateLastVersionUsedKey] isEqualToString:applicationVersion])
    {
        //reset counts
        [defaults setObject:applicationVersion forKey:iRateLastVersionUsedKey];
        [defaults setObject:[NSDate date] forKey:iRateFirstUsedKey];
        [defaults setInteger:0 forKey:iRateUseCountKey];
        [defaults setInteger:0 forKey:iRateEventCountKey];
        [defaults setObject:nil forKey:iRateLastRemindedKey];
        [defaults synchronize];
    }
    
    [self incrementUseCount];
    NSLog(@"[iRate] INCREMENT");
    if ([self shouldPromptForRating])
    {
        NSLog(@"[iRate] promptIfNetworkAvailable ");
        [self promptIfNetworkAvailable];
    }
}


- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground)
    {
        [self incrementUseCount];
        if ([self shouldPromptForRating])
        {
            [self promptIfNetworkAvailable];
        }
    }
}


#pragma mark -
#pragma mark UIAlertViewDelegate methods


- (void)openRatingsPageInAppStore
{
    [[UIApplication sharedApplication] openURL:self.ratingsURL];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex)
    {
        //log event
        if ([delegate respondsToSelector:@selector(iRateUserDidDeclineToRateApp)])
        {
            [delegate iRateUserDidDeclineToRateApp];
        }
        
        //ignore this version
        self.declinedThisVersion = YES;
    }
    else if (buttonIndex == 2)
    {
        //log event
        if ([delegate respondsToSelector:@selector(iRateUserDidRequestReminderToRateApp)])
        {
            [delegate iRateUserDidRequestReminderToRateApp];
        }
        
        //remind later
        self.lastReminded = [NSDate date];
    }
    else
    {
        //log event
        if ([delegate respondsToSelector:@selector(iRateUserDidAttemptToRateApp)])
        {
            [delegate iRateUserDidAttemptToRateApp];
        }
        
        //mark as rated
        self.ratedThisVersion = YES;
        
        //go to ratings page
        [self openRatingsPageInAppStore];
    }
    
    //release alert
    self.visibleAlert = nil;
}



- (void)logEvent:(BOOL)deferPrompt
{
    [self incrementEventCount];
    if (!deferPrompt && [self shouldPromptForRating])
    {
        [self promptIfNetworkAvailable];
    }
}

@end
