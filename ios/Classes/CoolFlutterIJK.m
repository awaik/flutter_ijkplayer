//
// Created by Caijinglong on 2019-03-08.
//

#import "CoolFlutterIJK.h"
#import "CoolVideoInfo.h"
#import "CoolIjkNotifyChannel.h"
#import <IJKMediaFramework/IJKMediaFramework.h>
#import <IJKMediaFramework/IJKMediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <libkern/OSAtomic.h>

@interface CoolFlutterIJK () <FlutterTexture, KKIjkNotifyDelegate>
@end

@implementation CoolFlutterIJK {
    int64_t textureId;
    CADisplayLink *displayLink;
    NSObject <FlutterTextureRegistry> *textures;
    IJKFFMoviePlayerController *controller;
    CVPixelBufferRef latestPixelBuffer;
    FlutterMethodChannel *channel;
    CoolIjkNotifyChannel *notifyChannel;
    int degree;
}

- (instancetype)initWithRegistrar:(NSObject <FlutterPluginRegistrar> *)registrar {
    self = [super init];
    if (self) {
        self.registrar = registrar;
        textures = [self.registrar textures];
        textureId = [textures registerTexture:self];
        NSString *channelName = [NSString stringWithFormat:@"top.kikt/ijkplayer/%lli", textureId];
        channel = [FlutterMethodChannel methodChannelWithName:channelName binaryMessenger:[registrar messenger]];
        [channel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
            [self handleMethodCall:call result:result];
        }];
    }

    return self;
}


- (void)dispose {
    [notifyChannel dispose];
    [[self.registrar textures] unregisterTexture:self.id];
    [controller stop];
    [controller shutdown];
    controller = nil;
    displayLink.paused = YES;
    [displayLink invalidate];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([@"play" isEqualToString:call.method]) {
        [self play];
        result(@(YES));
    } else if ([@"pause" isEqualToString:call.method]) {
        [self pause];
        result(@(YES));
    } else if ([@"stop" isEqualToString:call.method]) {
        [self stop];
        result(@(YES));
    } else if ([@"setNetworkDataSource" isEqualToString:call.method]) {
        @try {
            NSDictionary *params = call.arguments;
            NSString *uri = params[@"uri"];
            [self setDataSourceWithUri:uri];
            result(@(YES));
        }
        @catch (NSException *exception) {
            NSLog(@"Exception occurred: %@, %@", exception, [exception userInfo]);
            result([FlutterError errorWithCode:@"1" message:@"设置失败" details:nil]);
        }
    } else if ([@"setAssetDataSource" isEqualToString:call.method]) {
        @try {
            NSDictionary *params = [call arguments];
            NSString *name = params[@"name"];
            NSString *pkg = params[@"package"];
            IJKFFMoviePlayerController *playerController = [self createControllerWithAssetName:name pkg:pkg];
            [self setDataSourceWithController:playerController];
            result(@(YES));
        }
        @catch (NSException *exception) {
            NSLog(@"Exception occurred: %@, %@", exception, [exception userInfo]);
            result([FlutterError errorWithCode:@"1" message:@"设置失败" details:nil]);
        }
    } else if ([@"setFileDataSource" isEqualToString:call.method]) {
        NSDictionary *params = call.arguments;
        NSString *path = params[@"path"];
        IJKFFMoviePlayerController *playerController = [self createControllerWithPath:path];
        [self setDataSourceWithController:playerController];
        result(@(YES));
    } else if ([@"seekTo" isEqualToString:call.method]) {
        NSDictionary *params = call.arguments;
        double target = [params[@"target"] doubleValue];
        [self seekTo:target];
        result(@(YES));
    } else if ([@"getInfo" isEqualToString:call.method]) {
        CoolVideoInfo *info = [self getInfo];
        result([info toMap]);
    } else if ([@"setVolume" isEqualToString:call.method]) {
        NSDictionary *params = [self params:call];
        float v = [params[@"volume"] floatValue] / 100;
        controller.playbackVolume = v;
        result(@(YES));
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (NSDictionary *)params:(FlutterMethodCall *)call {
    return call.arguments;
}

+ (instancetype)ijkWithRegistrar:(NSObject <FlutterPluginRegistrar> *)registrar {
    return [[self alloc] initWithRegistrar:registrar];
}

- (int64_t)id {
    return textureId;
}

- (void)play {
    [controller play];
}

- (void)pause {
    [controller pause];
}

- (void)stop {
    [controller stop];
}

- (void)setDataSourceWithController:(IJKFFMoviePlayerController *)ctl {
    if (ctl) {
        controller = ctl;
        [self prepare];
    }
}

- (IJKFFOptions *)createOption {
    IJKFFOptions *options = [IJKFFOptions optionsByDefault];
    return options;
}

- (void)setDataSourceWithUri:(NSString *)uri {
    IJKFFOptions *options = [self createOption];
    controller = [[IJKFFMoviePlayerController alloc] initWithContentURLString:uri withOptions:options];
    [self prepare];
}

- (void)setDegree:(int)d {
    degree = d;
}


- (void)prepare {
    [controller prepareToPlay];
    if (displayLink) {
        displayLink.paused = YES;
        [displayLink invalidate];
        displayLink = nil;
    }

    displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onDisplayLink:)];
    [displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    displayLink.paused = YES;

    notifyChannel = [CoolIjkNotifyChannel channelWithController:controller textureId:textureId registrar:self.registrar];
    notifyChannel.infoDelegate = self;
}

- (IJKFFMoviePlayerController *)createControllerWithAssetName:(NSString *)assetName pkg:(NSString *)pkg {
    NSString *asset;
    if (!pkg) {
        asset = [self.registrar lookupKeyForAsset:assetName];
    } else {
        asset = [self.registrar lookupKeyForAsset:assetName fromPackage:pkg];
    }
    NSString *path = [[NSBundle mainBundle] pathForResource:asset ofType:nil];
    NSURL *url = [NSURL fileURLWithPath:path];

    IJKFFOptions *options = [self createOption];

    return [[IJKFFMoviePlayerController alloc] initWithContentURL:url withOptions:options];
}


- (IJKFFMoviePlayerController *)createControllerWithPath:(NSString *)path {
    NSURL *url = [NSURL fileURLWithPath:path];
    IJKFFOptions *options = [self createOption];
    return [[IJKFFMoviePlayerController alloc] initWithContentURL:url withOptions:options];
}

- (void)seekTo:(double)target {
    [controller setCurrentPlaybackTime:target];
}

- (void)onDisplayLink:(CADisplayLink *)link {
    [textures textureFrameAvailable:textureId];
}

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
    CVPixelBufferRef newBuffer = [controller framePixelbuffer];
    if (newBuffer) {
        CFRetain(newBuffer);
        CVPixelBufferRef pixelBuffer = latestPixelBuffer;
        while (!OSAtomicCompareAndSwapPtrBarrier(pixelBuffer, newBuffer, (void **) &latestPixelBuffer)) {
            pixelBuffer = latestPixelBuffer;
        }

        return pixelBuffer;
    }
    return NULL;
}

- (CoolVideoInfo *)getInfo {
    CoolVideoInfo *info = [CoolVideoInfo new];

    CGSize size = [controller naturalSize];
    NSTimeInterval duration = [controller duration];
    NSTimeInterval currentPlaybackTime = [controller currentPlaybackTime];

    info.size = size;
    info.duration = duration;
    info.currentPosition = currentPlaybackTime;
    info.isPlaying = [controller isPlaying];
    info.degree = degree;

    return info;
}

- (NSUInteger)degreeFromVideoFileWithURL:(NSURL *)url {
    NSUInteger mDegree = 0;

    AVAsset *asset = [AVAsset assetWithURL:url];
    NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if ([tracks count] > 0) {
        AVAssetTrack *videoTrack = tracks[0];
        CGAffineTransform t = videoTrack.preferredTransform;

        if (t.a == 0 && t.b == 1.0 && t.c == -1.0 && t.d == 0) {
            // Portrait
            mDegree = 90;
        } else if (t.a == 0 && t.b == -1.0 && t.c == 1.0 && t.d == 0) {
            // PortraitUpsideDown
            mDegree = 270;
        } else if (t.a == 1.0 && t.b == 0 && t.c == 0 && t.d == 1.0) {
            // LandscapeRight
            mDegree = 0;
        } else if (t.a == -1.0 && t.b == 0 && t.c == 0 && t.d == -1.0) {
            // LandscapeLeft
            mDegree = 180;
        }
    }

    return mDegree;
}

@end
