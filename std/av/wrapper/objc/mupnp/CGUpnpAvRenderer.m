//
//  CGUpnpAvServer.m
//  CyberLink for C
//
//  Created by Satoshi Konno on 08/07/02.
//  Copyright 2008 Satoshi Konno. All rights reserved.
//

#include <mupnp/std/av/cmediarenderer.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

#import "CGUpnpAvRenderer.h"
#import "CGUpnpAVPositionInfo.h"
#import "CGUpnpAVPositionInfo.h"
#import "CGUpnpService.h"
#import "CGUpnpAction.h"
#import "CGUpnpAvItem.h"

#define AUDIO_PROTOCOL_M4A @"http-get:*:audio/mp4:*;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=01700000000000000000000000000000"
#define AUDIO_PROTOCOL_MP3 @"http-get:*:audio/mpeg:DLNA.ORG_PN=MP3;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=01700000000000000000000000000000"
#define AUDIO_PROTOCOL_WAV @"http-get:*:audio/wav:*;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=01700000000000000000000000000000"
#define AUDIO_PROTOCOL_AIFF @"http-get:*:audio/x-aiff:*;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=01700000000000000000000000000000"
#define IMAGE_PROTOCOL_JPEG @"http-get:*:image/jpeg:DLNA.ORG_PN=JPEG_LRG;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=01700000000000000000000000000000"


@implementation DMRMediaItem

@end


@interface CGUpnpAvRenderer() {    
    CGUpnpService *avRenderControlService;
    CGUpnpService *avTransportService;
    CGUpnpService *avConnectManagerService;
    BOOL bGeneratingPositionInfoNotifications;
    BOOL bPlayedBySelf;
    BOOL bSeeking;
    BOOL bSkiping;
    
    NSArray<DMRMediaItem *> *sortedPlayerlist;
}

@end

@implementation CGUpnpAvRenderer

@synthesize cAvObject;

- (id)init
{
	if ((self = [super init]) == nil)
		return nil;

	cAvObject = mupnp_upnpav_dmr_new();
	[self setCObject:mupnp_upnpav_dmr_getdevice(cAvObject)];
    
    [self initStatus];
	
	return self;
}

- (id) initWithCObject:(mUpnpDevice *)cobj
{
	if ((self = [super initWithCObject:cobj]) == nil)
		return nil;
    
    [self getDeviceServices];
	cAvObject = NULL;
    
    [self initStatus];

	return self;
}

- (void)initStatus {
    _repeatMode = DMRMusicRepeatModeNone;
    _shuffleMode = DMRMusicShuffleModeOff;
    _playbackState = DMRMusicPlaybackStateStopped;
}

#pragma mark property

- (void)setDelegate:(id<CGUpnpDeviceDelegate>)delegate {
    _avDelegate = (id<CGUpnpAvRenderDelegate>)delegate;
    [super setDelegate:delegate];
}

- (void)setPlayerItemCollection:(NSArray<DMRMediaItem *> *)playerItemCollection {
    _playerItemCollection = playerItemCollection;
    if (DMRMusicShuffleModeOff != self.shuffleMode) {
        sortedPlayerlist = [self shuffleWithPokeMethodFromArray:self.playerItemCollection];
    } else {
        sortedPlayerlist = self.playerItemCollection;
    }
}

- (void)setPlaybackState:(DMRMusicPlaybackState)playbackState {
    _playbackState = playbackState;
    if (DMRMusicPlaybackStateStopped == playbackState) {
        if (self.autoPlayControl &&
            bPlayedBySelf &&
            nil != self.nowPlayingItem &&
            [self.playerItemCollection count] > 0 &&
            ! bSkiping) { // if user pressed next or previous, not jump to next again.
            if (DMRMusicRepeatModeOne == self.repeatMode) {
                [self skipToBeginning];
            } else {
                NSInteger index = 0;
                if (DMRMusicShuffleModeOff != self.shuffleMode) {
                    index = [self indexOfNowPlayingItemInSortedPlaylist];
                } else {
                    index = [self indexOfNowPlayingItem];
                }
                
                if ((DMRMusicRepeatModeAll == self.repeatMode) && (index >= [self.playerItemCollection count] - 1)) {
                    [self skipToFirstItem];
                } else {
                    [self skipToNextItem];
                }
            }
            
        }
    } else if (DMRMusicPlaybackStatePlaying == playbackState) {
        bSkiping = NO;
        [self mediaInfo];
    }
}

- (void)setShuffleMode:(DMRMusicShuffleMode)shuffleMode {
    _shuffleMode = shuffleMode;
    if (DMRMusicShuffleModeOff != shuffleMode) {
        sortedPlayerlist = [self shuffleWithPokeMethodFromArray:self.playerItemCollection];
    } else {
        sortedPlayerlist = self.playerItemCollection;
    }
}

- (void)setTrackURI:(NSString *)trackURI {
    if ([_trackURI isEqualToString:trackURI]) {
        return;
    }
    
    _trackURI = trackURI;
    if (nil != self.nowPlayingItem) {
        if (nil != self.nowPlayingItem.assetURL && [trackURI isEqualToString:self.nowPlayingItem.assetURL]) {
            bPlayedBySelf = YES;
            [self mediaInfoFromNowPlayItem];
            return;
        }
        else if (nil != self.nowPlayingItem.upnpAvItem) {
            NSString *mediaUrl = [[self.nowPlayingItem.upnpAvItem resource] url];
            if (nil != mediaUrl && [trackURI isEqualToString:mediaUrl]) {
                bPlayedBySelf = YES;
                [self mediaInfoFromURLString:trackURI];
                if (nil == self.currentTrackArtwork && nil != self.nowPlayingItem.upnpAvItem.albumArtURI) {
                    NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:self.nowPlayingItem.upnpAvItem.albumArtURI]];
                    if (nil != data) {
                        self.currentTrackArtwork = [UIImage imageWithData:data];
                    }
                }
                return;
            }
        }
    }
    
    bPlayedBySelf = NO;
    [self mediaInfoFromURLString:trackURI];
}

#pragma mark

- (NSUInteger)indexOfNowPlayingItem {
    NSUInteger index = NSNotFound;
    if (nil != self.nowPlayingItem) {
        index = [self.playerItemCollection indexOfObject:self.nowPlayingItem];
    }
    
    return index;
}

- (NSUInteger)indexOfNowPlayingItemInSortedPlaylist {
    NSUInteger index = NSNotFound;
    if (nil != self.nowPlayingItem) {
        index = [sortedPlayerlist indexOfObject:self.nowPlayingItem];
    }
    
    return index;
}

- (void)getDeviceServices
{
    avRenderControlService = [self getServiceForType:@"urn:schemas-upnp-org:service:RenderingControl:1"];
    avTransportService = [self getServiceForType:@"urn:schemas-upnp-org:service:AVTransport:1"];
    avConnectManagerService = [self getServiceForType:@"urn:schemas-upnp-org:service:ConnectionManager:1"];
}

- (CGUpnpAction *)actionOfTransportServiceForName:(NSString *)serviceName
{
	CGUpnpService *avTransService = [self getServiceForType:@"urn:schemas-upnp-org:service:AVTransport:1"];
	if (!avTransService)
		return nil;
	
	return [avTransService getActionForName:serviceName];
}

- (BOOL)setAVTransportWithAvItem:(CGUpnpAvItem *)avItem
{
    if (nil == avItem) {
        return NO;
    }
    
    CGUpnpAction *action = [self actionOfTransportServiceForName:@"SetAVTransportURI"];
    if (!action)
        return NO;
    
    NSString *resourceURL = [[avItem resource] url];
    NSString *metaData = [avItem xmlNodeToString];
    [action setArgumentValue:@"0" forName:@"InstanceID"];
    [action setArgumentValue:resourceURL forName:@"CurrentURI"];
    [action setArgumentValue:metaData forName:@"CurrentURIMetaData"];
    
    if (![action post])
        return NO;
    
    return YES;
}

- (BOOL)setAVTransportURI:(NSString *)aURL;
{
	CGUpnpAction *action = [self actionOfTransportServiceForName:@"SetAVTransportURI"];
	if (!action)
		return NO;
    
	[action setArgumentValue:@"0" forName:@"InstanceID"];
	[action setArgumentValue:aURL forName:@"CurrentURI"];
	[action setArgumentValue:@"" forName:@"CurrentURIMetaData"];
	
	if (![action post])
		return NO;
	
	return YES;
}

- (BOOL)play;
{
	CGUpnpAction *action = [self actionOfTransportServiceForName:@"Play"];
	if (!action)
		return NO;
	
	[action setArgumentValue:@"0" forName:@"InstanceID"];
	[action setArgumentValue:@"1" forName:@"Speed"];
	
	if (![action post])
		return NO;
	
	return YES;
}

- (BOOL)stop;
{
	CGUpnpAction *action = [self actionOfTransportServiceForName:@"Stop"];
	if (!action)
		return NO;
	
	[action setArgumentValue:@"0" forName:@"InstanceID"];
	
	if (![action post])
		return NO;
	
	return YES;
}

- (BOOL)pause
{
	CGUpnpAction *action = [self actionOfTransportServiceForName:@"Pause"];
	if (!action)
		return NO;
	
	[action setArgumentValue:@"0" forName:@"InstanceID"];
	
	if (![action post])
		return NO;
	
	return YES;
}

- (BOOL)seek:(float)relTime
{
    bSeeking = YES;
    BOOL bRet = NO;
	CGUpnpAction *action = [self actionOfTransportServiceForName:@"Seek"];
    if (action) {
//        [action setArgumentValue:@"0" forName:@"InstanceID"];
//        [action setArgumentValue:@"ABS_TIME" forName:@"Unit"];
//        [action setArgumentValue:[NSString stringWithDurationTime:absTime] forName:@"Target"];
        
        [action setArgumentValue:@"0" forName:@"InstanceID"];
        [action setArgumentValue:@"REL_TIME" forName:@"Unit"];
        [action setArgumentValue:[NSString stringWithDurationTime:relTime] forName:@"Target"];
        
        if ([action post]) {
            bRet = YES;
        }
    }
    bSeeking = NO;
    
	return bRet;
}

- (BOOL)isPlaying
{
	if (DMRMusicPlaybackStatePlaying == self.playbackState)
		return YES;
	return NO;
}

- (CGUpnpAVPositionInfo *)positionInfo
{
	CGUpnpAction *action = [self actionOfTransportServiceForName:@"GetPositionInfo"];
	if (!action)
		return nil;
	
	[action setArgumentValue:@"0" forName:@"InstanceID"];
	
	if (![action post])
		return nil;
	
	return [[CGUpnpAVPositionInfo alloc] initWithAction:action];
}

- (BOOL)mediaInfo
{
    BOOL bRet = NO;
    
    CGUpnpAction *action = [self actionOfTransportServiceForName:@"GetMediaInfo"];
    if (action) {
        [action setArgumentValue:@"0" forName:@"InstanceID"];
        
        if ([action post]) {
            bRet = YES;
            NSString *currentURI = [action argumentValueForName:@"CurrentURI"];
            if (nil != currentURI) {
                self.trackURI = currentURI;
            }
            
//            NSString *metaData = [action argumentValueForName:@"CurrentURIMetaData"];
//            NSString *nextURI = [action argumentValueForName:@"NextURI"];
//            NSString *nextMetaData = [action argumentValueForName:@"NextURIMetaData"];
//            NSString *tracks = [action argumentValueForName:@"NrTracks"];
//            NSString *duration = [action argumentValueForName:@"MediaDuration"];
//            NSString *playMedium = [action argumentValueForName:@"PlayMedium"];
//            NSString *writeStatus = [action argumentValueForName:@"WriteStatus"];
//            NSString *recordMedium = [action argumentValueForName:@"RecordMedium"];
        }
    }
    
    return bRet;
}

- (CGUpnpService *)renderControlService
{
    return avRenderControlService;
}

- (CGUpnpService *)transportService
{
    return avTransportService;
}

- (CGUpnpService *)connectionManagerService
{
    return avConnectManagerService;
}

- (CGUpnpService *)serviceWithSubscriptionID:(NSString *)sid
{
    if (nil == sid)
    {
        return nil;
    }
    
    CGUpnpService *service = [self getServiceWithSubscriptionID:sid];
    return service;
}

- (void)mediaInfoFromNowPlayItem {
    if (nil == self.nowPlayingItem) {
        return;
    }
    
    self.currentTrackName = self.nowPlayingItem.mediaItem.title;
    self.currentTrackArtist = self.nowPlayingItem.mediaItem.artist;
    self.currentTrackAlbum = self.nowPlayingItem.mediaItem.albumTitle;
    self.currentTrackArtwork = [self.nowPlayingItem.mediaItem.artwork imageWithSize:CGSizeMake(320, 320)];
}

- (void)mediaInfoFromURLString:(NSString *)url {
    if (nil == url) {
        return;
    }
    
    NSURL *fileURL = [NSURL URLWithString:url];
    AVURLAsset *avAsset = [AVURLAsset URLAssetWithURL:fileURL options:nil];
    NSArray *formatsArray = [avAsset availableMetadataFormats];
    for (NSString *format in formatsArray) {
        NSLog(@"format type = %@", format);
        NSArray *metadataArray = [avAsset metadataForFormat:format];
        for (AVMetadataItem *metadataItem in metadataArray) {
            if ([metadataItem.commonKey isEqualToString:@"artwork"]) {
                self.currentTrackArtwork = [UIImage imageWithData:(NSData *)metadataItem.value];
            } else if ([metadataItem.commonKey isEqualToString:@"albumName"]) {
                self.currentTrackAlbum = (NSString *)metadataItem.value;
            } else if ([metadataItem.commonKey isEqualToString:@"title"]) {
                self.currentTrackName = (NSString *)metadataItem.value;
            } else if ([metadataItem.commonKey isEqualToString:@"artist"]) {
                self.currentTrackArtist = (NSString *)metadataItem.value;
            }
        }
    }
}

/*
- (BOOL)start
{
	if (!cAvObject)
		return NO;
	return cg_upnpav_dms_start(cAvObject);
}

- (BOOL)stop
{
	if (!cAvObject)
		return NO;
	return cg_upnpav_dms_stop(cAvObject);
}
*/

#pragma mark Function for Assistant

- (NSArray<DMRMediaItem *> *)shuffleWithPokeMethodFromArray:(NSArray *)sourceArray {
    NSMutableArray *pokeArray = nil;
    if (nil != sourceArray && [sourceArray count] > 0) {
        pokeArray = [NSMutableArray arrayWithArray:sourceArray];
        NSInteger count = [pokeArray count];
        for (NSInteger i = count - 1; i > 0; i --) {
            NSInteger randId = (NSInteger)(random() / (float)RAND_MAX * i);
            DMRMediaItem *tempItem = [pokeArray objectAtIndex:randId];
            [pokeArray removeObjectAtIndex:randId];
            [pokeArray addObject:tempItem];
        }
    }
    
    return pokeArray;
}

#pragma mark Wrap the render with necessary infomation for playing

- (BOOL)setVolume:(NSInteger)volume {
    if (nil == avRenderControlService) {
        return NO;
    }
    
    CGUpnpAction *action = [avRenderControlService getActionForName:@"SetVolume"];
    if (!action)
        return NO;
    
    [action setArgumentValue:@"0" forName:@"InstanceID"];
    [action setArgumentValue:@"Master" forName:@"Channel"];
    [action setArgumentValue:[NSString stringWithFormat:@"%ld", (long)volume] forName:@"DesiredVolume"];
    
    if (![action post])
        return NO;
    
    return YES;
}

- (void)setNowPlayingItem:(DMRMediaItem *)nowPlayingItem {
    bPlayedBySelf = YES;
    _nowPlayingItem = nowPlayingItem;
    if (nil != nowPlayingItem.upnpAvItem) { // from UPnP AV Server
        [self setAVTransportWithAvItem:nowPlayingItem.upnpAvItem];
        [self play];
    } else if (nil != nowPlayingItem.assetURL) { // from Local iOS Device
        [self setAVTransportURI:nowPlayingItem.assetURL];
        [self play];
    }
}

- (void)playMusicWithIndex:(NSInteger)index {
    if (index < [self.playerItemCollection count]) {
        DMRMediaItem *item = [self.playerItemCollection objectAtIndex:index];
        [self playMusicWithDMRMediaItem:item];
    }
}

- (void)playMusicWithDMRMediaItem:(DMRMediaItem *)item {
    if ([self.playerItemCollection containsObject:item]) {
        // for iOS need to export local music to configure the resource url.
        if ([self.avDelegate respondsToSelector:@selector(upnpAvRender:preparingToPlayItem:)]) {
            [self.avDelegate upnpAvRender:self preparingToPlayItem:item];
        }
        
        bSkiping = YES;
        [self setNowPlayingItem:item];
    }
}

- (DMRMediaItem *)itemAtIndex:(NSInteger)index {
    DMRMediaItem *item = nil;
    if (index < [self.playerItemCollection count]) {
        item = [self.playerItemCollection objectAtIndex:index];
    }
    return item;
}

- (void)skipToNextItem {
    if (DMRMusicShuffleModeOff != self.repeatMode) {
        NSUInteger index = [self indexOfNowPlayingItemInSortedPlaylist];
        if (++ index < [sortedPlayerlist count]) {
            DMRMediaItem *item = [sortedPlayerlist objectAtIndex:index];
            [self playMusicWithDMRMediaItem:item];
        }
    } else {
        NSUInteger index = [self indexOfNowPlayingItem];
        if (++ index < [self.playerItemCollection count]) {
            DMRMediaItem *item = [self.playerItemCollection objectAtIndex:index];
            [self playMusicWithDMRMediaItem:item];
        }
    }
}

- (void)skipToFirstItem {
    if (DMRMusicShuffleModeOff != self.repeatMode) {
        if ([sortedPlayerlist count] > 0) {
            DMRMediaItem *item = [sortedPlayerlist objectAtIndex:0];
            [self playMusicWithDMRMediaItem:item];
        }
    } else {
        if ([self.playerItemCollection count] > 0) {
            DMRMediaItem *item = [self.playerItemCollection objectAtIndex:0];
            [self playMusicWithDMRMediaItem:item];
        }
    }
}

- (void)skipToBeginning {
    if (nil != self.nowPlayingItem) {
        DMRMediaItem *item = self.nowPlayingItem;
        [self setNowPlayingItem:item];
    }
}

- (void)skipToPreviousItem {
    if (DMRMusicShuffleModeOff != self.shuffleMode) {
        NSUInteger index = [self indexOfNowPlayingItemInSortedPlaylist];
        if (index > 0) {
            DMRMediaItem *item = [sortedPlayerlist objectAtIndex:index];
            [self playMusicWithDMRMediaItem:item];
        }
    } else {
        NSUInteger index = [self indexOfNowPlayingItem];
        if (index > 0) {
            DMRMediaItem *item = [self.playerItemCollection objectAtIndex:index];
            [self playMusicWithDMRMediaItem:item];
        }
    }
}

- (void)beginGeneratingPlaybackNotifications {
    if (! bGeneratingPositionInfoNotifications) {
        bGeneratingPositionInfoNotifications = YES;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            while (bGeneratingPositionInfoNotifications) {
                sleep(1);
                if (bSeeking) {
                    continue;
                }
                CGUpnpAVPositionInfo *positionInfo = [self positionInfo];
                self.currentPlaybackTime = positionInfo.relTime;
                self.trackDuration = positionInfo.trackDuration;
                
                if ([self.avDelegate respondsToSelector:@selector(upnpAvRenderDidPositionInfoUpdated:)])
                {
                    [self.avDelegate upnpAvRenderDidPositionInfoUpdated:self];
                }
            }
        });
    }
}

- (void)endGeneratingPlaybackNotifications {
    bGeneratingPositionInfoNotifications = NO;
}

@end
