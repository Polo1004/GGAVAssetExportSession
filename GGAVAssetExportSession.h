//
//  GGAVAssetExportSession.h
//
//
//  Created by PoloChen on 2019/3/8.
//  Copyright © 2019 Polo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GGAVAssetExportSession : NSObject

/**
 视频导出配置
 */
@property (strong, nonatomic, nullable) NSDictionary *videoOutputSetting;

/**
 音频导出配置
 */
@property (strong, nonatomic, nullable) NSDictionary *audioOutputSetting;

//@property (copy, nonatomic, nullable) AVVideoComposition *videoComposition;

// 视频导出类型
@property (copy, nonatomic, nullable) NSString *outputFileType;

// 视频导出路径
@property (copy, nonatomic, nullable) NSURL *outputURL;

// 视频分辨率
@property (assign, nonatomic, nullable) CGFloat videoWidth;
@property (assign, nonatomic, nullable) CGFloat videoHeight;

- (instancetype)initWithAVAsset:(AVAsset *)avasset;

- (void)exportAsynchronouslyWithCompletionHandler:(void (^)(BOOL isSuccessCompress, NSError * _Nullable error))handler;

@end

NS_ASSUME_NONNULL_END
