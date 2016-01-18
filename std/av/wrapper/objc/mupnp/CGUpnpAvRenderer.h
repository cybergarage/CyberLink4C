//
//  CGUpnpAvServer.h
//  CyberLink for C
//
//  Created by Satoshi Konno on 08/07/02.
//  Copyright 2008 Satoshi Konno. All rights reserved.
//

#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>

#import <mUPnP/CGUPnPDevice.h>
#import <mUPnP/CGUpnpAVPositionInfo.h>

#import <MediaPlayer/MPMediaItem.h>

@class CGUpnpAVPositionInfo;
@class CGUpnpAvItem;

typedef enum : NSUInteger {
    DMRMusicPlaybackStateStopped,
    DMRMusicPlaybackStateTransitioning,
    DMRMusicPlaybackStatePlaying,
    DMRMusicPlaybackStatePaused,
    DMRMusicPlaybackStateInterrupted,
    DMRMusicPlaybackStateSeekingForward,
    DMRMusicPlaybackStateSeekingBackward
} DMRMusicPlaybackState;

typedef enum : NSUInteger {
    DMRMusicRepeatModeNone,
    DMRMusicRepeatModeOne,
    DMRMusicRepeatModeAll,
} DMRMusicRepeatMode;

typedef enum : NSUInteger {
    DMRMusicShuffleModeOff,
    DMRMusicShuffleModeSongs,
} DMRMusicShuffleMode;


@interface DMRMediaItem : NSObject

@property (nonatomic, retain) NSString *assetURL; // a http url to access music
@property (nonatomic, retain) MPMediaItem *mediaItem; // For choose local music to play
@property (nonatomic, retain) CGUpnpAvItem *upnpAvItem; // For music from DMS or network

@end


@protocol CGUpnpAvRenderDelegate;


#if !defined(_CG_CLINKCAV_MEDIARENDERER_H_)
typedef void mUpnpAvRenderer;
#endif

/**
 * The CGUpnpAvRenderer class is a UPnP/AV media server class.
 */
@interface CGUpnpAvRenderer : CGUpnpDevice
{
}

@property (assign,readonly) mUpnpAvRenderer *cAvObject;
@property (nonatomic, weak) id<CGUpnpAvRenderDelegate> avDelegate;

// Player Setting
@property (nonatomic, retain) NSArray<DMRMediaItem *> *playerItemCollection;
@property (nonatomic, retain) DMRMediaItem *nowPlayingItem;
@property (nonatomic, readonly) NSUInteger indexOfNowPlayingItem; // return NSNotFound if the index is not valid
@property (nonatomic) float currentVolume;
@property (nonatomic) float trackDuration;
@property (nonatomic) float currentPlaybackTime;
@property (nonatomic) DMRMusicPlaybackState playbackState;

@property (nonatomic, assign) BOOL autoPlayControl;
@property (nonatomic) DMRMusicRepeatMode repeatMode;
@property (nonatomic) DMRMusicShuffleMode shuffleMode;

// Media Info
@property (nonatomic, retain) NSString *currentTrackName;
@property (nonatomic, retain) NSString *currentTrackAlbum;
@property (nonatomic, retain) NSString *currentTrackArtist;
@property (nonatomic, retain) UIImage *currentTrackArtwork;
@property (nonatomic, retain) NSString *trackURI;

- (id)init;
- (id)initWithCObject:(mUpnpDevice *)cobj;
- (BOOL)play;
- (BOOL)stop;
- (BOOL)pause;
- (BOOL)seek:(float)relTime;
- (BOOL)isPlaying;
- (BOOL)setVolume:(NSInteger)volume;
/*
- (BOOL)start
- (BOOL)stop
*/

- (CGUpnpService *)renderControlService;
- (CGUpnpService *)transportService;
- (CGUpnpService *)connectionManagerService;
- (CGUpnpService *)serviceWithSubscriptionID:(NSString *)sid;

/**
 * Wrap the render with necessary infomation for playing by jink2005@163.com
 */

- (void)playMusicWithIndex:(NSInteger)index;
- (void)playMusicWithDMRMediaItem:(DMRMediaItem *)item;
- (DMRMediaItem *)itemAtIndex:(NSInteger)index;
- (void)skipToNextItem; //If already at the last item, will end playback.
- (void)skipToFirstItem;
- (void)skipToBeginning; // Restarts playback at the beginning of the currently playing media item.
- (void)skipToPreviousItem; // If already at the first item, this will end playback.

// These methods determine whether playback notifications will be generated.
// Calls to begin/endGeneratingPlaybackNotifications are nestable.
- (void)beginGeneratingPlaybackNotifications;
- (void)endGeneratingPlaybackNotifications;

@end


@protocol CGUpnpAvRenderDelegate <NSObject>

@optional
- (void)upnpAvRenderDidPositionInfoUpdated:(CGUpnpAvRenderer *)renderer;
- (void)upnpAvRender:(CGUpnpAvRenderer *)renderer preparingToPlayItem:(DMRMediaItem *)item;

@end