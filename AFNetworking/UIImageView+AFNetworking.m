// UIImageView+AFNetworking.m
//
// Copyright (c) 2011 Gowalla (http://gowalla.com/)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
#import "UIImageView+AFNetworking.h"
#import "UIImage+Util.h"
#import "NSURL+Util.h"

static dispatch_queue_t image_request_operation_processing_queue() {
    static dispatch_queue_t af_image_request_operation_processing_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        af_image_request_operation_processing_queue = dispatch_queue_create("com.momenta.image-request.processing", DISPATCH_QUEUE_CONCURRENT);
    });
    
    return af_image_request_operation_processing_queue;
}

@interface AFImageCache : NSCache
- (UIImage *)cachedImageForRequest:(NSURLRequest *)request
                        withSuffix:(NSString *)suffix;
- (UIImage *)cachedImageForRequest:(NSURLRequest *)request;
- (void)cacheImage:(UIImage *)image
        forRequest:(NSURLRequest *)request;
- (void)cacheImage:(UIImage *)image
        forRequest:(NSURLRequest *)request
        withSuffix:(NSString *)suffix;
@end

#pragma mark -

static char kAFImageRequestOperationObjectKey;
static AFImageRequestOperation *playbackImageRequestOperation;
static 

@interface UIImageView (_AFNetworking)
@property (readwrite, nonatomic, strong, setter = af_setImageRequestOperation:) AFImageRequestOperation *af_imageRequestOperation;
@end

@implementation UIImageView (_AFNetworking)
@dynamic af_imageRequestOperation;
@end

#pragma mark -

@implementation UIImageView (AFNetworking)

- (AFHTTPRequestOperation *)af_imageRequestOperation {
    return (AFHTTPRequestOperation *)objc_getAssociatedObject(self, &kAFImageRequestOperationObjectKey);
}

- (void)af_setImageRequestOperation:(AFImageRequestOperation *)imageRequestOperation {
    objc_setAssociatedObject(self, &kAFImageRequestOperationObjectKey, imageRequestOperation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (NSOperationQueue *)af_sharedImageRequestOperationQueue {
    static NSOperationQueue *_af_imageRequestOperationQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _af_imageRequestOperationQueue = [[NSOperationQueue alloc] init];
        [_af_imageRequestOperationQueue setMaxConcurrentOperationCount:NSOperationQueueDefaultMaxConcurrentOperationCount];
    });

    return _af_imageRequestOperationQueue;
}

+ (AFImageCache *)af_sharedImageCache {
    static AFImageCache *_af_imageCache = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        _af_imageCache = [[AFImageCache alloc] init];
    });

    return _af_imageCache;
}


- (void)setImageWithURL:(NSURL *)url {
    [self setImageWithURL:url placeholderImage:nil];
}


- (void)setImageWithURL:(NSURL *)url
       placeholderImage:(UIImage *)placeholderImage
{
    
    [self setImageWithURL:url
         placeholderImage:placeholderImage
               themeColor:nil
     imageProcessingBlock:nil
     processedImageSuffix:nil
              cacheOnDisk:YES];
}


- (void)setImageWithURL:(NSURL *)url
       placeholderImage:(UIImage *)placeholderImage
             themeColor:(UIColor *)color
   imageProcessingBlock:(UIImage *(^)(UIImage * image, UIColor *color))imageProcessingBlock
   processedImageSuffix:(NSString *)suffix
            cacheOnDisk:(BOOL)cacheOnDisk
{
    [self cancelImageRequestOperation];
    
    if(url == nil)
    {
        if(placeholderImage) self.image = placeholderImage;
        return;
    }
    else if(url.isDefaultUserAvatarUrl)
    {
        self.image = [UIImage imageNamed:url.pathComponents.lastObject];
        return;
    }
    
    NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url];
    [urlRequest addValue:@"image/*" forHTTPHeaderField:@"Accept"];
    
    UIImage *cachedImageInMemory = [[[self class] af_sharedImageCache] cachedImageForRequest:urlRequest withSuffix:suffix];
    
    if (cachedImageInMemory)
    {
        self.image = cachedImageInMemory;
    }
    else
    {
        UIImage *cachedImageOnDisk = [UIImage imageWithCachedImageForFileName:url.filenameIdentifier withSuffix:suffix];
        if(cachedImageOnDisk)
        {
            self.image = cachedImageOnDisk;
            return;
        }
        
        if (placeholderImage) {
            self.image = placeholderImage;
        }
        
        AFImageRequestOperation *requestOperation = [AFImageRequestOperation
            imageRequestOperationWithRequest:urlRequest
            imageProcessingBlock:imageProcessingBlock
            color:color
            success:^(AFHTTPRequestOperation *operation, UIImage *image, UIImage *processedImage) {
                if ([urlRequest isEqual:[self.af_imageRequestOperation request]]) {
                    
                    dispatch_async(operation.successCallbackQueue ?: dispatch_get_main_queue(), ^(void) {
                        self.image = imageProcessingBlock && processedImage ? processedImage : image;
                    });
                    
                    if (self.af_imageRequestOperation == operation)
                    {
                        self.af_imageRequestOperation = nil;
                    }
                }
                if(cacheOnDisk)
                {
                    [image cacheImage:url.filenameIdentifier];
                }
                
                [[[self class] af_sharedImageCache] cacheImage:image forRequest:urlRequest];
                
                if(imageProcessingBlock && processedImage)
                {
                    [[[self class] af_sharedImageCache] cacheImage:processedImage
                                                        forRequest:urlRequest
                                                        withSuffix:suffix];
                }
            }
            failure:^(AFHTTPRequestOperation *operation, NSError *error){
                if ([urlRequest isEqual:[self.af_imageRequestOperation request]]) {
                    if (self.af_imageRequestOperation == operation)
                    {
                        self.af_imageRequestOperation = nil;
                    }
                }
            }];
        
        self.af_imageRequestOperation = requestOperation;
        [[[self class] af_sharedImageRequestOperationQueue] addOperation:self.af_imageRequestOperation];
    }
}


- (void)setPlaybackImageWithURL:(NSURL *)url
                        success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response))success
                        failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error))failure
{
    [self cancelPlaybackImageRequestOperation];
    
    if(url == nil)
    {
        // Illegal state
        return;
    }
    
    NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url];
    [urlRequest addValue:@"image/*" forHTTPHeaderField:@"Accept"];
    
    UIImage *cachedImage = [[[self class] af_sharedImageCache] cachedImageForRequest:urlRequest];
    
    if (cachedImage)
    {
        if (success)
        {
            success(nil, nil);
        }
        self.image = cachedImage;
    }
    else
    {
        AFImageRequestOperation *requestOperation = [[AFImageRequestOperation alloc] initWithRequest:urlRequest];
        [requestOperation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
            if ([urlRequest isEqual:[playbackImageRequestOperation request]])
            {
                dispatch_async(operation.successCallbackQueue ?: dispatch_get_main_queue(), ^(void) {
                    if (success)
                    {
                        success(operation.request, operation.response);
                    }
                    if (responseObject)
                    {
                        self.image = responseObject;
                    }
                });
                
                if (playbackImageRequestOperation == operation)
                {
                    playbackImageRequestOperation = nil;
                }
            }
            [[[self class] af_sharedImageCache] cacheImage:responseObject forRequest:urlRequest];
        }
                                                failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                                                    if ([urlRequest isEqual:[playbackImageRequestOperation request]])
                                                    {
                                                        if (failure)
                                                        {
                                                            failure(operation.request, operation.response, error);
                                                        }
                                                        
                                                        if (playbackImageRequestOperation == operation)
                                                        {
                                                            playbackImageRequestOperation = nil;
                                                        }
                                                    }
                                                }];
        
        playbackImageRequestOperation = requestOperation;
        [[[self class] af_sharedImageRequestOperationQueue] addOperation:playbackImageRequestOperation];
    }
}


- (void)cancelImageRequestOperation
{
    [self.af_imageRequestOperation cancel];
    self.af_imageRequestOperation = nil;
}

- (void)cancelPlaybackImageRequestOperation {
    [playbackImageRequestOperation cancel];
    playbackImageRequestOperation = nil;
}

@end

#pragma mark -

static inline NSString * AFImageCacheKeyFromURLRequest(NSURLRequest *request) {
    return [[request URL] absoluteString];
}

@implementation AFImageCache

- (UIImage *)cachedImageForRequest:(NSURLRequest *)request {
    
    return [self cachedImageForRequest:request withSuffix:nil];
}

- (UIImage *)cachedImageForRequest:(NSURLRequest *)request
                        withSuffix:(NSString *)suffix {
    
    switch ([request cachePolicy]) {
        case NSURLRequestReloadIgnoringCacheData:
        case NSURLRequestReloadIgnoringLocalAndRemoteCacheData:
            return nil;
        default:
            break;
    }

	return [self objectForKey:[NSString stringWithFormat:@"%@%@", AFImageCacheKeyFromURLRequest(request), suffix]];
}

- (void)cacheImage:(UIImage *)image
        forRequest:(NSURLRequest *)request
{
    [self cacheImage:image forRequest:request withSuffix:nil];
}

- (void)cacheImage:(UIImage *)image
        forRequest:(NSURLRequest *)request
        withSuffix:(NSString *)suffix
{
    if (image && request) {
        [self setObject:image forKey:[NSString stringWithFormat:@"%@%@", AFImageCacheKeyFromURLRequest(request), suffix]];
    }
}

@end

#endif
