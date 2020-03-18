# GGAVAssetExportSession
由于 AVAssetExportSession 的视频导出局限性，通过 AVAssetReader 和 AVAssetWriter 做了自定义导出设置

可自定义：视频分辨率，视频码率

默认设置：H264、30FPS、码率1.3M/s、最长边分辨率不超过960（QQ、Wechat 等视频压缩大致标准）

## 用法

```objective-c
// 和AVAssetExportSession 一样通过 AVURLAsset 创建 GGAVAssetExportSession
GGAVAssetExportSession *exportSession = [[GGAVAssetExportSession alloc]  initWithAVAsset:videoAsset];

// 导出api也沿用 AVAssetExportSession 直接使用 exportAsynchronouslyWithCompletionHandler
[exportSession exportAsynchronouslyWithCompletionHandler:^(BOOL isSuccessCompress, NSError * _Nullable error) {
     // 导出后操作
}];
```

