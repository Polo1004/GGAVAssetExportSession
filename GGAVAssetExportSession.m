//
//  GGAVAssetExportSession.m
//  
//
//  Created by PoloChen on 2019/3/8.
//  Copyright © 2019 Polo. All rights reserved.
//

#import "GGAVAssetExportSession.h"

#ifdef __cplusplus
#define PERFORM_SAFE_BLOCK(block, ...)          if (block) { block(__VA_ARGS__); }
#else
#define PERFORM_SAFE_BLOCK(block, ...)          (block) ? block(__VA_ARGS__) : nil;
#endif

// 视频最长边
static const CGFloat kVideoMaxSide = 960;

// 视频最大平均码率 1.3 M/s (QQ,weChat 平均数值)
static const NSInteger kVideoMaxAverageBitRate = 130 * 8 * 1024;

// 视频帧率
static const NSInteger kVideoFrameRate = 30;

@interface GGAVAssetExportSession ()

@property (strong, nonatomic) AVURLAsset *currentAsset;

@property (strong, nonatomic) AVAssetReader *reader;
@property (strong, nonatomic) AVAssetWriter *writer;

@property (strong, nonatomic) AVAssetReaderVideoCompositionOutput *videoReaderTrackOutput;
@property (strong, nonatomic) AVAssetReaderTrackOutput *audioReaderTrackOutput;

@property (strong, nonatomic) AVAssetWriterInput *videoWriterInput;
@property (strong, nonatomic) AVAssetWriterInput *audioWriterInput;

@property (strong, nonatomic) dispatch_queue_t currentUtilQueue;
@property (strong, nonatomic) dispatch_queue_t videoWriterQueue;
@property (strong, nonatomic) dispatch_queue_t audioWriterQueue;


@property (assign, nonatomic) BOOL videoWriterComplete;
@property (assign, nonatomic) BOOL audioWriterComplete;

@property (copy, nonatomic) void (^completionHandler)(BOOL isSuccessCompress, NSError * _Nullable error);
@end

@implementation GGAVAssetExportSession

// MARK:- init

- (instancetype)initWithAVAsset:(AVAsset *)avasset {
    if (self = [super init]) {
        
        _currentAsset = (AVURLAsset *)avasset;
        
        _currentUtilQueue    = dispatch_queue_create("currentUtilQueue", DISPATCH_QUEUE_SERIAL);
        _videoWriterQueue    = dispatch_queue_create("videoWriterQueue", DISPATCH_QUEUE_SERIAL);
        _audioWriterQueue    = dispatch_queue_create("audioWriterQueue", DISPATCH_QUEUE_SERIAL);

        _videoWriterComplete = NO;
        _audioWriterComplete = NO;
    }
    return self;
}

// MARK:- Get Method

// 导出视频 设置
- (NSDictionary *)videoOutputSetting {
    if (!_videoOutputSetting) {
        CGFloat ratio = _videoWidth / _videoHeight;
        if (_videoWidth > kVideoMaxSide && _videoWidth >= _videoHeight) {
            _videoWidth = kVideoMaxSide;
            _videoHeight = _videoWidth / ratio;
        }else if (_videoHeight > kVideoMaxSide && _videoHeight >= _videoWidth){
            _videoHeight = kVideoMaxSide;
            _videoWidth = _videoHeight * ratio;
        }
        _videoOutputSetting = @{
                               AVVideoCodecKey: AVVideoCodecH264,
                               AVVideoWidthKey: @(_videoWidth),
                               AVVideoHeightKey: @(_videoHeight),
                               AVVideoCompressionPropertiesKey: @
                               {
                               AVVideoAverageBitRateKey: @(kVideoMaxAverageBitRate),
                               AVVideoProfileLevelKey: AVVideoProfileLevelH264High40,
                               },
                               };
    }
    return _videoOutputSetting;
}
// 导出音频 设置
- (NSDictionary *)audioOutputSetting {
    if (!_audioOutputSetting) {
        _audioOutputSetting = @{
                                AVFormatIDKey: @(kAudioFormatMPEG4AAC),
                                AVNumberOfChannelsKey: @1,
                                AVSampleRateKey: @44100,
                                AVEncoderBitRateKey: @128000,
                                };
    }
    return _audioOutputSetting;
}

- (NSString *)outputFileType {
    if (!_outputFileType) {
        _outputFileType = AVFileTypeMPEG4;
    }
    return _outputFileType;
}
//导出路径
- (NSURL *)outputURL {
    if (!_outputURL) {
        NSString *outputPath = [NSHomeDirectory() stringByAppendingFormat:@"/tmp/"];
        NSString *fileName;
        NSDate *datenow = [NSDate date];
        NSString *timeSp = [NSString stringWithFormat:@"%ld", (long)[datenow timeIntervalSince1970]*1000];
        if (_currentAsset.URL && _currentAsset.URL.lastPathComponent) {
            fileName = _currentAsset.URL.lastPathComponent;
            //时间戳_IMG_XXXX.MP4
            outputPath = [outputPath stringByAppendingFormat:@"%@_%@",timeSp,fileName];
        }else {
            //没有url 拼写一个格式:IMG_(现在时间的时间戳).MP4
            fileName = [NSString stringWithFormat:@"IMG_%@.MP4",timeSp];
            outputPath = [outputPath stringByAppendingFormat:@"%@",fileName];
        }
        NSURL *outputURL = [NSURL fileURLWithPath:outputPath];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:[NSHomeDirectory() stringByAppendingFormat:@"/tmp"]]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:[NSHomeDirectory() stringByAppendingFormat:@"/tmp"] withIntermediateDirectories:YES attributes:nil error:nil];
        }
        _outputURL = outputURL;
    }
    return _outputURL;
}

// 默认视频大小 960 x 540
- (CGFloat)videoWidth {
    if (!_videoWidth) {
        _videoWidth = kVideoMaxSide;
    }
    return _videoWidth;
}

- (CGFloat)videoHeight {
    if (!_videoHeight) {
        _videoHeight = 540;
    }
    return _videoHeight;
}

// MARK:- Create Reader and Writer

- (void)exportAsynchronouslyWithCompletionHandler:(void (^)(BOOL isSuccessCompress, NSError * _Nullable error))handler {
    
    self.completionHandler = handler;
    
    if (![self judgeVideoIsComplianceWithStandards:self.currentAsset]) {
        NSError *unCompressError = [NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey:@"⚠️⚠️⚠️ 这个视频符合标准 不需要压缩 !!!"}];
        PERFORM_SAFE_BLOCK(handler, NO, unCompressError);
        return;
    }
    
    [self.currentAsset loadValuesAsynchronouslyForKeys:@[@"tracks"] completionHandler:^{
        dispatch_async(_currentUtilQueue, ^{
            NSError *error;
            if ([self.currentAsset statusOfValueForKey:@"tracks" error:&error] == AVKeyValueStatusLoaded) {
                if ([self setupAssetReaderAndWriter:&error]) {
                    [self starReadingAndWriting];
                }
                else {
                    PERFORM_SAFE_BLOCK(handler, NO, error);
                }
            }
            else {
                PERFORM_SAFE_BLOCK(handler, NO, error);
            }
        });
    }];
}

- (BOOL)setupAssetReaderAndWriter:(NSError **)error {
    self.reader = [[AVAssetReader alloc] initWithAsset:self.currentAsset error:error];
    if (*error) {
        NSLog(@"⚠️⚠️⚠️ reader create fail !!!");
        return NO;
    }
    self.writer = [[AVAssetWriter alloc] initWithURL:self.outputURL fileType:self.outputFileType error:error];
    if (*error) {
        NSLog(@"⚠️⚠️⚠️ writer create fail !!!");
        return NO;
    }
    
    if (self.reader && self.writer) {
        AVAssetTrack *audioTrack = [self.currentAsset tracksWithMediaType:AVMediaTypeAudio].firstObject;
        if (audioTrack) {
            NSDictionary *unCompressAudioSettrings = @{
                                                       AVFormatIDKey : @(kAudioFormatLinearPCM)
                                                       };
            self.audioReaderTrackOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:audioTrack outputSettings:unCompressAudioSettrings];
            if ([self.reader canAddOutput:self.audioReaderTrackOutput]) {
                [self.reader addOutput:self.audioReaderTrackOutput];
            }
            
            self.audioWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:self.audioOutputSetting];
            if ([self.writer canAddInput:self.audioWriterInput]) {
                [self.writer addInput:self.audioWriterInput];
            }
        }
        
        AVAssetTrack *videoTrack = [self.currentAsset tracksWithMediaType:AVMediaTypeVideo].firstObject;
        if (videoTrack) {
            NSDictionary *unCompressVideoSettings = @{
                                                      (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_422YpCbCr8)
                                                      };
            self.videoReaderTrackOutput = [AVAssetReaderVideoCompositionOutput assetReaderVideoCompositionOutputWithVideoTracks:@[videoTrack] videoSettings:unCompressVideoSettings];
            if (self.videoComposition) {
                self.videoReaderTrackOutput.videoComposition = self.videoComposition;
            }else {
                AVMutableVideoComposition *videoComposition = [self fixedCompositionWithAsset:videoAsset];
                if (videoComposition.renderSize.width) {
                    // 修正视频转向
                    self.videoReaderTrackOutput.videoComposition = videoComposition;
                }
//                self.videoReaderTrackOutput.videoComposition = [self buildDefaultVideoComposition];
            }
            if ([self.reader canAddOutput:self.videoReaderTrackOutput]) {
                [self.reader addOutput:self.videoReaderTrackOutput];
            }
    
            self.videoWriterInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:self.videoOutputSetting];
            if ([self.writer canAddInput:self.videoWriterInput]) {
                [self.writer addInput:self.videoWriterInput];
            }
        }
        return YES;
    }
    else {
        if (!*error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey:@"⚠️⚠️⚠️ reader and writer create fail !!!"}];
        }
        return NO;
    }
}

- (void)starReadingAndWriting {
    //开始读取资源
    if (![self.reader startReading]) {
        PERFORM_SAFE_BLOCK(self.completionHandler, NO, self.reader.error);
        self.completionHandler = nil;
        return ;
    }
    
    if (![self.writer startWriting]) {
        PERFORM_SAFE_BLOCK(self.completionHandler, NO, self.writer.error);
        self.completionHandler = nil;
        return ;
    }
    //创建一个 队列group 进行 音频和视频 资源的 交叉写入
    dispatch_group_t compressExportGroup = dispatch_group_create();
    //开启一个写入会话
    [self.writer startSessionAtSourceTime:kCMTimeZero];
    
    //音频写入
    if (self.audioWriterInput) {
        dispatch_group_enter(compressExportGroup);
        [self.audioWriterInput requestMediaDataWhenReadyOnQueue:self.audioWriterQueue usingBlock:^{
            if (self.audioWriterComplete) {
                return ;
            }
            
            BOOL completeOrFaild = NO;
            
            while ([self.audioWriterInput isReadyForMoreMediaData] && !completeOrFaild) {
                CMSampleBufferRef sampleBuffer = [self.audioReaderTrackOutput copyNextSampleBuffer];
                if (sampleBuffer != NULL) {
                    BOOL success = [self.audioWriterInput appendSampleBuffer:sampleBuffer];
                    CFRelease(sampleBuffer);
                    sampleBuffer = NULL;
                    completeOrFaild = !success;
                }else {
                    completeOrFaild = YES;
                }
            }
            
            if (completeOrFaild) {
                BOOL oldFinished = self.audioWriterComplete;
                self.audioWriterComplete = YES;
                if (!oldFinished) {
                    [self.audioWriterInput markAsFinished];
                }
                dispatch_group_leave(compressExportGroup);
            }
        }];
    }
    else {
        //该视频无音轨输入 默认音频导出完成
        NSLog(@"This video not exist audio track !!!");
        self.audioWriterComplete = YES;
    }
    
    //视频写入
    if (self.videoWriterInput) {
        dispatch_group_enter(compressExportGroup);
        __block NSInteger sampleNum = 0;
        [self.videoWriterInput requestMediaDataWhenReadyOnQueue:self.videoWriterQueue usingBlock:^{
            if (self.videoWriterComplete) {
                return ;
            }
            
            BOOL completeOrFaild = NO;
            NSLog(@"isReadyForMoreMediaData : %d  count:%ld",[NSNumber numberWithBool:self.videoWriterInput.isReadyForMoreMediaData].intValue,sampleNum);
            while ([self.videoWriterInput isReadyForMoreMediaData] && !completeOrFaild) {
                CMSampleBufferRef sampleBuffer = [self.videoReaderTrackOutput copyNextSampleBuffer];
                if (sampleBuffer != NULL) {
                    BOOL success = [self.videoWriterInput appendSampleBuffer:sampleBuffer];
                    ++sampleNum;
                    CFRelease(sampleBuffer);
                    sampleBuffer = NULL;
                    completeOrFaild = !success;
                }else {
                    completeOrFaild = YES;
                }
            }
            
            if (completeOrFaild) {
                BOOL oldFinished = self.videoWriterComplete;
                self.videoWriterComplete = YES;
                if (!oldFinished) {
                    [self.videoWriterInput markAsFinished];
                }
                dispatch_group_leave(compressExportGroup);
            }
        }];
    }
    else {
        //该视频无视频轨输入 默认该视频导出失败
        NSError *noVideoTrackError = [NSError errorWithDomain:NSCocoaErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey:@"❌ This video not exist video track !!! Uncomplete to export this video!"}];
        PERFORM_SAFE_BLOCK(self.completionHandler, NO, noVideoTrackError);
        self.completionHandler = nil;
        return ;
    }
    //写入完成回调
    dispatch_group_notify(compressExportGroup, self.currentUtilQueue, ^{
        if (self.videoWriterComplete && self.audioWriterComplete) {
            [self.writer finishWritingWithCompletionHandler:^{
                AVAssetWriterStatus status = self.writer.status;
                switch (status) {
                    case AVAssetWriterStatusCompleted : {
                        PERFORM_SAFE_BLOCK(self.completionHandler, YES, nil);
                        self.completionHandler = nil;
                        break;
                    }
                    case AVAssetWriterStatusFailed :
                    case AVAssetWriterStatusCancelled :
                    case AVAssetWriterStatusUnknown : {
                        PERFORM_SAFE_BLOCK(self.completionHandler, NO, self.writer.error);
                        self.completionHandler = nil;
                        break;
                    }  
                    default:
                        break;
                }
            }];
        }
        else {
            NSLog(@"❌ Uncomplete to export this video!!! \n videoWriter:%d audioWriter:%d",[NSNumber numberWithBool:self.videoWriterComplete].intValue,[NSNumber numberWithBool:self.audioWriterComplete].intValue);
            PERFORM_SAFE_BLOCK(self.completionHandler, NO, self.writer.error);
            self.completionHandler = nil;
        }
    });
}

// MARK:- helper

/**
 此方法的判断条件可自由修改
 */
- (BOOL)judgeVideoIsComplianceWithStandards:(AVAsset *)avasset {
    AVURLAsset *videoAsset = (AVURLAsset*)avasset;
    AVAssetTrack *track = [[videoAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    
    //获取分辨率 码率 帧数 视频编码
    {
        
        CGSize trackDimensions = {
            .width = 0.0,
            .height = 0.0,
        };
        trackDimensions = [track naturalSize];
        
        CGFloat width = trackDimensions.width;
        CGFloat heigth = trackDimensions.height;
        NSLog(@"像素 %f x %f",width,heigth);
        
        float frameRate = [track nominalFrameRate];
        float bps = [track estimatedDataRate];
        
        NSLog(@"帧率 %f fps",frameRate);
        NSLog(@"比特率 %f kbps",bps/1024);
        
        CMFormatDescriptionRef videoFormatDescription = (__bridge CMFormatDescriptionRef)([track formatDescriptions].firstObject);
        FourCharCode codeType = CMFormatDescriptionGetMediaSubType(videoFormatDescription);
        if (codeType == 'avc1') {
            NSLog(@"yes H.264");
        }
        else {
            NSLog(@"no H.264");
            NSLog(@"视频非H.264编码 需要转码");
            return YES;
        }
        if (bps > (kVideoMaxAverageBitRate)) {
            NSLog(@"视频码率大于1.3 MBps 需要转码");
            return YES;
        }
        if (width > kVideoMaxSide || heigth > kVideoMaxSide) {
            NSLog(@"视频分辨率大于 %.0fx540 需要转码",kVideoMaxSide);
            return YES;
        }
        if (frameRate > 30) {
            NSLog(@"视频帧率大于30FPS 需要转码");
            return YES;
        }
        
    }
    
    return NO;
}

// 摘自 SDAVAssetExportSession
- (AVMutableVideoComposition *)buildDefaultVideoComposition
{
    AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
    AVAssetTrack *videoTrack = [[self.currentAsset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
    
    // get the frame rate from videoSettings, if not set then try to get it from the video track,
    // if not set (mainly when asset is AVComposition) then use the default frame rate of 30
    float trackFrameRate = 0;
    if (self.videoOutputSetting)
    {
        NSDictionary *videoCompressionProperties = [self.videoOutputSetting objectForKey:AVVideoCompressionPropertiesKey];
        if (videoCompressionProperties)
        {
            NSNumber *frameRate = [videoCompressionProperties objectForKey:AVVideoAverageNonDroppableFrameRateKey];
            if (frameRate)
            {
                trackFrameRate = frameRate.floatValue;
            }
        }
    }
    else
    {
        trackFrameRate = [videoTrack nominalFrameRate];
    }
    
    if (trackFrameRate == 0)
    {
        trackFrameRate = 30;
    }
    
    videoComposition.frameDuration = CMTimeMake(1, trackFrameRate);
    CGSize targetSize = CGSizeMake([self.videoOutputSetting[AVVideoWidthKey] floatValue], [self.videoOutputSetting[AVVideoHeightKey] floatValue]);
    CGSize naturalSize = [videoTrack naturalSize];
    CGAffineTransform transform = videoTrack.preferredTransform;
    // Workaround radar 31928389, see https://github.com/rs/SDAVAssetExportSession/pull/70 for more info
    if (transform.ty == -560) {
        transform.ty = 0;
    }
    
    if (transform.tx == -560) {
        transform.tx = 0;
    }
    
    CGFloat videoAngleInDegree  = atan2(transform.b, transform.a) * 180 / M_PI;
    if (videoAngleInDegree == 90 || videoAngleInDegree == -90) {
        CGFloat width = naturalSize.width;
        naturalSize.width = naturalSize.height;
        naturalSize.height = width;
    }
    videoComposition.renderSize = naturalSize;
    // center inside
    {
        float ratio;
        float xratio = targetSize.width / naturalSize.width;
        float yratio = targetSize.height / naturalSize.height;
        ratio = MIN(xratio, yratio);
        
        float postWidth = naturalSize.width * ratio;
        float postHeight = naturalSize.height * ratio;
        float transx = (targetSize.width - postWidth) / 2;
        float transy = (targetSize.height - postHeight) / 2;
        
        CGAffineTransform matrix = CGAffineTransformMakeTranslation(transx / xratio, transy / yratio);
        matrix = CGAffineTransformScale(matrix, ratio / xratio, ratio / yratio);
        transform = CGAffineTransformConcat(transform, matrix);
    }
    
    // Make a "pass through video track" video composition.
    AVMutableVideoCompositionInstruction *passThroughInstruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    passThroughInstruction.timeRange = CMTimeRangeMake(kCMTimeZero, self.currentAsset.duration);
    
    AVMutableVideoCompositionLayerInstruction *passThroughLayer = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];
    
    [passThroughLayer setTransform:transform atTime:kCMTimeZero];
    
    passThroughInstruction.layerInstructions = @[passThroughLayer];
    videoComposition.instructions = @[passThroughInstruction];
    
    return videoComposition;
}


// 方法摘自 TZImagePickerController
/// 获取优化后的视频转向信息
- (AVMutableVideoComposition *)fixedCompositionWithAsset:(AVAsset *)videoAsset {
    AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
    // 视频转向
    int degrees = [self degressFromVideoFileWithAsset:videoAsset];
    if (degrees != 0) {
        CGAffineTransform translateToCenter;
        CGAffineTransform mixedTransform;
        videoComposition.frameDuration = CMTimeMake(1, 30);
        
        NSArray *tracks = [videoAsset tracksWithMediaType:AVMediaTypeVideo];
        AVAssetTrack *videoTrack = [tracks objectAtIndex:0];
        
        AVMutableVideoCompositionInstruction *roateInstruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        roateInstruction.timeRange = CMTimeRangeMake(kCMTimeZero, [videoAsset duration]);
        AVMutableVideoCompositionLayerInstruction *roateLayerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];
        
        if (degrees == 90) {
            // 顺时针旋转90°
            translateToCenter = CGAffineTransformMakeTranslation(videoTrack.naturalSize.height, 0.0);
            mixedTransform = CGAffineTransformRotate(translateToCenter,M_PI_2);
            videoComposition.renderSize = CGSizeMake(videoTrack.naturalSize.height,videoTrack.naturalSize.width);
            [roateLayerInstruction setTransform:mixedTransform atTime:kCMTimeZero];
        } else if(degrees == 180){
            // 顺时针旋转180°
            translateToCenter = CGAffineTransformMakeTranslation(videoTrack.naturalSize.width, videoTrack.naturalSize.height);
            mixedTransform = CGAffineTransformRotate(translateToCenter,M_PI);
            videoComposition.renderSize = CGSizeMake(videoTrack.naturalSize.width,videoTrack.naturalSize.height);
            [roateLayerInstruction setTransform:mixedTransform atTime:kCMTimeZero];
        } else if(degrees == 270){
            // 顺时针旋转270°
            translateToCenter = CGAffineTransformMakeTranslation(0.0, videoTrack.naturalSize.width);
            mixedTransform = CGAffineTransformRotate(translateToCenter,M_PI_2*3.0);
            videoComposition.renderSize = CGSizeMake(videoTrack.naturalSize.height,videoTrack.naturalSize.width);
            [roateLayerInstruction setTransform:mixedTransform atTime:kCMTimeZero];
        }
        
        roateInstruction.layerInstructions = @[roateLayerInstruction];
        // 加入视频方向信息
        videoComposition.instructions = @[roateInstruction];
    }
    return videoComposition;
}

/// 获取视频角度
- (int)degressFromVideoFileWithAsset:(AVAsset *)asset {
    int degress = 0;
    NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if([tracks count] > 0) {
        AVAssetTrack *videoTrack = [tracks objectAtIndex:0];
        CGAffineTransform t = videoTrack.preferredTransform;
        if(t.a == 0 && t.b == 1.0 && t.c == -1.0 && t.d == 0){
            // Portrait
            degress = 90;
        } else if(t.a == 0 && t.b == -1.0 && t.c == 1.0 && t.d == 0){
            // PortraitUpsideDown
            degress = 270;
        } else if(t.a == 1.0 && t.b == 0 && t.c == 0 && t.d == 1.0){
            // LandscapeRight
            degress = 0;
        } else if(t.a == -1.0 && t.b == 0 && t.c == 0 && t.d == -1.0){
            // LandscapeLeft
            degress = 180;
        }
    }
    return degress;
}

@end
